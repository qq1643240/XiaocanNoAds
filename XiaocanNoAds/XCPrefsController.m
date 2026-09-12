//
//  XCPrefsController.m
//  XiaocanNoAds
//

#import "XCPrefsController.h"
#import "XCNoAdsConfig.h"
#import "XCAdBlocker.h"
#import "XCDiag.h"
#import "XCJSONScrubber.h"

@interface XCPrefsController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@end

@implementation XCPrefsController

#pragma mark - 入口

+ (UIViewController *)xc_topViewController {
    UIWindow *keyWin = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { keyWin = w; break; }
    }
    if (keyWin == nil) keyWin = [UIApplication sharedApplication].windows.firstObject;

    UIViewController *top = keyWin.rootViewController;
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    if ([top isKindOfClass:[UINavigationController class]]) {
        top = ((UINavigationController *)top).visibleViewController;
    } else if ([top isKindOfClass:[UITabBarController class]]) {
        top = ((UITabBarController *)top).selectedViewController;
    }
    return top;
}

+ (void)xc_handlePrefsGesture:(UIGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;

    UIViewController *top = [self xc_topViewController];
    if (top == nil) return;
    if ([top isKindOfClass:[XCPrefsController class]]) return;

    XCPrefsController *prefs = [[XCPrefsController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:prefs];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [top presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"小蚕去广告 v1.3.0";

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(onDone)];

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.table];
}

- (void)onDone {
    [[XCNoAdsConfig shared] save];
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Data

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 6; }

- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    switch (s) {
        case 0: return @"总开关";
        case 1: return @"广告 SDK 拦截";
        case 2: return @"数据层拦截（对付 SwiftUI / 跨端推广位）";
        case 3: return @"诊断";
        case 4: return @"拦截统计";
        default: return @"其它";
    }
}

- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if (s == 2) {
        return @"首页促销位由服务端 JSON 驱动、SwiftUI 渲染，无法用类名 hook。"
               @"「清洗接口 JSON」会从接口返回里剔除带红包/券/补贴等特征的节点。";
    }
    if (s == 3) {
        return @"诊断日志记录了所有网络请求与接口 JSON。"
               @"把日志导出发给我，就能精确定位剩余广告来自哪条接口。";
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 1;
    if (s == 1) return 6;
    if (s == 2) return 2;
    if (s == 3) return 3;
    if (s == 4) {
        NSUInteger recent = [XCAdBlocker shared].recentBlocked.count;
        return 1 + MIN(recent, (NSUInteger)3);
    }
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"c"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"];
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    c.accessoryView = nil;
    c.accessoryType = UITableViewCellAccessoryNone;
    c.textLabel.numberOfLines = 1;
    c.textLabel.textColor = UIColor.labelColor;

    XCNoAdsConfig *cfg = [XCNoAdsConfig shared];

    UISwitch *sw = [[UISwitch alloc] init];
    sw.onTintColor = UIColor.systemGreenColor;

    if (ip.section == 0) {
        c.textLabel.text = @"启用去广告";
        sw.on = cfg.enabled;
        sw.tag = 0;
        c.accessoryView = sw;
        [sw addTarget:self action:@selector(onSwitch:) forControlEvents:UIControlEventValueChanged];
        return c;
    }

    if (ip.section == 1) {
        NSArray *names = @[@"开屏广告", @"插屏广告", @"横幅广告",
                           @"信息流广告", @"激励视频(自动完成)", @"兜底隐藏广告View"];
        c.textLabel.text = names[ip.row];
        sw.tag = 100 + ip.row;
        BOOL vals[6] = { cfg.blockSplash, cfg.blockInterstitial, cfg.blockBanner,
                         cfg.blockFeed, cfg.blockReward, cfg.hideAdViews };
        sw.on = vals[ip.row];
        c.accessoryView = sw;
        [sw addTarget:self action:@selector(onSwitch:) forControlEvents:UIControlEventValueChanged];
        return c;
    }

    if (ip.section == 2) {
        if (ip.row == 0) {
            c.textLabel.text = @"清洗接口 JSON 促销节点";
            sw.on = cfg.scrubPromoJSON;
            sw.tag = 200;
        } else {
            c.textLabel.text = @"记录网络抓包（诊断）";
            sw.on = cfg.captureNet;
            sw.tag = 201;
        }
        c.accessoryView = sw;
        [sw addTarget:self action:@selector(onSwitch:) forControlEvents:UIControlEventValueChanged];
        return c;
    }

    if (ip.section == 3) {
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        c.textLabel.font = [UIFont systemFontOfSize:15];
        if (ip.row == 0) {
            c.textLabel.text = @"导出诊断日志";
            c.textLabel.textColor = UIColor.systemBlueColor;
        } else if (ip.row == 1) {
            unsigned long long size = [XCDiag logSize];
            c.textLabel.text = [NSString stringWithFormat:@"日志大小：%.1f KB",
                                size / 1024.0];
            c.textLabel.textColor = UIColor.secondaryLabelColor;
        } else {
            c.textLabel.text = @"清空日志";
            c.textLabel.textColor = UIColor.systemRedColor;
        }
        return c;
    }

    if (ip.section == 4) {
        c.textLabel.font = [UIFont systemFontOfSize:13];
        if (ip.row == 0) {
            c.textLabel.textColor = UIColor.labelColor;
            c.textLabel.font = [UIFont boldSystemFontOfSize:15];
            c.textLabel.text = [NSString stringWithFormat:
                @"已拦截：%lu 次   |   HTTP：%lu   JSON：%lu",
                (unsigned long)[XCAdBlocker shared].blockedCount,
                (unsigned long)[XCDiag shared].httpCount,
                (unsigned long)[XCDiag shared].jsonCount];
        } else {
            c.textLabel.textColor = UIColor.secondaryLabelColor;
            c.textLabel.numberOfLines = 2;
            NSArray *recent = [XCAdBlocker shared].recentBlocked;
            NSUInteger idx = ip.row - 1;
            c.textLabel.text = (idx < recent.count) ? recent[idx] : @"";
        }
        return c;
    }

    c.textLabel.text = @"输出调试日志到系统控制台";
    c.textLabel.textColor = UIColor.secondaryLabelColor;
    sw.on = cfg.logEnabled;
    sw.tag = 1;
    c.accessoryView = sw;
    [sw addTarget:self action:@selector(onSwitch:) forControlEvents:UIControlEventValueChanged];
    return c;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];

    if (ip.section == 3) {
        if (ip.row == 0) {
            [self exportLog];
        } else if (ip.row == 2) {
            [XCDiag clearLog];
            [self.table reloadData];
            [self toast:@"日志已清空"];
        }
        return;
    }
}

- (void)onSwitch:(UISwitch *)sw {
    XCNoAdsConfig *cfg = [XCNoAdsConfig shared];

    if (sw.tag == 0) {
        cfg.enabled = sw.on;
    } else if (sw.tag == 1) {
        cfg.logEnabled = sw.on;
    } else if (sw.tag == 200) {
        cfg.scrubPromoJSON = sw.on;
    } else if (sw.tag == 201) {
        cfg.captureNet = sw.on;
        [XCDiag shared].captureEnabled = sw.on;
    } else if (sw.tag >= 100) {
        switch (sw.tag - 100) {
            case 0: cfg.blockSplash = sw.on; break;
            case 1: cfg.blockInterstitial = sw.on; break;
            case 2: cfg.blockBanner = sw.on; break;
            case 3: cfg.blockFeed = sw.on; break;
            case 4: cfg.blockReward = sw.on; break;
            case 5: cfg.hideAdViews = sw.on; break;
        }
    }
    [cfg save];
}

#pragma mark - 导出

- (void)exportLog {
    NSData *data = [XCDiag logData];
    if (data.length == 0) {
        [self toast:@"日志为空，请先打开 App 用一会儿"];
        return;
    }

    NSString *dir = [XCDiag logDirPath];
    NSString *name = @"xiaocan_noads_diag.log";
    NSString *tmp = [dir stringByAppendingPathComponent:name];
    [data writeToFile:tmp atomically:YES];

    NSURL *url = [NSURL fileURLWithPath:tmp];
    UIActivityViewController *avc =
        [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    avc.popoverPresentationController.sourceView = self.view;
    avc.popoverPresentationController.sourceRect = self.view.bounds;
    [self presentViewController:avc animated:YES completion:nil];
}

- (void)toast:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil
                                                               message:msg
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:a animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [a dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}

@end
