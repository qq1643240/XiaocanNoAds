// XiaocanNoAds/Tweak.xm
// 小蚕惠生活 (com.realtech.xiaocan) 去广告插件  v1.1.0
//
// 目标 App v3.20.4 广告架构（侦察自真实 IPA）：
//   ┌─ 自研封装：BTP*AdHelper / BTPConfigCenter / CXHChannel* / CXHAdSDK*
//   ├─ 自研聚合：AdGain* / CXHAdapter*
//   └─ 厂商 SDK：穿山甲(ABUAdSDK/BUAdSDK)、优量汇(GDT)、快手(KS)、
//                百度、Menta、QMAdSDK、MSAdSDK、OctAdSDK、BeiZi…
//
// 广告接口（网络层拦截用）：
//   /sylas/sdk/v2/ads/conf                       自研广告配置
//   sdk-api.adn-plus.com.cn/api/v3/ad/getAd      AdScope 广告
//   sdk-api.adn-plus.com.cn/api/v3/cfg/getConfig AdScope 配置
//   sdkcfg.adintl.cn/sdk/getConfig               AdScope 配置
//
// 六层拦截（任一层生效即可去广告，层层叠加覆盖率）：
//   L0 网络层：广告接口直接失败（对付服务端 JSON 驱动广告）
//   L1 厂商层：各 SDK 加载/展示全部失败
//   L2 自研层：BTP*AdHelper 加载失败
//   L3 聚合层：AdGain 请求不发
//   L4 业务层：CXHChannel* 广告 View 不上屏
//   L5 兜底层：广告 View 隐藏 + 开屏 VC 拦截
//
// 注意：所有方法体一律使用标准多行格式——官方 theos 的 Logos
//       不接受「单行 + %orig」写法，会报 function definition is not allowed here。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "XCNoAdsConfig.h"
#import "XCAdBlocker.h"

#define XC_ON   ([XCNoAdsConfig shared].enabled)

static inline NSString *XCClsOf(id obj) {
    return obj ? NSStringFromClass([obj class]) : @"(nil)";
}

static BOOL XCClsNameContains(id obj, NSArray<NSString *> *keywords) {
    NSString *cls = XCClsOf(obj);
    for (NSString *kw in keywords) {
        if ([cls containsString:kw]) return YES;
    }
    return NO;
}


%group XCGroup

// ═════════════════════════════════════════════════════════════
// L0 网络层：广告接口直接失败
// ═════════════════════════════════════════════════════════════
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler {
    NSString *url = request.URL.absoluteString;
    if (completionHandler && [XCAdBlocker shouldBlockURL:url]) {
        [[XCAdBlocker shared] recordBlocked:url];
        void (^wrapped)(NSData *, NSURLResponse *, NSError *) =
            ^(NSData *data, NSURLResponse *response, NSError *error) {
                NSError *err = [NSError errorWithDomain:NSURLErrorDomain
                                                   code:NSURLErrorCannotFindHost
                                               userInfo:@{NSLocalizedDescriptionKey: @"XCNoAds"}];
                completionHandler(nil, response, err);
            };
        return %orig(request, wrapped);
    }
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler {
    NSString *abs = url.absoluteString;
    if (completionHandler && [XCAdBlocker shouldBlockURL:abs]) {
        [[XCAdBlocker shared] recordBlocked:abs];
        void (^wrapped)(NSData *, NSURLResponse *, NSError *) =
            ^(NSData *data, NSURLResponse *response, NSError *error) {
                NSError *err = [NSError errorWithDomain:NSURLErrorDomain
                                                   code:NSURLErrorCannotFindHost
                                               userInfo:@{NSLocalizedDescriptionKey: @"XCNoAds"}];
                completionHandler(nil, response, err);
            };
        return %orig(url, wrapped);
    }
    return %orig;
}

%end


// ═════════════════════════════════════════════════════════════
// L1 厂商层：穿山甲 Pangle
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
    if (XC_ON) return;
    %orig;
}

- (void)showAdInWindow:(UIWindow *)window {
    if (XC_ON) return;
    %orig;
}

%end


%hook BUNativeExpressAdManager

- (void)loadAdDataWithCount:(NSInteger)count {
    if (XC_ON) return;
    %orig;
}

%end


%hook BUNativeExpressFullscreenVideoAd

- (void)loadAdData {
    if (XC_ON) return;
    %orig;
}

- (void)showAdFromRootViewController:(UIViewController *)vc {
    if (XC_ON) return;
    %orig;
}

%end


%hook BUNativeExpressRewardedVideoAd

- (void)loadAdData {
    if (XC_ON) return;
    %orig;
}

- (void)showAdFromRootViewController:(UIViewController *)vc {
    if (XC_ON) {
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


// 穿山甲 draw / banner（信息流自渲染广告，首页那些横幅就是它）
%hook ABUDrawAdsManager

- (void)loadAdDataWithCount:(NSInteger)count {
    if (XC_ON) {
        XCLog(@"block ABUDrawAdsManager");
        return;
    }
    %orig;
}

%end


%hook ABUBannerAd

- (void)loadAdData {
    if (XC_ON) return;
    %orig;
}

- (void)loadBannerAd {
    if (XC_ON) return;
    %orig;
}

%end


// ═════════════════════════════════════════════════════════════
// L1 厂商层：优量汇 GDT
// ═════════════════════════════════════════════════════════════
%hook GDTSplashAd

- (void)loadAd {
    if (XC_ON) {
        XCLog(@"block GDTSplashAd");
        return;
    }
    %orig;
}

%end


%hook GDTUnifiedInterstitialAd

- (void)loadAd {
    if (XC_ON) return;
    %orig;
}

- (void)presentAdFromRootViewController:(UIViewController *)vc {
    if (XC_ON) return;
    %orig;
}

%end


%hook GDTUnifiedNativeAd

- (void)loadAd {
    if (XC_ON) return;
    %orig;
}

%end


// ═════════════════════════════════════════════════════════════
// L1 厂商层：快手 KS
// ═════════════════════════════════════════════════════════════
%hook KSAdSDKManager

+ (void)setAppId:(NSString *)appId {
    if (XC_ON) return;
    %orig;
}

%end


%hook KSSplashAdView

- (void)loadAdData {
    if (XC_ON) return;
    %orig;
}

%end


// ═════════════════════════════════════════════════════════════
// L2 自研层：BTP*AdHelper（App 自己的广告封装）
// ═════════════════════════════════════════════════════════════
%hook BTPSplashAdHelper

- (void)loadAdData {
    if (XC_ON) {
        XCLog(@"block BTPSplashAdHelper");
        return;
    }
    %orig;
}

%end


%hook BTPBannerAdHelper

- (void)loadAdData {
    if (XC_ON) {
        XCLog(@"block BTPBannerAdHelper");
        return;
    }
    %orig;
}

%end


%hook BTPFeedAdHelper

- (void)loadAdData {
    if (XC_ON) {
        XCLog(@"block BTPFeedAdHelper");
        return;
    }
    %orig;
}

%end


// ═════════════════════════════════════════════════════════════
// L3 聚合层：AdGain
// ═════════════════════════════════════════════════════════════
%hook AdGainBaseAdRequestImp

- (void)startRequest {
    if (XC_ON) {
        XCLog(@"block AdGain request");
        return;
    }
    %orig;
}

%end


%hook AdGainAdRequest

- (void)sendRequest {
    if (XC_ON) return;
    %orig;
}

%end


// ═════════════════════════════════════════════════════════════
// L4 业务层：CXHChannel* 广告视图不上屏
// ═════════════════════════════════════════════════════════════
%hook CXHChannelSplashAdView

- (void)show {
    if (XC_ON) {
        XCLog(@"block CXH splash show");
        return;
    }
    %orig;
}

%end


%hook CXHChannelInterstitialAdView

- (void)show {
    if (XC_ON) return;
    %orig;
}

%end


%hook CXHChannelRewardVideoAd

- (void)show {
    if (XC_ON) return;
    %orig;
}

%end


%hook CXHChannelRequestManager

- (void)startRequest {
    if (XC_ON) return;
    %orig;
}

%end


// ═════════════════════════════════════════════════════════════
// L5 兜底层 A：广告 View 隐藏（类名关键字，扩大覆盖）
// ═════════════════════════════════════════════════════════════
%hook UIView

- (void)didMoveToWindow {
    %orig;
    if (!XC_ON || ![XCNoAdsConfig shared].hideAdViews) return;

    static NSArray *adKeywords = nil;
    static NSArray *promoKeywords = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        adKeywords = @[@"SplashAd", @"InterstitialAd", @"BannerAd", @"NativeAd",
                       @"RewardVideo", @"AdGain", @"CXHChannel", @"CXHAdSDK",
                       @"CSJSplash", @"BUSplash", @"GDTSplash", @"KSSplash",
                       @"AdView", @"DrawAd", @"FeedAd", @"AdBanner",
                       @"AdContainer", @"AdCard", @"AdSlot", @"AdTemplate",
                       @"BTPBanner", @"BTPFeed", @"BTPSplash", @"BTPInterstitial",
                       @"BTPReward", @"BTPAd"];

        // 首页业务推广位（原生类，实测自 3.20.5）
        promoKeywords = @[@"HomeBubbleView",                    // 大额红包浮窗
                          @"HomeActivityViewV2",                // 外卖红包横幅
                          @"HomeBigBrandView",                  // 福利社格子
                          @"HomeBigBrandTwoView",
                          @"HomeBigBrandItem",
                          @"HomeFullRefundStickyBannerView",    // 吸顶横幅
                          @"HomeFullRefundRebateGuideFloatingView",
                          @"HomeNewUserServiseFloatingView",
                          @"HomeRainAndOrderFloatingView",      // 红包雨浮窗
                          @"HomeRainFloatingView",
                          @"HomeFloatTaskTipView",              // 浮动任务提示
                          @"HomeFullRefundMarqueeItemView",     // 跑马灯
                          @"HomePromotionItem",
                          @"HomeTDNewUserBannerAction",
                          @"HomePromotionNotifiDialog",         // 促销弹窗
                          @"HomeUpActivityDialog",
                          @"HomeActiveVipDialog",
                          @"HomeRebornCardActivityDialog",
                          @"HomeFullRefundExpiringRedPacketDialog"];
    });

    NSString *cls = NSStringFromClass([self class]);

    for (NSString *kw in adKeywords) {
        if ([cls containsString:kw]) {
            self.hidden = YES;
            self.alpha = 0;
            return;
        }
    }

    if ([XCNoAdsConfig shared].hideHomePromos) {
        for (NSString *kw in promoKeywords) {
            if ([cls containsString:kw]) {
                XCLog(@"hide promo view %@", cls);
                self.hidden = YES;
                self.alpha = 0;
                return;
            }
        }
    }
}

%end


// ═════════════════════════════════════════════════════════════
// L5 兜底层 B：开屏 / 广告 VC 拦截 + 开屏提速
// ═════════════════════════════════════════════════════════════
%hook UIViewController

- (void)presentViewController:(UIViewController *)vc
                     animated:(BOOL)flag
                   completion:(void (^)(void))completion {
    if (XC_ON) {
        static NSArray *vcKeywords = nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            vcKeywords = @[@"Splash", @"AdViewController", @"Interstitial",
                           @"RewardVideo", @"AdGain", @"CXHChannel",
                           @"BTPAd", @"AdLanding", @"LandingPage"];
        });
        if (XCClsNameContains(vc, vcKeywords)) {
            XCLog(@"block present %@", XCClsOf(vc));
            if (completion) completion();
            return;
        }
    }
    %orig;
}

// 开屏提速：广告类开屏 VC 一出现就立刻关掉，不占用启动时间
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!XC_ON) return;

    static NSArray *splashKeywords = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        splashKeywords = @[@"SplashAdView", @"AdGainSplash", @"BTPSplash",
                           @"SplashAdViewController", @"CXHChannelSplash"];
    });
    if (XCClsNameContains(self, splashKeywords)) {
        XCLog(@"fast-dismiss splash %@", XCClsOf(self));
        __weak typeof(self) wself = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) sself = wself;
            if (sself.presentingViewController) {
                [sself dismissViewControllerAnimated:NO completion:nil];
            }
        });
    }
}

%end


// ═════════════════════════════════════════════════════════════
// L5 兜底层 C：底部推广 tab 过滤（抖音补贴 / 特领元宝 等）
// ═════════════════════════════════════════════════════════════
%hook UITabBarController

- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers animated:(BOOL)animated {
    if (XC_ON && [XCNoAdsConfig shared].hidePromoTabs && viewControllers.count > 0) {
        static NSArray *promoTabTitles = nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            promoTabTitles = @[@"抖音补贴", @"特领元宝", @"补贴", @"元宝", @"福利"];
        });

        NSMutableArray<UIViewController *> *filtered = [NSMutableArray arrayWithCapacity:viewControllers.count];
        for (UIViewController *vc in viewControllers) {
            NSString *title = vc.tabBarItem.title ?: vc.title ?: @"";
            BOOL isPromo = NO;
            for (NSString *kw in promoTabTitles) {
                if ([title containsString:kw]) { isPromo = YES; break; }
            }
            if (isPromo) {
                XCLog(@"drop promo tab: %@", title);
                continue;
            }
            [filtered addObject:vc];
        }

        if (filtered.count > 0 && filtered.count != viewControllers.count) {
            %orig(filtered, animated);
            return;
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
        XCLog(@"XiaocanNoAds v1.2.0 loaded");
    }
}
