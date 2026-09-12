//
//  XCAdBlocker.h
//  XiaocanNoAds
//
//  网络层广告拦截：按域名 / 路径匹配广告接口，直接让请求失败。
//  这是对付「服务端 JSON 驱动广告」最有效的一层。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface XCAdBlocker : NSObject

+ (instancetype)shared;

/// 判断该 URL 是否为广告请求
+ (BOOL)shouldBlockURL:(nullable NSString *)url;

/// 本次运行已拦截的广告请求数
@property (nonatomic, assign, readonly) NSUInteger blockedCount;

/// 最近被拦截的 URL（最多 20 条，便于排查）
@property (nonatomic, strong, readonly) NSMutableArray<NSString *> *recentBlocked;

- (void)recordBlocked:(NSString *)url;

@end

NS_ASSUME_NONNULL_END
