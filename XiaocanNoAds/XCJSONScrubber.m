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

@implementation XCJSONScrubber

+ (void)_collect:(id)node path:(NSString *)path into:(NSMutableArray *)out depth:(NSUInteger)depth;
+ (id)_scrub:(id)node removed:(NSUInteger *)count depth:(NSUInteger)depth;

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
        return out;
    }

    if ([node isKindOfClass:[NSArray class]]) {
        NSArray *arr = node;
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:arr.count];
        for (id item in arr) {
            if ([item isKindOfClass:[NSDictionary class]] && XCDictLooksPromo(item)) {
                *count = *count + 1;
                continue;   // 丢掉整个促销节点
            }
            [out addObject:[self _scrub:item removed:count depth:depth + 1]];
        }
        return out;
    }

    return node;
}

@end
