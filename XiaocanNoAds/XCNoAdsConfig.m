//
//  XCNoAdsConfig.m
//  XiaocanNoAds
//

#import "XCNoAdsConfig.h"

static NSString *const kXCEnabled          = @"XCNoAds_enabled";
static NSString *const kXCLogEnabled       = @"XCNoAds_logEnabled";
static NSString *const kXCBlockSplash      = @"XCNoAds_blockSplash";
static NSString *const kXCBlockInterstitial= @"XCNoAds_blockInterstitial";
static NSString *const kXCBlockBanner      = @"XCNoAds_blockBanner";
static NSString *const kXCBlockFeed        = @"XCNoAds_blockFeed";
static NSString *const kXCBlockReward      = @"XCNoAds_blockReward";
static NSString *const kXCHideAdViews      = @"XCNoAds_hideAdViews";

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
    [ud synchronize];
}

@end
