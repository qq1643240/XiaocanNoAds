//
//  XCNoAdsConfig.m
//  XiaocanNoAds
//

#import "XCNoAdsConfig.h"
#import "XCDiag.h"

static NSString *const kXCEnabled          = @"XCNoAds_enabled";
static NSString *const kXCLogEnabled       = @"XCNoAds_logEnabled";
static NSString *const kXCBlockSplash      = @"XCNoAds_blockSplash";
static NSString *const kXCBlockInterstitial= @"XCNoAds_blockInterstitial";
static NSString *const kXCBlockBanner      = @"XCNoAds_blockBanner";
static NSString *const kXCBlockFeed        = @"XCNoAds_blockFeed";
static NSString *const kXCBlockReward      = @"XCNoAds_blockReward";
static NSString *const kXCHideAdViews      = @"XCNoAds_hideAdViews";
static NSString *const kXCHideHomePromos   = @"XCNoAds_hideHomePromos";
static NSString *const kXCHidePromoTabs    = @"XCNoAds_hidePromoTabs";
static NSString *const kXCBlockPromoAPI    = @"XCNoAds_blockPromoAPI";
static NSString *const kXCScrubPromoJSON   = @"XCNoAds_scrubPromoJSON";
static NSString *const kXCCaptureNet       = @"XCNoAds_captureNet";

@implementation XCNoAdsConfig

+ (instancetype)shared {
    static XCNoAdsConfig *s = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s = [[XCNoAdsConfig alloc] init];
        [s setDefaults];
    });
    return s;
}

- (void)setDefaults {
    _enabled           = YES;
    _logEnabled        = NO;
    _blockSplash       = YES;
    _blockInterstitial = YES;
    _blockBanner       = YES;
    _blockFeed         = YES;
    _blockReward       = YES;
    _hideAdViews       = YES;
    _hideHomePromos    = YES;
    _hidePromoTabs     = YES;
    _blockPromoAPI     = NO;   // 默认关：接口拦截较激进，需用户主动开
    _scrubPromoJSON    = YES;  // 默认开：从接口 JSON 剔除促销节点（对付 SwiftUI/跨端渲染）
    _captureNet        = YES;  // 默认开：诊断期记录网络，方便定位漏网广告
}

- (void)load {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    // 首次运行：注册默认值
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [ud registerDefaults:@{
            kXCEnabled:           @YES,
            kXCLogEnabled:        @NO,
            kXCBlockSplash:       @YES,
            kXCBlockInterstitial: @YES,
            kXCBlockBanner:       @YES,
            kXCBlockFeed:         @YES,
            kXCBlockReward:       @YES,
            kXCHideAdViews:       @YES,
            kXCHideHomePromos:    @YES,
            kXCHidePromoTabs:     @YES,
            kXCBlockPromoAPI:     @NO,
            kXCScrubPromoJSON:    @YES,
            kXCCaptureNet:        @YES,
        }];
    });

    _enabled           = [ud boolForKey:kXCEnabled];
    _logEnabled        = [ud boolForKey:kXCLogEnabled];
    _blockSplash       = [ud boolForKey:kXCBlockSplash];
    _blockInterstitial = [ud boolForKey:kXCBlockInterstitial];
    _blockBanner       = [ud boolForKey:kXCBlockBanner];
    _blockFeed         = [ud boolForKey:kXCBlockFeed];
    _blockReward       = [ud boolForKey:kXCBlockReward];
    _hideAdViews       = [ud boolForKey:kXCHideAdViews];
    _hideHomePromos    = [ud boolForKey:kXCHideHomePromos];
    _hidePromoTabs     = [ud boolForKey:kXCHidePromoTabs];
    _blockPromoAPI     = [ud boolForKey:kXCBlockPromoAPI];

    XCLog(@"config loaded: enabled=%d splash=%d inter=%d banner=%d feed=%d reward=%d hide=%d",
          _enabled, _blockSplash, _blockInterstitial, _blockBanner,
          _blockFeed, _blockReward, _hideAdViews);
}

- (void)save {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:_enabled           forKey:kXCEnabled];
    [ud setBool:_logEnabled        forKey:kXCLogEnabled];
    [ud setBool:_blockSplash       forKey:kXCBlockSplash];
    [ud setBool:_blockInterstitial forKey:kXCBlockInterstitial];
    [ud setBool:_blockBanner       forKey:kXCBlockBanner];
    [ud setBool:_blockFeed         forKey:kXCBlockFeed];
    [ud setBool:_blockReward       forKey:kXCBlockReward];
    [ud setBool:_hideAdViews       forKey:kXCHideAdViews];
    [ud setBool:_hideHomePromos    forKey:kXCHideHomePromos];
    [ud setBool:_hidePromoTabs     forKey:kXCHidePromoTabs];
    [ud setBool:_blockPromoAPI     forKey:kXCBlockPromoAPI];
    [ud setBool:_scrubPromoJSON    forKey:kXCScrubPromoJSON];
    [ud setBool:_captureNet        forKey:kXCCaptureNet];
    [ud synchronize];
}

@end
