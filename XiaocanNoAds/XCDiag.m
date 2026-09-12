//
//  XCDiag.m
//  XiaocanNoAds
//

#import "XCDiag.h"
#import <UIKit/UIKit.h>

static NSString *const kXCDiagDirName = @"XiaocanNoAds";
static const unsigned long long kXCDiagMaxBytes = 16ULL * 1024ULL * 1024ULL; // 16MB 上限
static const NSUInteger kXCDiagMaxHTTPRecords = 400;
static const NSUInteger kXCDiagMaxJSONRecords = 500;
static const NSUInteger kXCDiagBodyPreview = 6000;   // 每个 body 最多记录字符数

@interface XCDiag ()
@property (nonatomic, assign) NSUInteger httpCount;
@property (nonatomic, assign) NSUInteger jsonCount;
+ (NSString *)_preview:(NSString *)text;
@end

@implementation XCDiag {
    dispatch_queue_t _q;
    NSFileHandle    *_fh;
    unsigned long long _written;
    NSDateFormatter *_fmt;
    NSDateFormatter *_dayFmt;
}

+ (instancetype)shared {
    static XCDiag *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[XCDiag alloc] init];
    });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // ⚠️ 只做最轻量的事：创建队列 + 设默认值。
        //    绝不在 dyld 加载期碰文件系统或 NSDateFormatter，否则启动闪退。
        _q = dispatch_queue_create("com.xiaocan.noads.diag", DISPATCH_QUEUE_SERIAL);
        _captureEnabled = YES;
        _captureJSON    = YES;
    }
    return self;
}

#pragma mark - Paths

+ (NSString *)logDirPath {
    NSArray<NSString *> *docs =
        NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *base = docs.firstObject;
    if (base.length == 0) base = NSTemporaryDirectory();
    // 注意：这里不创建目录（可能在 dyld 加载期被调用）。
    //       目录创建统一放在 _append: 的异步块里。
    return [base stringByAppendingPathComponent:kXCDiagDirName];
}

+ (NSString *)logFilePath {
    return [[self logDirPath] stringByAppendingPathComponent:@"diag.log"];
}

+ (NSData *)logData {
    NSString *p = [self logFilePath];
    NSData *d = [NSData dataWithContentsOfFile:p];
    return d ?: [NSData data];
}

+ (unsigned long long)logSize {
    NSDictionary *attr = [[NSFileManager defaultManager] attributesOfItemAtPath:[self logFilePath] error:NULL];
    return attr.fileSize;
}

+ (void)clearLog {
    XCDiag *s = [self shared];
    dispatch_async(s->_q, ^{
        [s->_fh closeFile];
        s->_fh = nil;
        s->_written = 0;
        [[NSFileManager defaultManager] removeItemAtPath:[self logFilePath] error:NULL];
    });
}

#pragma mark - Internal write

- (void)_append:(NSString *)text at:(NSDate *)date {
    if (text.length == 0) return;

    dispatch_async(_q, ^{
        // ── 懒创建格式化器（此时已脱离 dyld 加载期）──
        if (self->_fmt == nil) {
            self->_fmt = [[NSDateFormatter alloc] init];
            self->_fmt.dateFormat = @"HH:mm:ss.SSS";

            self->_dayFmt = [[NSDateFormatter alloc] init];
            self->_dayFmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        }

        // ── 懒创建目录 + 文件 ──
        if (self->_fh == nil) {
            NSString *dir = [XCDiag logDirPath];
            [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                     withIntermediateDirectories:YES
                                                      attributes:nil
                                                           error:NULL];

            NSString *path = [XCDiag logFilePath];
            NSFileManager *fm = [NSFileManager defaultManager];
            if (![fm fileExistsAtPath:path]) {
                [fm createFileAtPath:path contents:nil attributes:nil];
            }
            self->_fh = [NSFileHandle fileHandleForWritingAtPath:path];
            [self->_fh seekToEndOfFile];

            NSDictionary *attr = [fm attributesOfItemAtPath:path error:NULL];
            self->_written = attr.fileSize;

            NSString *head = [NSString stringWithFormat:
                @"\n===== XiaocanNoAds 诊断日志 =====\n"
                @"启动: %@\n"
                @"进程: %@\n"
                @"=====\n\n",
                [self->_dayFmt stringFromDate:date],
                [NSProcessInfo processInfo].processName];
            NSData *hd = [head dataUsingEncoding:NSUTF8StringEncoding];
            [self->_fh writeData:hd];
            self->_written += hd.length;
        }

        if (self->_written >= kXCDiagMaxBytes) {
            return;
        }

        NSString *ts = [self->_fmt stringFromDate:date];
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", ts, text];
        NSData *d = [line dataUsingEncoding:NSUTF8StringEncoding];
        [self->_fh writeData:d];
        self->_written += d.length;
    });
}

#pragma mark - Logging

+ (void)log:(NSString *)format, ... {
    va_list ap;
    va_start(ap, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);
    [self logLine:msg];
}

+ (void)logLine:(NSString *)line {
    XCDiag *s = [self shared];
    // 时间戳格式化推迟到异步块里，避免在 dyld 加载期创建 NSDateFormatter
    [s _append:line at:[NSDate date]];
}

#pragma mark - HTTP

+ (void)recordHTTP:(NSString *)url
            method:(NSString *)method
       requestBody:(NSData *)reqBody
      responseCode:(NSInteger)code
      responseBody:(NSData *)respBody {

    XCDiag *s = [self shared];
    if (!s.captureEnabled) return;
    if (url.length == 0) return;

    // 静态资源 / 图片不记，避免刷屏
    NSString *lower = url.lowercaseString;
    if ([lower hasSuffix:@".png"] || [lower hasSuffix:@".jpg"] || [lower hasSuffix:@".jpeg"] ||
        [lower hasSuffix:@".webp"] || [lower hasSuffix:@".gif"] || [lower hasSuffix:@".svg"] ||
        [lower hasSuffix:@".css"] || [lower hasSuffix:@".js"] || [lower hasSuffix:@".woff"] ||
        [lower hasSuffix:@".ttf"] || [lower hasSuffix:@".mp4"] || [lower hasSuffix:@".zip"]) {
        return;
    }

    if (s.httpCount >= kXCDiagMaxHTTPRecords) return;
    s.httpCount = s.httpCount + 1;

    NSMutableString *m = [NSMutableString string];
    [m appendFormat:@"\n──── HTTP #%lu ────\n", (unsigned long)s.httpCount];
    [m appendFormat:@"%@ %@\n", method.length ? method : @"GET", url];
    [m appendFormat:@"状态: %ld\n", (long)code];

    if (reqBody.length > 0) {
        NSString *rb = [[NSString alloc] initWithData:reqBody encoding:NSUTF8StringEncoding];
        if (rb.length > 0) {
            [m appendFormat:@"请求体: %@\n", [self _preview:rb]];
        } else {
            [m appendFormat:@"请求体: <%lu 字节二进制>\n", (unsigned long)reqBody.length];
        }
    }

    if (respBody.length > 0) {
        NSString *body = [[NSString alloc] initWithData:respBody encoding:NSUTF8StringEncoding];
        if (body.length > 0) {
            [m appendFormat:@"响应体: %@\n", [self _preview:body]];
        } else {
            [m appendFormat:@"响应体: <%lu 字节，非 UTF-8>\n", (unsigned long)respBody.length];
        }
    }

    [self logLine:m];
}

+ (NSString *)_preview:(NSString *)text {
    if (text.length <= kXCDiagBodyPreview) return text;
    return [NSString stringWithFormat:@"%@…（共 %lu 字符，已截断）",
            [text substringToIndex:kXCDiagBodyPreview], (unsigned long)text.length];
}

#pragma mark - JSON

+ (void)recordJSON:(id)json source:(NSString *)source {
    XCDiag *s = [self shared];
    if (!s.captureEnabled || !s.captureJSON) return;
    if (json == nil) return;
    if (s.jsonCount >= kXCDiagMaxJSONRecords) return;

    NSString *desc = nil;
    @try {
        NSError *err = nil;
        NSData *d = [NSJSONSerialization dataWithJSONObject:json options:0 error:&err];
        if (d.length > 0) {
            desc = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        }
    } @catch (__unused NSException *e) {
        desc = nil;
    }

    if (desc.length == 0) {
        @try {
            desc = [json description];
        } @catch (__unused NSException *e) {
            desc = @"<无法序列化>";
        }
    }

    if (desc.length == 0) return;

    // 跳过系统数据（iOS 框架清单之类的大块无用 JSON），把配额留给 App 数据
    if (desc.length > 50000 && [desc containsString:@"\"platforms\""]) {
        return;
    }

    s.jsonCount = s.jsonCount + 1;

    NSMutableString *m = [NSMutableString string];
    [m appendFormat:@"\n──── JSON #%lu ────\n", (unsigned long)s.jsonCount];
    if (source.length) [m appendFormat:@"来源: %@\n", source];
    [m appendFormat:@"%@\n", [self _preview:desc]];
    [self logLine:m];
}

@end
