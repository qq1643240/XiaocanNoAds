//
//  XCJSONScrubber.h
//  XiaocanNoAds
//
//  从接口 JSON 里识别（并可选剔除）促销节点。
//  设计原则：只在「明确的类型字段」命中关键词时才动手，避免误伤正常业务数据。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface XCJSONScrubber : NSObject

/// 递归扫描，返回「疑似促销节点」的可读摘要（诊断用，不修改数据）
+ (NSString *)summaryOfJSON:(nullable id)json;

/// 递归剔除疑似促销节点，removed 返回剔除个数。未命中时原样返回。
+ (id)scrubJSON:(id)json removed:(NSUInteger *)removed;

/// 命中的促销关键词（诊断面板展示用）
+ (NSArray<NSString *> *)keywords;

@end

NS_ASSUME_NONNULL_END
