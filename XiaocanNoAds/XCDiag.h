//
//  XCDiag.h
//  XiaocanNoAds
//
//  诊断模块：把插件加载状态、网络请求、JSON 响应写入日志文件，
//  便于定位「到底哪条链路在渲染广告」。
//  日志位置：<App Documents>/XiaocanNoAds/diag.log
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface XCDiag : NSObject

+ (instancetype)shared;

/// 是否记录网络请求（默认 YES）
@property (nonatomic, assign) BOOL captureEnabled;

/// 是否记录 JSON 响应体（默认 YES）
@property (nonatomic, assign) BOOL captureJSON;

/// 写一行日志（线程安全）
+ (void)log:(NSString *)format, ...;
+ (void)logLine:(NSString *)line;

/// 记录一次 HTTP 往返
+ (void)recordHTTP:(NSString *)url
           method:(nullable NSString *)method
       requestBody:(nullable NSData *)reqBody
      responseCode:(NSInteger)code
      responseBody:(nullable NSData *)respBody;

/// 记录一次 JSON 解析结果
+ (void)recordJSON:(id)json source:(nullable NSString *)source;

// ── 文件操作 ──
+ (NSString *)logDirPath;
+ (NSString *)logFilePath;
+ (NSData *)logData;
+ (unsigned long long)logSize;
+ (void)clearLog;

// ── 统计 ──
@property (nonatomic, assign, readonly) NSUInteger httpCount;
@property (nonatomic, assign, readonly) NSUInteger jsonCount;

@end

NS_ASSUME_NONNULL_END
