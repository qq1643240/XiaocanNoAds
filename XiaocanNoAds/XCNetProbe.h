//
//  XCNetProbe.h
//  XiaocanNoAds
//
//  基于 NSURLProtocol 的精准抓包 / 改写。
//
//  背景：App 业务请求走 https://gw.xiaocantech.com/rpc，
//        且很可能由 Kotlin/Native 直接解析字节（不经过 NSJSONSerialization），
//        所以只能在网络层拿原始响应。
//
//  安全设计：只拦截 App 自有域名，其余请求完全透传，不影响 App 主流程。
//

#import <Foundation/Foundation.h>

@interface XCNetProbe : NSObject

/// App 启动后调用一次（内部会注册 NSURLProtocol）
+ (void)install;

@end
