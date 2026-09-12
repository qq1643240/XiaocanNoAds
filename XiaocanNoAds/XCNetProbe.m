//
//  XCNetProbe.m
//  XiaocanNoAds
//

#import "XCNetProbe.h"
#import "XCNoAdsConfig.h"
#import "XCDiag.h"
#import "XCJSONScrubber.h"

static NSString *const kHandledKey = @"XCNetProbeHandled";
static const NSUInteger kAPIBodyMaxLog = 150000;   // 接口响应最多记录字符数

static BOOL XCIsAppAPIHost(NSURL *url) {
    NSString *h = url.host.lowercaseString;
    if (h.length == 0) return NO;
    return [h containsString:@"xiaocantech"]
        || [h containsString:@"realtech"]
        || [h containsString:@"hzaiguojiang"]
        || [h containsString:@"xinyifm"]
        || [h containsString:@"djtaoke"];
}

#pragma mark - Protocol

@interface XCProbeProtocol : NSURLProtocol
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDataTask *task;
@end

@implementation XCProbeProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    XCNoAdsConfig *cfg = [XCNoAdsConfig shared];
    if (!cfg.enabled) return NO;
    if (!cfg.captureNet && !cfg.scrubPromoJSON) return NO;
    if ([NSURLProtocol propertyForKey:kHandledKey inRequest:request]) return NO;

    NSString *scheme = request.URL.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) return NO;

    return XCIsAppAPIHost(request.URL);
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSMutableURLRequest *req = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:kHandledKey inRequest:req];

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *s = [NSURLSession sessionWithConfiguration:cfg];
    self.session = s;

    __weak typeof(self) wself = self;
    self.task = [s dataTaskWithRequest:req
                    completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        __strong typeof(wself) sself = wself;
        if (sself == nil) return;

        if (err) {
            [sself.client URLProtocol:sself didFailWithError:err];
            return;
        }

        NSData *outData = data;

        @try {
            NSInteger code = 0;
            if ([resp isKindOfClass:[NSHTTPURLResponse class]]) {
                code = ((NSHTTPURLResponse *)resp).statusCode;
            }

            // ── 记录原始响应（这是定位推广位的关键数据）──
            if ([XCNoAdsConfig shared].captureNet) {
                NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (body.length > kAPIBodyMaxLog) {
                    body = [body substringToIndex:kAPIBodyMaxLog];
                }
                [XCDiag log:@"[API] %@ %@\n状态: %ld\n响应: %@",
                    req.HTTPMethod ?: @"GET", req.URL.absoluteString,
                    (long)code, body ?: @"<非文本>"];
            }

            // ── 按需清洗 ──
            if ([XCNoAdsConfig shared].scrubPromoJSON && data.length > 0) {
                id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
                if (json) {
                    NSUInteger removed = 0;
                    id scrubbed = [XCJSONScrubber scrubJSON:json removed:&removed];
                    if (removed > 0) {
                        NSData *nd = [NSJSONSerialization dataWithJSONObject:scrubbed options:0 error:NULL];
                        if (nd.length > 0) outData = nd;
                        [XCDiag log:@"[清洗] %@ 移除 %lu 个节点",
                            req.URL.absoluteString, (unsigned long)removed];
                    }
                }
            }
        } @catch (__unused NSException *e) {
            outData = data;
        }

        if (resp) {
            [sself.client URLProtocol:sself didReceiveResponse:resp
                                            cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        }
        if (outData) {
            [sself.client URLProtocol:sself didLoadData:outData];
        }
        [sself.client URLProtocolDidFinishLoading:sself];
    }];

    [self.task resume];
}

- (void)stopLoading {
    [self.task cancel];
    self.task = nil;
    [self.session invalidateAndCancel];
    self.session = nil;
}

@end

#pragma mark - Install

@implementation XCNetProbe

+ (void)install {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @try {
            [NSURLProtocol registerClass:[XCProbeProtocol class]];
            [XCDiag log:@"[探针] 已注册，拦截域名: xiaocantech / realtech / hzaiguojiang / xinyifm / djtaoke"];
        } @catch (__unused NSException *e) {
        }
    });
}

@end
