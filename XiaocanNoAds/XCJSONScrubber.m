//
//  XCJSONScrubber.m
//  XiaocanNoAds
//

#import "XCJSONScrubber.h"

/// 只看「类型类」字段，避免误伤
static NSArray<NSString *> *XCTypeKeys(void) {
    static NSArray *keys = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[@"type", @"cardType", @"moduleType", @"elementType", @"style",
                 @"templateType", @"bizType", @"componentType", @"cellType",
                 @"resourceType", @"elementId", @"moduleName", @"componentName",
                 @"bizCode", @"positionCode", @"slotType", @"floorType"];
    });
    return keys;
}

static NSArray<NSString *> *XCPromoWords(void) {
    static NSArray *kw = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        kw = @[
            // 中文强信号
            @"红包", @"神券", @"优惠券", @"领券", @"满减", @"补贴", @"元宝",
            @"福利", @"返现", @"返利", @"抽奖", @"免单", @"秒杀", @"试吃",
            @"免费吃", @"免费喝", @"挑战赛", @"红包雨", @"大额", @"砍价",
            @"新人礼", @"赚金币", @"天天领",
            // 英文强信号
            @"redpacket", @"red_packet", @"redenvelope", @"coupon", @"promotion",
            @"promot", @"advert", @"welfare", @"lottery", @"rebate", @"discount",
            @"marketing", @"newuser", @"new_user", @"incentive"
        ];
    });
    return kw;
}

@interface XCJSONScrubber ()
+ (void)_collect:(id)node path:(NSString *)path into:(NSMutableArray *)out depth:(NSUInteger)depth;
+ (id)_scrub:(id)node removed:(NSUInteger *)count depth:(NSUInteger)depth;
+ (void)_patchAdSwitches:(NSMutableDictionary *)d;
@end

@implementation XCJSONScrubber

+ (NSArray<NSString *> *)keywords {
    return XCPromoWords();
}

static BOOL XCStringLooksPromo(NSString *s) {
    if (s.length == 0) return NO;
    NSString *lower = s.lowercaseString;
    for (NSString *kw in XCPromoWords()) {
        if ([lower containsString:kw.lowercaseString]) return YES;
    }
    return NO;
}

/// 实测得到的推广位 slug（来自 resources 接口 / 神策 tracing）
static NSArray<NSString *> *XCPromoSlugs(void) {
    static NSArray *kw = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        kw = @[
               // ── 实测：首页推广 section（3.20.5 抓包确认）──
               @"BRAND_LOGO_CAROUSEL_SECTION",  // 福利社格子（美团红包/淘闪购/京东红包…）
               @"KEY_VISUAL_SECTION",           // 主视觉横幅（请学生免费喝 10000 杯奶茶）
               @"SECOND_TAB",                   // 二级 tab（抖音补贴 / 赚钱 / 特领元宝）
               @"TAB_SWITCH_SECTION",           // tab 切换区
               @"CPS_COUPON_SECTION",           // CPS 优惠券区块
               @"SPECIAL_OFFERS_SECTION",       // 特惠区块
               @"DOUYIN_BANNER",                // 抖音 banner
               // ── 通用推广关键词 ──
               @"BANNER", @"_AD", @"AD_", @"ADVER", @"FLOAT", @"POPUP",
               @"REDPACKET", @"RED_PACKET", @"REDPACK", @"COUPON", @"PROMOT",
               @"WELFARE", @"LOTTERY", @"GIFT", @"RAIN", @"LUCKY"];
    });
    return kw;
}

static BOOL XCStringIsPromoSlug(NSString *s) {
    if (s.length == 0) return NO;
    NSString *u = s.uppercaseString;
    for (NSString *kw in XCPromoSlugs()) {
        if ([u containsString:kw]) return YES;
    }
    return NO;
}

/// 【关键】实测得到的推广位 resource_id（3.20.5 抓包确认）
///
/// 响应结构里，顶层 resource **只有 resource_id，没有 resource_slug**：
///   {"status":{"code":0},"resources":[
///       {"resource_id":301,"value":[
///           {"rank_id":0,"content":"{...}","resource_slug":"BRAND_LOGO_CAROUSEL_SECTION",...}
///       ]}
///   ]}
/// resource_slug 藏在 value 的子对象里。
/// 之前只按 slug 匹配 → 删的是 value 里的子对象，顶层 resource 还在，App 照样渲染。
/// 必须按 resource_id 匹配顶层 resource 才能真正去掉。
static NSSet *XCPromoResourceIDs(void) {
    static NSSet *ids = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ids = [NSSet setWithObjects:
               @291,   // CPS_COUPON_SECTION            CPS 券（美团/淘宝跳转）
               @293,   // KEY_VISUAL_SECTION            主视觉头图（蚕宝省钱攻略横幅）
               @299,   // SPECIAL_OFFERS_SECTION        特惠专场（抖音商城）
               @301,   // BRAND_LOGO_CAROUSEL_SECTION   金刚区（美团/淘宝闪购/京东 logo）
               @302,   // TAB_SWITCH_SECTION            tab 切换区（特惠专场）
               nil];
    });
    return ids;
}

static BOOL XCNumberIsPromoResourceID(id rid) {
    if (rid == nil || [rid isKindOfClass:[NSNull class]]) return NO;
    if (![rid respondsToSelector:@selector(integerValue)]) return NO;
    return [XCPromoResourceIDs() containsObject:@([rid integerValue])];
}

/// resources / value 数组里的推广资源项
static BOOL XCDictIsPromoResource(NSDictionary *dict) {
    // 【最高优先】顶层 resource 只有 resource_id，按 id 判定（实测 5 个全是推广 section）
    if (XCNumberIsPromoResourceID(dict[@"resource_id"])) return YES;

    id slug = dict[@"resource_slug"];
    if ([slug isKindOfClass:[NSString class]] && XCStringIsPromoSlug(slug)) return YES;

    id tracing = dict[@"tracing"];
    if ([tracing isKindOfClass:[NSString class]] && XCStringIsPromoSlug(tracing)) return YES;

    // content 是 JSON 字符串，里面含推广文案也算
    id content = dict[@"content"];
    if ([content isKindOfClass:[NSString class]] && XCStringLooksPromo(content)) return YES;

    return NO;
}

/// 判断一个字典是否是促销节点：只检查类型类字段 + 关键业务字段
static BOOL XCDictLooksPromo(NSDictionary *dict) {
    for (NSString *key in dict) {
        NSString *lk = key.lowercaseString;
        id val = dict[key];

        BOOL isTypeKey = NO;
        for (NSString *tk in XCTypeKeys()) {
            if ([lk isEqualToString:tk.lowercaseString]) { isTypeKey = YES; break; }
        }

        if (isTypeKey && [val isKindOfClass:[NSString class]] && XCStringLooksPromo(val)) {
            return YES;
        }

        // 字段名本身就是促销语义（如 isShowRedPacket / couponInfo）
        if ([lk containsString:@"redpacket"] || [lk containsString:@"red_packet"] ||
            [lk containsString:@"coupon"] || [lk containsString:@"redenvelope"]) {
            if (![val isKindOfClass:[NSNull class]]) return YES;
        }

        // ── 实测规则（来自神策埋点 HomePage_Feed_*_Ex 的真实字段）──
        // ad_type 非 0 = 广告位（埋点里外卖红包 banner 就是 "ad_type":1）
        if ([lk isEqualToString:@"ad_type"]) {
            if ([val isKindOfClass:[NSNumber class]] && [val integerValue] != 0) return YES;
            if ([val isKindOfClass:[NSString class]] && [val integerValue] != 0) return YES;
        }

        // information_pic_list = 信息流推广图列表（如 "(高)今日可领--外卖红包.gif"）
        if ([lk isEqualToString:@"information_pic_list"]) {
            if (![val isKindOfClass:[NSNull class]]) return YES;
        }
    }
    return NO;
}

#pragma mark - Summary

+ (NSString *)summaryOfJSON:(id)json {
    NSMutableArray<NSString *> *hits = [NSMutableArray array];
    [self _collect:json path:@"$" into:hits depth:0];

    if (hits.count == 0) return @"（未发现疑似促销节点）";

    NSMutableString *m = [NSMutableString string];
    [m appendFormat:@"发现 %lu 个疑似促销节点：\n", (unsigned long)hits.count];
    NSUInteger n = MIN(hits.count, (NSUInteger)40);
    for (NSUInteger i = 0; i < n; i++) {
        [m appendFormat:@"  %@\n", hits[i]];
    }
    if (hits.count > n) {
        [m appendFormat:@"  …还有 %lu 个\n", (unsigned long)(hits.count - n)];
    }
    return m;
}

+ (void)_collect:(id)node path:(NSString *)path into:(NSMutableArray *)out depth:(NSUInteger)depth {
    if (depth > 12) return;

    if ([node isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = node;
        if (XCDictLooksPromo(dict)) {
            NSString *typeVal = @"";
            for (NSString *k in XCTypeKeys()) {
                id v = dict[k];
                if ([v isKindOfClass:[NSString class]]) { typeVal = v; break; }
            }
            [out addObject:[NSString stringWithFormat:@"%@  type=%@  keys=%@",
                            path, typeVal.length ? typeVal : @"?",
                            [[dict allKeys] componentsJoinedByString:@","]]];
        }
        for (NSString *k in dict) {
            [self _collect:dict[k] path:[path stringByAppendingFormat:@".%@", k] into:out depth:depth + 1];
        }
    } else if ([node isKindOfClass:[NSArray class]]) {
        NSArray *arr = node;
        NSUInteger i = 0;
        for (id item in arr) {
            [self _collect:item path:[path stringByAppendingFormat:@"[%lu]", (unsigned long)i]
                      into:out depth:depth + 1];
            i++;
            if (i > 200) break;
        }
    }
}

#pragma mark - Scrub

+ (id)scrubJSON:(id)json removed:(NSUInteger *)removed {
    NSUInteger count = 0;
    id result = [self _scrub:json removed:&count depth:0];
    if (removed) *removed = count;
    return result;
}

+ (id)_scrub:(id)node removed:(NSUInteger *)count depth:(NSUInteger)depth {
    if (depth > 12) return node;

    if ([node isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = node;
        NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:dict.count];
        for (NSString *k in dict) {
            out[k] = [self _scrub:dict[k] removed:count depth:depth + 1];
        }
        // 关掉广告开关：不删节点，最安全也最有效
        [self _patchAdSwitches:out];
        return out;
    }

    if ([node isKindOfClass:[NSArray class]]) {
        NSArray *arr = node;
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:arr.count];
        for (id item in arr) {
            if ([item isKindOfClass:[NSDictionary class]] &&
                (XCDictLooksPromo(item) || XCDictIsPromoResource(item))) {
                *count = *count + 1;
                continue;   // 丢掉整个促销节点
            }
            [out addObject:[self _scrub:item removed:count depth:depth + 1]];
        }
        return out;
    }

    return node;
}

/// 改写广告开关字段。
/// 实测结构：{"ad_open":1,"ad_type":[1],"ios_slot_id":"...","ad_source":[6],
///           "resource_id":194,"put_id":7825,"tracing":"PROGRAM_RESOURCE-194-7825-476-"}
/// 把 ad_open 置 0 即可关掉该位置的广告，同时保留正常内容。
+ (void)_patchAdSwitches:(NSMutableDictionary *)d {
    // 保持字段类型不变，避免 App 取值时类型不匹配
    id adOpen = d[@"ad_open"];
    if (adOpen != nil) {
        if ([adOpen isKindOfClass:[NSString class]]) {
            d[@"ad_open"] = @"0";
        } else if ([adOpen isKindOfClass:[NSNumber class]]) {
            d[@"ad_open"] = @0;
        }
    }
    if ([d[@"ad_type"] isKindOfClass:[NSArray class]] && [d[@"ad_type"] count] > 0) {
        d[@"ad_type"] = @[];
    }
    if (d[@"ios_slot_id"] != nil && [d[@"ios_slot_id"] isKindOfClass:[NSString class]]) {
        d[@"ios_slot_id"] = @"";
    }
    if (d[@"ios_ad_id"] != nil && [d[@"ios_ad_id"] isKindOfClass:[NSString class]]) {
        d[@"ios_ad_id"] = @"";
    }
    if (d[@"ad_photo"] != nil && [d[@"ad_photo"] isKindOfClass:[NSString class]]) {
        d[@"ad_photo"] = @"";
    }
}

@end
