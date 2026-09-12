//
//  XCAdBlocker.m
//  XiaocanNoAds
//

#import "XCAdBlocker.h"
#import "XCNoAdsConfig.h"

// ── 广告域名（子串匹配，命中即拦）──
// 来源：对 com.realtech.xiaocan v3.20.4 主二进制的接口字符串分析
static NSString *const kAdDomains[] = {
    // 自研 / 聚合广告
    @"adn-plus.com.cn",          // AdScope 聚合广告
    @"adintl.cn",                // AdScope 配置
    @"ad-scope.com.cn",          // AdScope SDK
    @"adgain",                   // AdGain 自研聚合
    @"sylas/sdk",                // App 自研广告 SDK 路径
    // 穿山甲 Pangle
    @"pglstatp",
    @"pangolin-sdk-toutiao",
    @"ad.toutiao.com",
    @"is.snssdk.com",
    @"adservice",
    // 优量汇 GDT
    @"gdt.qq.com",
    @"pgdt.gtimg.cn",
    @"e.qq.com",
    @"v.gdt.qq.com",
    // 快手
    @"ksad",
    @"kuaishou.com",
    // 百度
    @"mobads.baidu.com",
    @"ada.baidu.com",
    @"aden.baidu.com",
    @"baihemob.com",
    // Menta / 美泰
    @"menta",
    // QM / 米盟
    @"qm-ad",
    @"qmsdk",
    // 其他
    @"beizi",
    @"octopusad",
    @"msad",
    @"richmob",
    @"leadmob",
    @"youtui",
};

// ── 广告路径关键字（子串匹配）──
static NSString *const kAdPaths[] = {
    @"/sylas/sdk/v2/ads/conf",
    @"/sylas/sdk/track",
    @"/api/v3/ad/getAd",
    @"/api/v3/cfg/getConfig",
    @"/sdk/getConfig",
    @"/mb/sdk0/json",
    @"/mb/sdk/crash",
    @"/ad/getAd",
    @"/ads/conf",
    @"/adconf",
    @"/advert",
    @"/api/ad/",
};

static const NSUInteger kAdDomainsCount = sizeof(kAdDomains) / sizeof(kAdDomains[0]);
static const NSUInteger kAdPathsCount   = sizeof(kAdPaths)   / sizeof(kAdPaths[0]);

@interface XCAdBlocker ()
@property (nonatomic, assign) NSUInteger blockedCount;
@property (nonatomic, strong) NSMutableArray<NSString *> *recentBlocked;
@end

@implementation XCAdBlocker

+ (instancetype)shared {
    static XCAdBlocker *s = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s = [[XCAdBlocker alloc] init];
        s.recentBlocked = [NSMutableArray array];
    });
    return s;
}

+ (BOOL)shouldBlockURL:(NSString *)url {
    if (!url.length) return NO;
    if (![XCNoAdsConfig shared].enabled) return NO;

    NSString *lower = url.lowercaseString;

    for (NSUInteger i = 0; i < kAdDomainsCount; i++) {
        if ([lower containsString:kAdDomains[i]]) return YES;
    }
    for (NSUInteger i = 0; i < kAdPathsCount; i++) {
        if ([lower containsString:kAdPaths[i].lowercaseString]) return YES;
    }
    return NO;
}

- (void)recordBlocked:(NSString *)url {
    if (!url.length) return;
    _blockedCount++;

    NSString *shortURL = url.length > 110 ? [url substringToIndex:110] : url;
    if (![self.recentBlocked containsObject:shortURL]) {
        [self.recentBlocked insertObject:shortURL atIndex:0];
        if (self.recentBlocked.count > 20) [self.recentBlocked removeLastObject];
    }

    XCLog(@"blocked ad request: %@", shortURL);
}

@end
