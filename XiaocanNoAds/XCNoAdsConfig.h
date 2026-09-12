//
//  XCNoAdsConfig.h
//  XiaocanNoAds
//
//  插件配置：总开关、日志开关、细粒度拦截项
//  配置持久化在 NSUserDefaults（com.realtech.xiaocan 域），
//  可在手机的「设置 → 小蚕惠生活去广告」里改（见 XCPrefsController）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 统一日志
#define XCLog(fmt, ...) \
    do { if ([XCNoAdsConfig shared].logEnabled) \
        NSLog(@"[XiaocanNoAds] " fmt, ##__VA_ARGS__); } while (0)

@interface XCNoAdsConfig : NSObject

+ (instancetype)shared;

/// 总开关：NO 时插件完全透传，等同没装
@property (nonatomic, assign) BOOL enabled;

/// 是否输出日志
@property (nonatomic, assign) BOOL logEnabled;

// ── 细粒度开关 ──
@property (nonatomic, assign) BOOL blockSplash;        // 开屏广告
@property (nonatomic, assign) BOOL blockInterstitial;  // 插屏广告
@property (nonatomic, assign) BOOL blockBanner;        // 横幅广告
@property (nonatomic, assign) BOOL blockFeed;          // 信息流广告
@property (nonatomic, assign) BOOL blockReward;        // 激励视频（自动完成）
@property (nonatomic, assign) BOOL hideAdViews;        // 兜底隐藏广告 View

/// 从 NSUserDefaults 载入
- (void)load;

/// 保存到 NSUserDefaults
- (void)save;

@end

NS_ASSUME_NONNULL_END
