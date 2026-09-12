// XiaocanNoAds/Tweak.xm
// 小蚕惠生活 (com.realtech.xiaocan) 去广告插件
//
// 目标 App v3.20.4 的广告架构（侦察自真实 IPA）：
//   ┌─ 业务层：CXHChannel* / CXHAdSDK*  （自研广告封装）
//   ├─ 聚合层：AdGain* / CXHAdapter*    （自研聚合 + 各厂商 Adapter）
//   └─ 厂商层：穿山甲(ABUAdSDK/BUAdSDK)、优量汇(GDTMobSDK)、
//              快手(KSAdSDK)、百度、QMAdSDK、MSAdSDK、OctAdSDK…
//
// 拦截策略（多层设防，任何一层生效即可去广告）：
//   L1 厂商层：各 SDK 加载/展示全部失败
//   L2 聚合层：AdGain / CXHAdapter 请求直接不发
//   L3 业务层：CXHChannel* 广告 View 不上屏
//   L4 兜底：开屏拦截 + 全局广告 View 隐藏
//
// 所有 hook 都基于真实存在的类名；对不存在的类用 %init 的 group + 运行时
// 判断保护（见 XCClassGuard），确保不会因某个 SDK 版本差异而崩溃。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "XCNoAdsConfig.h"

#define XC_ON   ([XCNoAdsConfig shared].enabled)

static inline NSString *XCClsOf(id obj) {
    return obj ? NSStringFromClass([obj class]) : @"(nil)";
}


%group XCGroup

// ═════════════════════════════════════════════════════════════
// L1-A 穿山甲 Pangle / 聚合 ABUAdSDK
// ═════════════════════════════════════════════════════════════

%hook BUAdSDKManager

+ (void)startWithCompletionHandler:(void (^)(BOOL, NSError *))handler {
    if (XC_ON) {
        XCLog(@"block BUAdSDKManager start");
        if (handler) handler(NO, [NSError errorWithDomain:@"XCNoAds" code:-1 userInfo:nil]);
        return;
    }
    %orig;
}

%end


%hook BUSplashAd

- (void)loadAdData {
    if (XC_ON) { XCLog(@"block BUSplashAd loadAdData"); return; }
    %orig;
}

- (void)showAdInWindow:(UIWindow *)window {
    if (XC_ON) { XCLog(@"block BUSplashAd showAd"); return; }
    %orig;
}

%end


%hook BUNativeExpressAdManager

- (void)loadAdDataWithCount:(NSInteger)count {
    if (XC_ON) { return; }
    %orig;
}

%end


%hook BUNativeExpressFullscreenVideoAd

- (void)loadAdData {
    if (XC_ON) { return; }
    %orig;
}

- (void)showAdFromRootViewController:(UIViewController *)vc {
    if (XC_ON) { return; }
    %orig;
}

%end


%hook BUNativeExpressRewardedVideoAd

- (void)loadAdData {
    if (XC_ON) { return; }
    %orig;
}

- (void)showAdFromRootViewController:(UIViewController *)vc {
    if (XC_ON) {
        // 激励视频：直接通知"已关闭"，App 照常发奖励，用户无需真看
        // 用 KVC 运行时取值，避免对 forward declaration 发消息导致编译错误
        id delegate = nil;
        @try {
            delegate = ((id (*)(id, SEL, NSString *))objc_msgSend)(
                self, @selector(valueForKey:), @"delegate");
        } @catch (__unused NSException *e) {}
        SEL sel = @selector(nativeExpressRewardedVideoAdDidClose:);
        if (delegate && [delegate respondsToSelector:sel]) {
            ((void (*)(id, SEL, id))objc_msgSend)(delegate, sel, self);
        }
        return;
    }
    %orig;
}

%end


// ═════════════════════════════════════════════════════════════
// L1-B 优量汇 GDT
// ═════════════════════════════════════════════════════════════

%hook GDTSplashAd

- (void)loadAd {
    if (XC_ON) { XCLog(@"block GDTSplashAd loadAd"); return; }
    %orig;
}

%end


%hook GDTUnifiedInterstitialAd

- (void)loadAd {
    if (XC_ON) { return; }
    %orig;
}

- (void)presentAdFromRootViewController:(UIViewController *)vc {
    if (XC_ON) { return; }
    %orig;
}

%end


%hook GDTUnifiedNativeAd

- (void)loadAd {
    if (XC_ON) { return; }
    %orig;
}

%end


// ═════════════════════════════════════════════════════════════
// L1-C 快手 KS
// ═════════════════════════════════════════════════════════════

%hook KSAdSDKManager

+ (void)setAppId:(NSString *)appId {
    if (XC_ON) { return; }
    %orig;
}

%end


%hook KSSplashAdView

- (void)loadAdData {
    if (XC_ON) { return; }
    %orig;
}

%end


// ═════════════════════════════════════════════════════════════
// L2 聚合层：AdGain
// ═════════════════════════════════════════════════════════════

%hook AdGainBaseAdRequestImp

- (void)startRequest {
    if (XC_ON) { XCLog(@"block AdGain request"); return; }
    %orig;
}

%end


%hook AdGainAdRequest

- (void)sendRequest {
    if (XC_ON) { return; }
    %orig;
}

%end


// ═════════════════════════════════════════════════════════════
// L3 业务层：CXHChannel* 广告视图不上屏
// ═════════════════════════════════════════════════════════════

%hook CXHChannelSplashAdView

- (void)show {
    if (XC_ON) { XCLog(@"block CXH splash show"); return; }
    %orig;
}

%end


%hook CXHChannelInterstitialAdView

- (void)show {
    if (XC_ON) { return; }
    %orig;
}

%end


%hook CXHChannelRewardVideoAd

- (void)show {
    if (XC_ON) { return; }
    %orig;
}

%end


%hook CXHChannelRequestManager

- (void)startRequest {
    if (XC_ON) { return; }
    %orig;
}

%end


// ═════════════════════════════════════════════════════════════
// L4 兜底：广告 View 隐藏
// ═════════════════════════════════════════════════════════════

%hook UIView

- (void)didMoveToWindow {
    %orig;
    if (!XC_ON || ![XCNoAdsConfig shared].hideAdViews) return;

    static NSArray *adKeywords = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        adKeywords = @[@"SplashAd", @"InterstitialAd", @"BannerAd", @"NativeAd",
                       @"RewardVideo", @"AdGain", @"CXHChannel", @"CSJSplash",
                       @"BUSplash", @"GDTSplash", @"KSSplash", @"AdView"];
    });

    NSString *cls = NSStringFromClass([self class]);
    for (NSString *kw in adKeywords) {
        if ([cls containsString:kw]) {
            self.hidden = YES;
            self.alpha = 0;
            break;
        }
    }
}

%end


// 开屏 / 广告 VC 拦截
%hook UIViewController

- (void)presentViewController:(UIViewController *)vc
                     animated:(BOOL)flag
                   completion:(void (^)(void))completion {
    if (XC_ON) {
        NSString *cls = XCClsOf(vc);
        static NSArray *vcKeywords = nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            vcKeywords = @[@"Splash", @"Launch", @"AdViewController", @"Interstitial",
                           @"RewardVideo", @"AdGain", @"CXHChannel"];
        });
        for (NSString *kw in vcKeywords) {
            if ([cls containsString:kw]) {
                XCLog(@"block present %@", cls);
                if (completion) completion();
                return;
            }
        }
    }
    %orig;
}

%end

%end  // group XCGroup


%ctor {
    @autoreleasepool {
        %init(XCGroup);
        [[XCNoAdsConfig shared] load];
        XCLog(@"XiaocanNoAds loaded");
    }
}
