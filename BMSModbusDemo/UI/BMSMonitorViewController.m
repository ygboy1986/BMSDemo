#import "BMSMonitorViewController.h"

static UIColor *BMSBlue(void) { return [UIColor colorWithRed:0.035 green:0.40 blue:0.93 alpha:1]; }
static UILabel *BMSText(NSString *text, CGFloat size, UIFontWeight weight) {
    UILabel *label = [UILabel new]; label.text = text; label.font = [UIFont systemFontOfSize:size weight:weight];
    [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    label.numberOfLines = 0; label.textColor = [UIColor colorWithWhite:0.25 alpha:1]; return label;
}

@interface BMSCellsViewController : UITableViewController
@property (nonatomic, strong) BMSRealtimeData *snapshot;
@property (nonatomic, copy) NSString *statusText;
@property (nonatomic, copy) void (^readAction)(void);
- (void)reloadSnapshot;
@end
@implementation BMSCellsViewController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"查看单节电压"; self.tableView.rowHeight = 58;
    self.tableView.backgroundColor = UIColor.whiteColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"刷新" style:UIBarButtonItemStylePlain target:self action:@selector(readTapped)];
    self.refreshControl = [UIRefreshControl new]; [self.refreshControl addTarget:self action:@selector(readTapped) forControlEvents:UIControlEventValueChanged];
    UILabel *footer = BMSText(@"全部 32 路按设备原值显示，0 mV 保留为 0。均衡位与电芯的对应关系待确认。", 12, UIFontWeightRegular);
    footer.frame = CGRectMake(16, 0, 300, 76); footer.textAlignment = NSTextAlignmentCenter;
    self.tableView.tableFooterView = footer;
}
- (void)readTapped { if (self.readAction) { self.readAction(); } }
- (void)reloadSnapshot {
    if (!self.isViewLoaded) { return; }
    UILabel *header = BMSText(self.statusText ?: @"尚未读取", 12, UIFontWeightRegular);
    header.textAlignment = NSTextAlignmentCenter; header.frame = CGRectMake(0,0,320,52);
    self.tableView.tableHeaderView = header;
    [self.refreshControl endRefreshing]; [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 32; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (!cell) { cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"cell"]; }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSString *value = @"—";
    if (self.snapshot.cellVoltages.count > indexPath.row) {
        id voltage = self.snapshot.cellVoltages[indexPath.row];
        value = voltage == NSNull.null ? @"无效/异常" : [NSString stringWithFormat:@"%.0f mV", [voltage doubleValue]*1000];
    }
    cell.textLabel.text = [NSString stringWithFormat:@"电池%ld   %@", (long)indexPath.row+1, value];
    cell.textLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightRegular];
    cell.detailTextLabel.text = self.snapshot ? [NSString stringWithFormat:@"均衡%@", [self.snapshot balanceTextForCell:indexPath.row]] : @"—";
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12]; cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessibilityLabel = [NSString stringWithFormat:@"%@，%@", cell.textLabel.text, cell.detailTextLabel.text];
    return cell;
}
@end

@interface BMSMonitorViewController ()
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) UIStackView *probes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UILabel *> *values;
@property (nonatomic, strong) NSMutableArray<UILabel *> *alarms;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *updatedLabel;
@property (nonatomic, strong) UILabel *rawStateLabel;
@property (nonatomic, strong) UILabel *faultSummary;
@property (nonatomic, strong) UIProgressView *batteryProgress;
@property (nonatomic, strong) UIButton *probeButton;
@property (nonatomic, strong) UIButton *readButton;
@property (nonatomic, strong) UISwitch *autoSwitch;
@property (nonatomic, strong) UIRefreshControl *pullRefresh;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) BMSRealtimeData *snapshot;
@property (nonatomic, strong) NSNumber *cellCount;
@property (nonatomic, strong) NSDate *updatedAt;
@property (nonatomic, strong) BMSCellsViewController *cellsController;
@property (nonatomic) NSUInteger connectionGeneration;
@property (nonatomic) BOOL countAttempted;
@property (nonatomic) BOOL initialReadNeeded;
@property (nonatomic) BOOL reading;
@property (nonatomic, copy) NSString *connectionMessage;
@end

@implementation BMSMonitorViewController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"数据监控";
    self.view.backgroundColor = [UIColor colorWithWhite:0.965 alpha:1];
    self.values = NSMutableDictionary.dictionary; self.alarms = NSMutableArray.array;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"设备" style:UIBarButtonItemStylePlain target:self action:@selector(connectionTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"日志" style:UIBarButtonItemStylePlain target:self action:@selector(logTapped)];
    UIScrollView *scroll = [UIScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints = NO; scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];
    self.pullRefresh = [UIRefreshControl new]; [self.pullRefresh addTarget:self action:@selector(manualRead) forControlEvents:UIControlEventValueChanged]; scroll.refreshControl = self.pullRefresh;
    self.stack = [UIStackView new]; self.stack.axis = UILayoutConstraintAxisVertical; self.stack.spacing = 18; self.stack.translatesAutoresizingMaskIntoConstraints = NO; [scroll addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor], [scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:14], [self.stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [self.stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:12], [self.stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-12]
    ]];
    self.statusLabel = BMSText(self.connectionMessage ?: @"未连接设备 · 点击左上角“设备”连接", 13, UIFontWeightMedium);
    self.statusLabel.textColor = UIColor.secondaryLabelColor; [self.stack addArrangedSubview:self.statusLabel];
    UIStackView *state = [self section:@"实时状态"];
    self.updatedLabel = BMSText(@"更新时间：尚未读取", 12, UIFontWeightRegular); self.updatedLabel.textColor = UIColor.secondaryLabelColor; [state addArrangedSubview:self.updatedLabel];
    UIStackView *hero = [UIStackView new]; hero.axis = UILayoutConstraintAxisHorizontal; hero.distribution = UIStackViewDistributionFillEqually; hero.alignment = UIStackViewAlignmentCenter; hero.spacing = 16;
    UIStackView *battery = [UIStackView new]; battery.axis = UILayoutConstraintAxisVertical; battery.spacing = 6;
    UIImageView *batteryIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"battery.100"]]; batteryIcon.tintColor = BMSBlue(); batteryIcon.contentMode = UIViewContentModeScaleAspectFit; [batteryIcon.heightAnchor constraintEqualToConstant:65].active=YES;
    [battery addArrangedSubview:batteryIcon]; self.batteryProgress = [UIProgressView new]; self.batteryProgress.progressTintColor = BMSBlue(); [battery addArrangedSubview:self.batteryProgress];
    [hero addArrangedSubview:battery];
    UIStackView *states = [UIStackView new]; states.axis = UILayoutConstraintAxisVertical; states.spacing = 12;
    [states addArrangedSubview:[self metric:@"运行模式" key:@"mode" icon:nil]];
    [states addArrangedSubview:[self metric:@"充放电状态" key:@"state" icon:nil]]; [hero addArrangedSubview:states]; [state addArrangedSubview:hero];
    [self grid:@[@[@"SOC电量",@"soc",@""],@[@"SOH",@"soh",@""],@[@"剩余使用时间",@"remaining",@""]] columns:3 in:state];
    self.rawStateLabel = BMSText(@"运行状态、剩余时间及均衡映射待确认", 11, UIFontWeightRegular); self.rawStateLabel.textColor = UIColor.secondaryLabelColor; [state addArrangedSubview:self.rawStateLabel];

    UIStackView *voltage = [self section:@"电压信息"];
    [self grid:@[@[@"总电压",@"voltage",@"bolt.circle"],@[@"电流",@"current",@"a.circle"],@[@"功率",@"power",@"waveform.path"],@[@"最高电压",@"maxVoltage",@"arrow.up.circle"],@[@"最低电压",@"minVoltage",@"arrow.down.circle"],@[@"压差",@"difference",@"gauge.with.dots.needle.50percent"],@[@"最高电压串号",@"maxIndex",@"arrow.up"],@[@"最低电压串号",@"minIndex",@"arrow.down"],@[@"电芯串数",@"count",@"battery.100"]] columns:3 in:voltage];
    [voltage addArrangedSubview:[self action:@"查看单节电压" selector:@selector(showCells)]];
    [self grid:@[@[@"环境温度",@"ambient",@"thermometer.medium"],@[@"MOS温度",@"mosTemp",@"cpu"],@[@"探针最高温度",@"maxTemp",@"thermometer.high"],@[@"探针最低温度",@"minTemp",@"thermometer.low"]] columns:2 in:voltage];
    self.probeButton = [self action:@"查看探针温度 ﹀" selector:@selector(toggleProbes)]; [voltage addArrangedSubview:self.probeButton];
    self.probes = [UIStackView new]; self.probes.axis = UILayoutConstraintAxisVertical; self.probes.spacing=20;
    NSMutableArray *probeItems = NSMutableArray.array;
    for (NSUInteger i=0;i<6;i++) { [probeItems addObject:@[[NSString stringWithFormat:@"探针温度%lu",(unsigned long)i+1],[NSString stringWithFormat:@"probe%lu",(unsigned long)i],@""]]; }
    [self grid:probeItems columns:3 in:self.probes]; self.probes.hidden=YES; [voltage addArrangedSubview:self.probes];

    UIStackView *mos = [self section:@"MOS状态"];
    [self grid:@[@[@"充电MOS状态",@"mos0",@""],@[@"放电MOS状态",@"mos1",@""],@[@"预充MOS状态",@"mos2",@""],@[@"预放MOS状态",@"mos3",@""],@[@"限流MOS状态",@"mos4",@""],@[@"循环次数",@"cycles",@""]] columns:3 in:mos];
    UIStackView *alarm = [self section:@"报警信息"];
    self.faultSummary = BMSText(@"尚未读取", 12, UIFontWeightRegular); [alarm addArrangedSubview:self.faultSummary];
    for (NSDictionary *item in [[BMSRealtimeData new] alarmRows]) {
        UIStackView *row = [UIStackView new]; row.axis = UILayoutConstraintAxisHorizontal; row.spacing = 8;
        UILabel *name=BMSText([@"• " stringByAppendingString:item[@"name"]],15,UIFontWeightRegular); [row addArrangedSubview:name];
        UILabel *value=BMSText(@"—",15,UIFontWeightMedium); value.textAlignment=NSTextAlignmentRight;
        [value setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal]; [row addArrangedSubview:value];
        [self.alarms addObject:value]; [alarm addArrangedSubview:row];
    }
    UIStackView *refresh = [self section:@"刷新设置"];
    UIStackView *refreshRow = [UIStackView new]; refreshRow.axis = UILayoutConstraintAxisHorizontal; refreshRow.alignment=UIStackViewAlignmentCenter;
    [refreshRow addArrangedSubview:BMSText(@"自动刷新（每2秒）",14,UIFontWeightRegular)];
    self.autoSwitch=[UISwitch new]; self.autoSwitch.on=YES; [self.autoSwitch addTarget:self action:@selector(autoChanged) forControlEvents:UIControlEventValueChanged]; [refreshRow addArrangedSubview:self.autoSwitch]; [refresh addArrangedSubview:refreshRow];
    self.readButton=[self action:@"读取实时数据" selector:@selector(manualRead)]; [refresh addArrangedSubview:self.readButton];
    UILabel *note=BMSText(@"“—”表示未读取或无效值。压差按设备配置串数计算；探针最高/最低包含全部6路的0℃读数。",12,UIFontWeightRegular); note.textColor=UIColor.secondaryLabelColor; [refresh addArrangedSubview:note];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationInactive) name:UIApplicationWillResignActiveNotification object:nil];
    [self renderSnapshot];
}
- (void)dealloc { [self.timer invalidate]; [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self startTimer]; if (!self.snapshot) { self.initialReadNeeded=YES; } [self tick]; }
- (void)applicationInactive { [self.timer invalidate]; self.timer=nil; }
- (void)applicationActive { if (self.isViewLoaded) { [self startTimer]; [self tick]; } }
- (void)connectionTapped { if (self.connectionAction) { self.connectionAction(); } }
- (void)logTapped { if (self.logAction) { self.logAction(); } }
- (void)autoChanged { if (self.autoSwitch.on) { [self tick]; } }
- (void)startTimer {
    if (self.timer) { return; } __weak typeof(self) weakSelf=self;
    self.timer=[NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer) { [weakSelf tick]; }];
}
- (BOOL)monitorIsVisible {
    UIViewController *top=self.navigationController.topViewController;
    return self.navigationController.view.window && self.tabBarController.selectedViewController==self.navigationController && (top==self || top==self.cellsController) && UIApplication.sharedApplication.applicationState==UIApplicationStateActive;
}
- (void)tick {
    if (![self monitorIsVisible] || !self.client.transport.isConnected || self.client.isBusy || self.reading) { return; }
    if (self.autoSwitch.on || self.initialReadNeeded) { [self readSnapshot]; }
}
- (void)manualRead {
    if (!self.client.transport.isConnected) { [self setReadStatus:@"未连接设备，请点击“设备”连接" failed:YES]; return; }
    if (self.client.isBusy || self.reading) { [self setReadStatus:@"设备正在处理其他请求，请稍后刷新" failed:NO]; return; }
    // 手动刷新也重新获取设备串数；不会读取任何本地型号预设。
    self.countAttempted=NO; [self readSnapshot];
}
- (void)connectionChanged:(BOOL)connected message:(NSString *)message {
    self.connectionGeneration++; self.reading=NO; self.snapshot=nil; self.updatedAt=nil; self.cellCount=nil; self.countAttempted=NO;
    self.initialReadNeeded=connected; self.connectionMessage=message;
    if (self.isViewLoaded) { [self renderSnapshot]; self.statusLabel.text=message; [self startTimer]; }
}
- (void)readSnapshot {
    self.initialReadNeeded=NO; self.reading=YES; self.readButton.enabled=NO;
    self.statusLabel.text=@"正在读取设备…";
    NSUInteger generation=self.connectionGeneration; BMSClient *client=self.client;
    __weak typeof(self) weakSelf=self;
    void (^readRealtime)(void)=^{
        if (weakSelf.connectionGeneration!=generation || weakSelf.client!=client) { return; }
        [client readRealtimeData:^(BMSRealtimeData *data, NSError *error) {
            if (weakSelf.connectionGeneration!=generation || weakSelf.client!=client) { return; }
            weakSelf.reading=NO; weakSelf.readButton.enabled=YES;
            if (error) { [weakSelf setReadStatus:[NSString stringWithFormat:@"读取失败：%@；上次读数未更新",error.localizedDescription] failed:YES]; return; }
            weakSelf.snapshot=data; weakSelf.updatedAt=NSDate.date;
            [weakSelf renderSnapshot];
            [weakSelf setReadStatus:weakSelf.cellCount ? @"设备已连接 · 数据已更新" : @"数据已更新 · 电芯串数未读取，电压统计暂缺" failed:!weakSelf.cellCount];
            if (client.logHandler) { client.logHandler(data.diagnosticText); }
            if (weakSelf.snapshotHandler) { weakSelf.snapshotHandler(data); }
        }];
    };
    if (!self.countAttempted) {
        self.countAttempted=YES;
        [client readRunningParametersFrom:335 count:1 completion:^(NSArray *words, NSError *error) {
            if (weakSelf.connectionGeneration!=generation || weakSelf.client!=client) { return; }
            NSNumber *count=words.firstObject;
            weakSelf.cellCount=!error && count.integerValue>=1 && count.integerValue<=32 ? count : nil;
            if (client.logHandler) { client.logHandler([NSString stringWithFormat:@"【监控串数】D335：%@；%@",count ?: @"未读取",error.localizedDescription ?: weakSelf.cellCount ? @"用于本次电压统计" : @"超出1～32，统计不计算"]); }
            readRealtime();
        }];
    } else { readRealtime(); }
}
- (void)setReadStatus:(NSString *)message failed:(BOOL)failed {
    self.statusLabel.text=message; self.statusLabel.textColor=failed ? UIColor.systemOrangeColor : UIColor.secondaryLabelColor;
    [self.pullRefresh endRefreshing];
    self.cellsController.statusText=[NSString stringWithFormat:@"%@\n%@",message,self.updatedLabel.text]; [self.cellsController reloadSnapshot];
}
- (void)renderSnapshot {
    NSDictionary *values=[self.snapshot monitorValuesForCellCount:self.cellCount];
    [self.values enumerateKeysAndObjectsUsingBlock:^(NSString *key, UILabel *label, BOOL *stop) {
        label.text=values[key] ?: @"—";
        label.textColor=[key hasPrefix:@"mos"] && ![key isEqual:@"mosTemp"] ? UIColor.labelColor : [UIColor colorWithWhite:0.25 alpha:1];
    }];
    self.batteryProgress.progress=self.snapshot && self.snapshot.displaySOC<=100 ? self.snapshot.displaySOC/100.0 : 0;
    if (self.updatedAt) {
        NSDateFormatter *format=[NSDateFormatter new]; format.dateFormat=@"yyyy-MM-dd HH:mm:ss";
        self.updatedLabel.text=[@"更新时间：" stringByAppendingString:[format stringFromDate:self.updatedAt]];
    } else { self.updatedLabel.text=@"更新时间：尚未读取"; }
    if (self.snapshot.rawRegisters.count==86) {
        NSArray *r=self.snapshot.rawRegisters;
        self.rawStateLabel.text=[NSString stringWithFormat:@"状态待确认：0x%04X / 0x%04X\n均衡待确认：0x%04X / 0x%04X",[r[65] unsignedShortValue],[r[66] unsignedShortValue],[r[63] unsignedShortValue],[r[64] unsignedShortValue]];
        self.faultSummary.text=[NSString stringWithFormat:@"故障位图 0x%04X · 等级 %lu%@",self.snapshot.faultBits,(unsigned long)self.snapshot.faultLevel,(self.snapshot.faultBits&0xC000) && self.snapshot.faultBits<0xFFFE ? @" · 含未定义故障位" : @""];
    } else { self.rawStateLabel.text=@"运行状态、剩余时间及均衡映射待确认"; self.faultSummary.text=@"尚未读取"; }
    NSArray *rows=[self.snapshot alarmRows];
    for (NSUInteger i=0;i<self.alarms.count;i++) {
        NSString *state=i<rows.count ? rows[i][@"state"] : @"—";
        self.alarms[i].text=state; self.alarms[i].textColor=[state isEqual:@"报警"] ? UIColor.systemRedColor : [state isEqual:@"正常"] ? UIColor.systemGreenColor : UIColor.secondaryLabelColor;
    }
    self.readButton.enabled=YES; [self.pullRefresh endRefreshing];
    self.cellsController.snapshot=self.snapshot; self.cellsController.statusText=self.updatedLabel.text; [self.cellsController reloadSnapshot];
}
- (void)toggleProbes { self.probes.hidden=!self.probes.hidden; [self.probeButton setTitle:self.probes.hidden ? @"查看探针温度 ﹀" : @"收起探针温度 ﹁" forState:UIControlStateNormal]; }
- (void)showCells {
    self.cellsController=[BMSCellsViewController new]; self.cellsController.snapshot=self.snapshot; self.cellsController.statusText=self.updatedLabel.text;
    __weak typeof(self) weakSelf=self; self.cellsController.readAction=^{ [weakSelf manualRead]; };
    self.cellsController.hidesBottomBarWhenPushed=YES;
    [self.navigationController pushViewController:self.cellsController animated:YES]; [self.cellsController reloadSnapshot];
}
- (UIStackView *)section:(NSString *)title {
    UIView *card=[UIView new]; card.backgroundColor=UIColor.whiteColor; card.layer.cornerRadius=14;
    card.layer.shadowColor=UIColor.blackColor.CGColor; card.layer.shadowOpacity=0.07; card.layer.shadowRadius=8; card.layer.shadowOffset=CGSizeMake(0,5);
    UIStackView *stack=[UIStackView new]; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=18; stack.translatesAutoresizingMaskIntoConstraints=NO; [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:18],[stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-20],[stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],[stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14]]];
    UILabel *heading=BMSText([@"▎" stringByAppendingString:title],16,UIFontWeightSemibold); heading.textColor=BMSBlue(); [stack addArrangedSubview:heading]; [self.stack addArrangedSubview:card]; return stack;
}
- (UIView *)metric:(NSString *)title key:(NSString *)key icon:(NSString *)icon {
    UIStackView *stack=[UIStackView new]; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=5; stack.alignment=UIStackViewAlignmentFill;
    if (icon.length) { UIImageView *image=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:icon]]; image.tintColor=BMSBlue(); image.contentMode=UIViewContentModeScaleAspectFit; [image.heightAnchor constraintEqualToConstant:30].active=YES; [stack addArrangedSubview:image]; }
    UILabel *value=BMSText(@"—",17,UIFontWeightSemibold); value.font=[UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightSemibold]; value.textAlignment=NSTextAlignmentCenter; value.adjustsFontSizeToFitWidth=YES; value.minimumScaleFactor=0.7; value.numberOfLines=1;
    UILabel *name=BMSText(title,12,UIFontWeightRegular); name.textAlignment=NSTextAlignmentCenter; name.textColor=UIColor.secondaryLabelColor;
    [stack addArrangedSubview:value]; [stack addArrangedSubview:name]; self.values[key]=value;
    stack.isAccessibilityElement=NO; value.accessibilityIdentifier=key;
    return stack;
}
- (void)grid:(NSArray<NSArray<NSString *> *> *)items columns:(NSUInteger)columns in:(UIStackView *)parent {
    for (NSUInteger i=0;i<items.count;i+=columns) {
        UIStackView *row=[UIStackView new]; row.axis=UILayoutConstraintAxisHorizontal; row.spacing=6; row.distribution=UIStackViewDistributionFillEqually; row.alignment=UIStackViewAlignmentTop;
        for (NSUInteger j=0;j<columns;j++) {
            if (i+j<items.count) { NSArray *item=items[i+j]; [row addArrangedSubview:[self metric:item[0] key:item[1] icon:item[2]]]; }
            else { [row addArrangedSubview:[UIView new]]; }
        }
        [parent addArrangedSubview:row];
    }
}
- (UIButton *)action:(NSString *)title selector:(SEL)selector {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem]; button.backgroundColor=BMSBlue(); button.layer.cornerRadius=10;
    [button setTitle:title forState:UIControlStateNormal]; [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; button.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [button.heightAnchor constraintEqualToConstant:44].active=YES; [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside]; return button;
}
@end
