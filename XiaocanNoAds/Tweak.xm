// XiaocanNoAds/Tweak.xm
// 小蚕惠生活 (com.realtech.xiaocan) 去广告插件  v1.3.0
//
// ─────────────────────────────────────────────────────────────
// v1.3.0 重要变更（基于对 3.20.5 的重新侦察）
//
// 侦察结论：
//   1. App 是 Flutter + Lynx + Kuikly + SwiftUI 四引擎混合体
//   2. 首页 Swift 组件（HomeBubbleView / HomeActivityViewV2 /
//      HomeBigBrandView …）是 SwiftUI struct，**不注册进 ObjC 运行时**
//      → objc_getClass 返回 nil，%hook 静默失效（这是 v1.1/v1.2 无效的根因）
//   3. 首页促销 / 底部推广 tab 全部由服务端 JSON 驱动
//
// 因此 v1.3.0 改为「数据层拦截」为主：
//   D0 数据层：hook NSJSONSerialization，从接口 JSON 里剔除促销节点  ← 核心
//   D1 诊断层：抓包记录所有 HTTP 往返 + JSON，写入日志文件
//   L1~L5 保留原有 SDK 层拦截（对标准广告 SDK 仍然有效）
// ─────────────────────────────────────────────────────────────
//
// 注意：所有 %hook 方法体一律使用标准多行格式——官方 theos 的 Logos
//       不接受「单行 + %orig」写法，会报 function definition is not allowed here。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "XCNoAdsConfig.h"
#import "XCAdBlocker.h"
#import "XCDiag.h"
#import "XCJSONScrubber.h"
#import "XCPrefsController.h"

#define XC_ON   ([XCNoAdsConfig shared].enabled)
#define XC_CFG  [XCNoAdsConfig shared]

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

/// 统一记录一次 HTTP 往返
static void XCRecordHTTP(NSURLRequest *req, NSData *data, NSURLResponse *resp, NSError *err) {
    if (!XC_CFG.captureNet) return;
    NSInteger code = 0;
    if ([resp isKindOfClass:[NSHTTPURLResponse class]]) {
        code = ((NSHTTPURLResponse *)resp).statusCode;
    } else if (err) {
        code = -1;
    }
    [XCDiag recordHTTP:req.URL.absoluteString
                method:req.HTTPMethod
           requestBody:req.HTTPBody
          responseCode:code
          responseBody:data];
}

/// 判断是否「像接口返回的 JSON」——只有像才清洗，避免误伤其它 JSON
static BOOL XCLooksLikeAPIResponse(id obj) {
    if (![obj isKindOfClass:[NSDictionary class]]) return NO;
    NSDictionary *d = obj;
    for (NSString *k in @[@"code", @"data", @"result", @"msg", @"message", @"success", @"errno"]) {
        if (d[k] != nil) return YES;
    }
    return NO;
}

// ── 状态浮标：确认插件是否真的加载了 ──
static UIWindow *gBadgeWindow = nil;

static void XCShowBadge(NSString *text, NSTimeInterval seconds) {
    void (^blk)(void) = ^{
        UIWindow *w = [[UIWindow alloc] initWithFrame:CGRectZero];
        w.windowLevel = UIWindowLevelAlert + 100;
        w.backgroundColor = [UIColor colorWithRed:0.05 green:0.55 blue:0.25 alpha:0.94];
        w.layer.cornerRadius = 10.0;
        w.clipsToBounds = YES;

        UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
        l.text = text;
        l.textColor = [UIColor whiteColor];
        l.font = [UIFont boldSystemFontOfSize:12.5];
        l.textAlignment = NSTextAlignmentCenter;
        l.numberOfLines = 0;
        [w addSubview:l];

        CGRect screen = [UIScreen mainScreen].bounds;
        CGFloat width = screen.size.width - 32.0;
        CGFloat height = 62.0;
        w.frame = CGRectMake(16.0, 64.0, width, height);
        l.frame = CGRectInset(w.bounds, 10.0, 6.0);

        gBadgeWindow = w;
        w.hidden = NO;
        w.alpha = 0.0;
        [UIView animateWithDuration:0.25 animations:^{
            w.alpha = 1.0;
        }];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.35 animations:^{
                gBadgeWindow.alpha = 0.0;
            } completion:^(BOOL finished) {
                gBadgeWindow.hidden = YES;
                gBadgeWindow = nil;
            }];
        });
    };

    if ([NSThread isMainThread]) {
        blk();
    } else {
        dispatch_async(dispatch_get_main_queue(), blk);
    }
}

// ── 设置面板入口：三指双击 ──
static void XCInstallPrefsGesture(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIWindow *win = nil;
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) { win = w; break; }
        }
        if (win == nil) win = [UIApplication sharedApplication].windows.firstObject;
        if (win == nil) return;

        UITapGestureRecognizer *tap =
            [[UITapGestureRecognizer alloc] initWithTarget:[XCPrefsController class]
                                                    action:@selector(xc_handlePrefsGesture:)];
        tap.numberOfTapsRequired = 2;
        tap.numberOfTouchesRequired = 3;
        [win addGestureRecognizer:tap];
    });
}


%group XCGroup

// ═════════════════════════════════════════════════════════════
// D0 数据层：JSON 清洗（核心）
//    首页促销 / 底部推广 tab 都来自服务端 JSON，
//    SwiftUI 渲染层无法 hook，只能在数据源头剔除。
// ═════════════════════════════════════════════════════════════
%hook NSJSONSerialization

+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
    id obj = %orig;

    if (obj == nil || !XC_ON) {
        return obj;
    }

    // 抓包记录
    if (XC_CFG.captureNet) {
        [XCDiag recordJSON:obj
                    source:[NSString stringWithFormat:@"NSJSONSerialization (%lu B)",
                            (unsigned long)data.length]];
    }

    // 促销节点清洗
    if (XC_CFG.scrubPromoJSON && XCLooksLikeAPIResponse(obj)) {
        NSUInteger removed = 0;
        id scrubbed = [XCJSONScrubber scrubJSON:obj removed:&removed];
        if (removed > 0) {
            [XCDiag log:@"[清洗] 从接口 JSON 移除 %lu 个促销节点", (unsigned long)removed];
            XCLog(@"scrub JSON: removed %lu promo nodes", (unsigned long)removed);
            return scrubbed;
        }
    }

    return obj;
}

%end


// ═════════════════════════════════════════════════════════════
// D1 诊断层 + L0 网络层：广告接口失败 + 全量抓包
// ═════════════════════════════════════════════════════════════
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler {
    NSString *url = request.URL.absoluteString;

    if (completionHandler && XC_ON && [XCAdBlocker shouldBlockURL:url]) {
        [[XCAdBlocker shared] recordBlocked:url];
        [XCDiag log:@"[拦截] 广告接口 %@", url];
        void (^wrapped)(NSData *, NSURLResponse *, NSError *) =
            ^(NSData *data, NSURLResponse *response, NSError *error) {
                NSError *err = [NSError errorWithDomain:NSURLErrorDomain
                                                   code:NSURLErrorCannotFindHost
                                               userInfo:@{NSLocalizedDescriptionKey: @"XCNoAds"}];
                completionHandler(nil, response, err);
            };
        return %orig(request, wrapped);
    }

    if (completionHandler && XC_CFG.captureNet) {
        void (^wrapped)(NSData *, NSURLResponse *, NSError *) =
            ^(NSData *data, NSURLResponse *response, NSError *error) {
                XCRecordHTTP(request, data, response, error);
                completionHandler(data, response, error);
            };
        return %orig(request, wrapped);
    }

    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler {
    NSString *abs = url.absoluteString;

    if (completionHandler && XC_ON && [XCAdBlocker shouldBlockURL:abs]) {
        [[XCAdBlocker shared] recordBlocked:abs];
        [XCDiag log:@"[拦截] 广告接口 %@", abs];
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

// AFNetworking 走的是这个 5 参数版本
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                               uploadProgress:(void (^)(int64_t, int64_t, int64_t))uploadProgressBlock
                             downloadProgress:(void (^)(int64_t, int64_t, int64_t))downloadProgressBlock
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    NSString *url = request.URL.absoluteString;

    if (completionHandler && XC_ON && [XCAdBlocker shouldBlockURL:url]) {
        [[XCAdBlocker shared] recordBlocked:url];
        [XCDiag log:@"[拦截] 广告接口 %@", url];
        void (^wrapped)(NSData *, NSURLResponse *, NSError *) =
            ^(NSData *data, NSURLResponse *response, NSError *error) {
                NSError *err = [NSError errorWithDomain:NSURLErrorDomain
                                                   code:NSURLErrorCannotFindHost
                                               userInfo:@{NSLocalizedDescriptionKey: @"XCNoAds"}];
                completionHandler(nil, response, err);
            };
        return %orig(request, uploadProgressBlock, downloadProgressBlock, wrapped);
    }

    if (completionHandler && XC_CFG.captureNet) {
        void (^wrapped)(NSData *, NSURLResponse *, NSError *) =
            ^(NSData *data, NSURLResponse *response, NSError *error) {
                XCRecordHTTP(request, data, response, error);
                completionHandler(data, response, error);
            };
        return %orig(request, uploadProgressBlock, downloadProgressBlock, wrapped);
    }

    return %orig;
}

// 无 completion 版本（delegate 型任务）：只记请求，便于知道打了哪些接口
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    if (XC_CFG.captureNet) {
        [XCDiag log:@"[请求] %@ %@",
            request.HTTPMethod ?: @"GET", request.URL.absoluteString];
    }
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url {
    if (XC_CFG.captureNet) {
        [XCDiag log:@"[请求] GET %@", url.absoluteString];
    }
    return %orig;
}

%end


// ═════════════════════════════════════════════════════════════
// D1 诊断层：NSURLConnection（老式接口）
// ═════════════════════════════════════════════════════════════
%hook NSURLConnection

+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                 returningResponse:(NSURLResponse **)response
                             error:(NSError **)error {
    NSData *data = %orig;
    XCRecordHTTP(request, data, (response ? *response : nil), (error ? *error : nil));
    return data;
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
    if (XC_ON) {
        return;
    }
    %orig;
}

- (void)showAdInWindow:(UIWindow *)window {
    if (XC_ON) {
        return;
    }
    %orig;
}

%end


%hook BUNativeExpressAdManager

- (void)loadAdDataWithCount:(NSInteger)count {
    if (XC_ON) {
        return;
    }
    %orig;
}

%end


%hook BUNativeExpressFullscreenVideoAd

- (void)loadAdData {
    if (XC_ON) {
        return;
    }
    %orig;
}

- (void)showAdFromRootViewController:(UIViewController *)vc {
    if (XC_ON) {
        return;
    }
    %orig;
}

%end


%hook BUNativeExpressRewardedVideoAd

- (void)loadAdData {
    if (XC_ON) {
        return;
    }
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
    if (XC_ON) {
        return;
    }
    %orig;
}

- (void)loadBannerAd {
    if (XC_ON) {
        return;
    }
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
    if (XC_ON) {
        return;
    }
    %orig;
}

- (void)presentAdFromRootViewController:(UIViewController *)vc {
    if (XC_ON) {
        return;
    }
    %orig;
}

%end


%hook GDTUnifiedNativeAd

- (void)loadAd {
    if (XC_ON) {
        return;
    }
    %orig;
}

%end


// ═════════════════════════════════════════════════════════════
// L1 厂商层：快手 KS
// ═════════════════════════════════════════════════════════════
%hook KSAdSDKManager

+ (void)setAppId:(NSString *)appId {
    if (XC_ON) {
        return;
    }
    %orig;
}

%end


%hook KSSplashAdView

- (void)loadAdData {
    if (XC_ON) {
        return;
    }
    %orig;
}

%end


// ═════════════════════════════════════════════════════════════
// L2 自研层：BTP*AdHelper
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
        return;
    }
    %orig;
}

%end


%hook BTPFeedAdHelper

- (void)loadAdData {
    if (XC_ON) {
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
    if (XC_ON) {
        return;
    }
    %orig;
}

%end


// ═════════════════════════════════════════════════════════════
// L4 业务层：CXHChannel* 广告视图
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
    if (XC_ON) {
        return;
    }
    %orig;
}

%end


%hook CXHChannelRewardVideoAd

- (void)show {
    if (XC_ON) {
        return;
    }
    %orig;
}

%end


%hook CXHChannelRequestManager

- (void)startRequest {
    if (XC_ON) {
        return;
    }
    %orig;
}

%end


// ═════════════════════════════════════════════════════════════
// L5 兜底层 A：广告 View 隐藏（仅对真实存在的 UIKit 广告视图有效）
// ═════════════════════════════════════════════════════════════
%hook UIView

- (void)didMoveToWindow {
    %orig;
    if (!XC_ON || !XC_CFG.hideAdViews) return;

    static NSArray *adKeywords = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        adKeywords = @[@"SplashAd", @"InterstitialAd", @"BannerAd", @"NativeAd",
                       @"RewardVideo", @"AdGain", @"CXHChannel", @"CXHAdSDK",
                       @"CSJSplash", @"BUSplash", @"GDTSplash", @"KSSplash",
                       @"AdView", @"DrawAd", @"FeedAd", @"AdBanner",
                       @"AdContainer", @"AdCard", @"AdSlot", @"AdTemplate",
                       @"BTPBanner", @"BTPFeed", @"BTPSplash", @"BTPInterstitial",
                       @"BTPReward", @"BTPAd"];
    });

    NSString *cls = NSStringFromClass([self class]);
    for (NSString *kw in adKeywords) {
        if ([cls containsString:kw]) {
            self.hidden = YES;
            self.alpha = 0;
            return;
        }
    }
}

%end


// ═════════════════════════════════════════════════════════════
// L5 兜底层 B：广告 VC 拦截 + 开屏提速 + 诊断记录
// ═════════════════════════════════════════════════════════════
%hook UIViewController

- (void)presentViewController:(UIViewController *)vc
                     animated:(BOOL)flag
                   completion:(void (^)(void))completion {
    if (XC_ON) {
        if (XC_CFG.captureNet) {
            [XCDiag log:@"[弹出] %@", XCClsOf(vc)];
        }

        static NSArray *vcKeywords = nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            vcKeywords = @[@"Splash", @"AdViewController", @"Interstitial",
                           @"RewardVideo", @"AdGain", @"CXHChannel",
                           @"BTPAd", @"AdLanding", @"LandingPage"];
        });
        if (XCClsNameContains(vc, vcKeywords)) {
            XCLog(@"block present %@", XCClsOf(vc));
            [XCDiag log:@"[拦截] 弹出广告页 %@", XCClsOf(vc)];
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

    static NSUInteger sVCLogCount = 0;
    if (XC_CFG.captureNet && sVCLogCount < 120) {
        sVCLogCount++;
        [XCDiag log:@"[页面] %@", XCClsOf(self)];
    }

    static NSArray *splashKeywords = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        splashKeywords = @[@"SplashAdView", @"AdGainSplash", @"BTPSplash",
                           @"SplashAdViewController", @"CXHChannelSplash"];
    });
    if (XCClsNameContains(self, splashKeywords)) {
        XCLog(@"fast-dismiss splash %@", XCClsOf(self));
        [XCDiag log:@"[提速] 立即关闭开屏 %@", XCClsOf(self)];
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
// L5 兜底层 C：底部推广 tab 过滤
// ═════════════════════════════════════════════════════════════
%hook UITabBarController

- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers animated:(BOOL)animated {
    if (XC_ON && XC_CFG.hidePromoTabs && viewControllers.count > 0) {
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
                [XCDiag log:@"[拦截] 移除推广 tab: %@", title];
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
        [XC_CFG load];

        [XCDiag log:@"=== XiaocanNoAds v1.3.0 已加载 ==="];
        [XCDiag log:@"日志路径: %@", [XCDiag logFilePath]];
        XCLog(@"XiaocanNoAds v1.3.0 loaded, log=%@", [XCDiag logFilePath]);

        XCInstallPrefsGesture();

        XCShowBadge(@"小蚕去广告 v1.3.0 已加载 ✓\n三指双击屏幕打开设置 · 日志已开启", 8.0);
    }
}
