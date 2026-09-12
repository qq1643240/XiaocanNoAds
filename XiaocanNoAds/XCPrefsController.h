//
//  XCPrefsController.h
//  XiaocanNoAds
//
//  插件设置面板
//  唤起方式：三指双击屏幕（由 Tweak.xm 安装手势）
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface XCPrefsController : UIViewController

/// 三指双击手势入口（Tweak 把手势装到 keyWindow 上）
+ (void)xc_handlePrefsGesture:(UIGestureRecognizer *)gesture;

@end

NS_ASSUME_NONNULL_END
