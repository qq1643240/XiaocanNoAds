//
//  XCPrefsController.m
//  XiaocanNoAds
//

#import "XCPrefsController.h"
#import "XCNoAdsConfig.h"
#import "XCAdBlocker.h"

@interface XCPrefsController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@end

@implementation XCPrefsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"小蚕去广告";

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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 4; }

- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    if (s == 0) return @"总开关";
    if (s == 1) return @"拦截项";
    if (s == 2) return @"其它";
    return @"拦截统计";
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 1;
    if (s == 1) return 6;
    if (s == 2) return 1;
    // 统计：1 行计数 + 最多 3 行最近拦截的 URL
    NSUInteger recent = [XCAdBlocker shared].recentBlocked.count;
    return 1 + MIN(recent, (NSUInteger)3);
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"c"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"];
    c.selectionStyle = UITableViewCellSelectionStyleNone;

    UISwitch *sw = [[UISwitch alloc] init];
    sw.onTintColor = UIColor.systemGreenColor;
    c.accessoryView = sw;

    XCNoAdsConfig *cfg = [XCNoAdsConfig shared];

    if (ip.section == 0) {
        c.textLabel.text = @"启用去广告";
        sw.on = cfg.enabled;
        sw.tag = 0;
    } else if (ip.section == 1) {
        NSArray *names = @[@"开屏广告", @"插屏广告", @"横幅广告", @"信息流广告", @"激励视频(自动完成)", @"兜底隐藏广告View"];
        c.textLabel.text = names[ip.row];
        sw.tag = 100 + ip.row;
        BOOL vals[6] = { cfg.blockSplash, cfg.blockInterstitial, cfg.blockBanner,
                         cfg.blockFeed, cfg.blockReward, cfg.hideAdViews };
        sw.on = vals[ip.row];
    } else if (ip.section == 2) {
        c.textLabel.text = @"输出调试日志";
        c.textLabel.textColor = UIColor.secondaryLabelColor;
        sw.on = cfg.logEnabled;
        sw.tag = 1;
    } else {
        // 拦截统计：只读展示
        c.accessoryView = nil;
        c.textLabel.font = [UIFont systemFontOfSize:13];
        if (ip.row == 0) {
            c.textLabel.textColor = UIColor.labelColor;
            c.textLabel.font = [UIFont boldSystemFontOfSize:15];
            c.textLabel.text = [NSString stringWithFormat:@"已拦截广告请求：%lu 次",
                                (unsigned long)[XCAdBlocker shared].blockedCount];
        } else {
            c.textLabel.textColor = UIColor.secondaryLabelColor;
            c.textLabel.numberOfLines = 2;
            NSArray *recent = [XCAdBlocker shared].recentBlocked;
            NSUInteger idx = ip.row - 1;
            c.textLabel.text = (idx < recent.count) ? recent[idx] : @"";
        }
        return c;
    }

    [sw addTarget:self action:@selector(onSwitch:) forControlEvents:UIControlEventValueChanged];
    return c;
}

- (void)onSwitch:(UISwitch *)sw {
    XCNoAdsConfig *cfg = [XCNoAdsConfig shared];

    if (sw.tag == 0) {
        cfg.enabled = sw.on;
    } else if (sw.tag == 1) {
        cfg.logEnabled = sw.on;
    } else {
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

@end
