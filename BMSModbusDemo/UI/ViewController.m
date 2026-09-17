#import "ViewController.h"
#import "../Client/BMSClient.h"
#import "../Transport/BMSMockTransport.h"
#import "../Transport/BMSBLETransport.h"
#import "../Transport/BMSBLEConfiguration.h"

@interface ViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *connectionButton;
@property (nonatomic, strong) UILabel *deviceListTitle;
@property (nonatomic, strong) UIStackView *deviceListStack;
@property (nonatomic, copy) NSArray<BMSBLEDevice *> *nearbyDevices;
@property (nonatomic, strong) UILabel *voltageLabel;
@property (nonatomic, strong) UILabel *currentLabel;
@property (nonatomic, strong) UILabel *socLabel;
@property (nonatomic, strong) UILabel *realtimeTitle;
@property (nonatomic, strong) UILabel *mosLabel;
@property (nonatomic, strong) UILabel *temperatureLabel;
@property (nonatomic, strong) UILabel *alarmLabel;
@property (nonatomic, strong) UIButton *readDataButton;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) NSURL *logFileURL;
@property (nonatomic, strong) NSDateFormatter *logDateFormatter;
@property (nonatomic, strong) BMSClient *client;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, strong) UISwitch *autoRefreshSwitch;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UILabel *informationLabel;
@property (nonatomic, strong) UILabel *parameterLabel;
@property (nonatomic, strong) UILabel *historyLabel;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"BMS 数据监控";
    self.view.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1];
    [self buildUI];
    [self preparePersistentLog];
    [self rebuildClient];
}

- (void)dealloc { [self.refreshTimer invalidate]; }

- (void)buildUI {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];
    self.stackView = [[UIStackView alloc] init];
    self.stackView.axis = UILayoutConstraintAxisVertical;
    self.stackView.spacing = 14;
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.stackView];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.stackView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:16],
        [self.stackView.leadingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.leadingAnchor constant:16],
        [self.stackView.trailingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.trailingAnchor constant:-16],
        [self.stackView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-20]
    ]];

    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"模拟数据", @"真实蓝牙"]];
    self.modeControl.selectedSegmentIndex = 0;
    [self.modeControl addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];
    [self.stackView addArrangedSubview:self.modeControl];

    UIView *connectionCard = [self card];
    UIStackView *connectionStack = [self verticalStackIn:connectionCard];
    self.statusLabel = [self label:@"未连接" size:15 weight:UIFontWeightSemibold];
    self.statusLabel.textColor = UIColor.systemOrangeColor;
    [connectionStack addArrangedSubview:self.statusLabel];
    self.connectionButton = [self button:@"连接设备" action:@selector(connectTapped) color:UIColor.systemBlueColor];
    [connectionStack addArrangedSubview:self.connectionButton];
    [self.stackView addArrangedSubview:connectionCard];

    self.deviceListTitle = [self sectionTitle:@"附近设备（点击连接）"];
    self.deviceListTitle.hidden = YES;
    [self.stackView addArrangedSubview:self.deviceListTitle];
    self.deviceListStack = [[UIStackView alloc] init];
    self.deviceListStack.axis = UILayoutConstraintAxisVertical;
    self.deviceListStack.spacing = 8;
    self.deviceListStack.hidden = YES;
    [self.stackView addArrangedSubview:self.deviceListStack];

    self.realtimeTitle = [self sectionTitle:@"实时状态（模拟模式每10秒刷新）"];
    [self.stackView addArrangedSubview:self.realtimeTitle];
    UIStackView *metrics = [[UIStackView alloc] init];
    metrics.axis = UILayoutConstraintAxisHorizontal;
    metrics.distribution = UIStackViewDistributionFillEqually;
    metrics.spacing = 8;
    self.voltageLabel = [self metricCardWithTitle:@"总电压" initial:@"-- V" stack:metrics];
    self.currentLabel = [self metricCardWithTitle:@"总电流" initial:@"-- A" stack:metrics];
    self.socLabel = [self metricCardWithTitle:@"SOC" initial:@"-- %" stack:metrics];
    [self.stackView addArrangedSubview:metrics];

    UIStackView *actions = [[UIStackView alloc] init];
    actions.axis = UILayoutConstraintAxisHorizontal;
    actions.distribution = UIStackViewDistributionFillEqually;
    actions.spacing = 8;
    self.readDataButton = [self button:@"读取数据" action:@selector(readDataTapped) color:UIColor.systemBlueColor];
    [actions addArrangedSubview:self.readDataButton];
    [actions addArrangedSubview:[self button:@"读取历史" action:@selector(readHistoryTapped) color:UIColor.systemIndigoColor]];
    [self.stackView addArrangedSubview:actions];

    UIView *controlCard = [self card];
    UIStackView *controlStack = [self verticalStackIn:controlCard];
    [controlStack addArrangedSubview:[self sectionTitle:@"设备控制示例"]];
    self.mosLabel = [self label:@"充电 MOS：未知" size:15 weight:UIFontWeightRegular];
    [controlStack addArrangedSubview:self.mosLabel];
    self.temperatureLabel = [self label:@"温度：未知" size:15 weight:UIFontWeightRegular];
    [controlStack addArrangedSubview:self.temperatureLabel];
    self.alarmLabel = [self label:@"报警：未知" size:15 weight:UIFontWeightRegular];
    self.alarmLabel.textColor = UIColor.secondaryLabelColor;
    [controlStack addArrangedSubview:self.alarmLabel];
    UIStackView *mosActions = [[UIStackView alloc] init];
    mosActions.axis = UILayoutConstraintAxisHorizontal;
    mosActions.spacing = 8;
    mosActions.distribution = UIStackViewDistributionFillEqually;
    [mosActions addArrangedSubview:[self button:@"开启充电 MOS" action:@selector(openMOSTapped) color:UIColor.systemGreenColor]];
    [mosActions addArrangedSubview:[self button:@"关闭充电 MOS" action:@selector(closeMOSTapped) color:UIColor.systemRedColor]];
    [controlStack addArrangedSubview:mosActions];
    [self.stackView addArrangedSubview:controlCard];

    self.autoRefreshSwitch = [UISwitch new];
    [self.autoRefreshSwitch addTarget:self action:@selector(refreshChanged) forControlEvents:UIControlEventValueChanged];
    [self.stackView addArrangedSubview:[self label:@"自动刷新（10秒；忙碌时跳过，不自动重试）" size:14 weight:UIFontWeightRegular]];
    [self.stackView addArrangedSubview:self.autoRefreshSwitch];
    self.detailLabel = [self label:@"单体、温度、容量：未读取" size:13 weight:UIFontWeightRegular];
    [self.stackView addArrangedSubview:self.detailLabel];
    [self.stackView addArrangedSubview:[self button:@"读取设备信息" action:@selector(readInformationTapped) color:UIColor.systemBlueColor]];
    self.informationLabel = [self label:@"设备信息：未读取" size:13 weight:UIFontWeightRegular];
    [self.stackView addArrangedSubview:self.informationLabel];
    [self.stackView addArrangedSubview:[self button:@"读取常规参数（只读）" action:@selector(readParametersTapped) color:UIColor.systemBlueColor]];
    self.parameterLabel = [self label:@"常规参数：未读取" size:13 weight:UIFontWeightRegular];
    [self.stackView addArrangedSubview:self.parameterLabel];
    self.historyLabel = [self label:@"历史记录：未读取" size:13 weight:UIFontWeightRegular];
    [self.stackView addArrangedSubview:self.historyLabel];

    UIStackView *logHeader = [[UIStackView alloc] init];
    logHeader.axis = UILayoutConstraintAxisHorizontal;
    logHeader.alignment = UIStackViewAlignmentCenter;
    [logHeader addArrangedSubview:[self sectionTitle:@"运行日志"]];
    [logHeader addArrangedSubview:[[UIView alloc] init]];
    [logHeader addArrangedSubview:[self logActionButton:@"分享日志" action:@selector(shareLogTapped)]];
    [logHeader addArrangedSubview:[self logActionButton:@"清空" action:@selector(clearLogTapped)]];
    [self.stackView addArrangedSubview:logHeader];
    self.logView = [[UITextView alloc] init];
    self.logView.editable = NO;
    self.logView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.logView.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1];
    self.logView.textColor = [UIColor colorWithRed:0.50 green:0.95 blue:0.60 alpha:1];
    self.logView.layer.cornerRadius = 10;
    self.logView.text = @"等待操作…";
    [self.logView.heightAnchor constraintEqualToConstant:220].active = YES;
    [self.stackView addArrangedSubview:self.logView];
}

- (void)rebuildClient {
    [self.refreshTimer invalidate];
    self.autoRefreshSwitch.on = NO;
    self.detailLabel.text = @"单体、温度、容量：未读取";
    self.informationLabel.text = @"设备信息：未读取";
    self.parameterLabel.text = @"常规参数：未读取";
    self.historyLabel.text = @"历史记录：未读取";
    self.client.transport.stateHandler = nil;
    [self.client.transport disconnect];
    id<BMSByteTransport> transport = self.modeControl.selectedSegmentIndex == 0
        ? (id<BMSByteTransport>)[[BMSMockTransport alloc] init]
        : (id<BMSByteTransport>)[[BMSBLETransport alloc] initWithConfiguration:BMSBLEConfiguration.demoConfiguration];
    BOOL realBluetooth = self.modeControl.selectedSegmentIndex == 1;
    self.client = [[BMSClient alloc] initWithTransport:transport];
    // 实机保留5秒响应超时；诊断模式不会自动发送或自动重试。
    if (realBluetooth) { self.client.responseTimeout = 5.0; }
    self.nearbyDevices = @[];
    [self updateDeviceList:@[]];
    self.deviceListTitle.hidden = !realBluetooth;
    self.deviceListStack.hidden = !realBluetooth;
    [self.connectionButton setTitle:realBluetooth ? @"重新扫描" : @"连接设备" forState:UIControlStateNormal];
    [self.readDataButton setTitle:@"读取实时数据" forState:UIControlStateNormal];
    self.realtimeTitle.text = @"实时状态（可开启自动刷新）";
    // 切换模式时清除上一台设备/模拟数据，避免将旧值误认为实机响应。
    self.voltageLabel.text = @"-- V";
    self.currentLabel.text = @"-- A";
    self.socLabel.text = @"-- %";
    self.mosLabel.text = @"MOS：未读取";
    self.temperatureLabel.text = @"温度：未读取";
    self.alarmLabel.text = @"报警：未读取";
    self.alarmLabel.textColor = UIColor.secondaryLabelColor;
    __weak typeof(self) weakSelf = self;
    transport.stateHandler = ^(BOOL connected, NSString *message) {
        weakSelf.statusLabel.text = message;
        weakSelf.statusLabel.textColor = connected ? UIColor.systemGreenColor : UIColor.systemOrangeColor;
        [weakSelf appendLog:[NSString stringWithFormat:@"BLE状态：%@", message]];
        [weakSelf.connectionButton setTitle:connected ? @"断开设备" : (weakSelf.modeControl.selectedSegmentIndex == 1 ? @"重新扫描" : @"连接设备") forState:UIControlStateNormal];
        if (!connected) {
            weakSelf.autoRefreshSwitch.on = NO;
            [weakSelf.refreshTimer invalidate];
            weakSelf.refreshTimer = nil;
        }
        if (connected) {
            [weakSelf.refreshTimer invalidate];
            weakSelf.refreshTimer = nil;
            if (weakSelf.modeControl.selectedSegmentIndex == 0) {
                [weakSelf readDataTapped];
                weakSelf.autoRefreshSwitch.on = YES;
                [weakSelf refreshChanged];
            } else {
                [weakSelf appendLog:@"抓包适配版：点击“读取实时数据”发送01 04 00 60 00 56 70 2A；0x04响应按两字节长度组包，预期178字节"];
            }
        }
    };
    if ([transport isKindOfClass:BMSBLETransport.class]) {
        BMSBLETransport *bleTransport = (BMSBLETransport *)transport;
        bleTransport.devicesHandler = ^(NSArray<BMSBLEDevice *> *devices) {
            [weakSelf updateDeviceList:devices];
        };
    }
    self.client.logHandler = ^(NSString *line) { [weakSelf appendLog:line]; };
    self.statusLabel.text = self.modeControl.selectedSegmentIndex == 0 ? @"模拟模式就绪" : @"仅搜索 YT/QM 设备…";
}

- (void)modeChanged {
    [self rebuildClient];
    // 选择真实蓝牙后立即开始扫描；若系统蓝牙尚未就绪，Transport 会在状态变为 PoweredOn 后继续。
    if (self.modeControl.selectedSegmentIndex == 1) { [self.client.transport connect]; }
}
- (void)connectTapped { self.client.transport.isConnected ? [self.client.transport disconnect] : [self.client.transport connect]; }

- (void)updateDeviceList:(NSArray<BMSBLEDevice *> *)devices {
    self.nearbyDevices = devices;
    for (UIView *view in self.deviceListStack.arrangedSubviews.copy) {
        [self.deviceListStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    if (devices.count == 0) {
        UILabel *empty = [self label:@"正在搜索，请确保设备已开机并允许蓝牙权限…" size:13 weight:UIFontWeightRegular];
        empty.textColor = UIColor.secondaryLabelColor;
        [self.deviceListStack addArrangedSubview:empty];
        return;
    }
    for (BMSBLEDevice *device in devices) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        button.titleLabel.numberOfLines = 2;
        button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        button.backgroundColor = UIColor.whiteColor;
        button.layer.cornerRadius = 10;
        button.layer.borderWidth = 1;
        button.layer.borderColor = [UIColor colorWithWhite:0.88 alpha:1].CGColor;
        UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
        configuration.contentInsets = NSDirectionalEdgeInsetsMake(9, 12, 9, 12);
        button.configuration = configuration;
        button.accessibilityIdentifier = device.identifier.UUIDString;
        NSString *title = [NSString stringWithFormat:@"%@    %@ dBm\n%@", device.name, device.RSSI, device.identifier.UUIDString];
        [button setTitle:title forState:UIControlStateNormal];
        [button.heightAnchor constraintGreaterThanOrEqualToConstant:58].active = YES;
        [button addTarget:self action:@selector(deviceTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.deviceListStack addArrangedSubview:button];
    }
}

- (void)deviceTapped:(UIButton *)sender {
    if (![self.client.transport isKindOfClass:BMSBLETransport.class]) { return; }
    BMSBLEDevice *selected;
    for (BMSBLEDevice *device in self.nearbyDevices) {
        if ([device.identifier.UUIDString isEqualToString:sender.accessibilityIdentifier]) { selected = device; break; }
    }
    if (selected) {
        [self appendLog:[NSString stringWithFormat:@"选择设备：%@，RSSI=%@，identifier=%@", selected.name, selected.RSSI, selected.identifier.UUIDString]];
        if (selected.RSSI.integerValue <= -90) {
            [self appendLog:@"警告：蓝牙信号弱于 -90 dBm，请将手机靠近设备后测试，弱信号可能造成连接超时"];
        }
        [(BMSBLETransport *)self.client.transport connectToDevice:selected];
    }
}

- (void)readDataTapped {
    if (![self requireConnection]) { return; }
    if (self.client.isBusy) { return; }
    BMSClient *requestClient = self.client;
    __weak typeof(self) weakSelf = self;
    if (self.modeControl.selectedSegmentIndex == 1) {
        [self appendLog:@"按旧APP读取：起始0x0060，数量86，等待完整响应及CRC校验"];
    }
    [self.client readRealtimeData:^(BMSRealtimeData *data, NSError *error) {
        if (weakSelf.client != requestClient) { return; }
        if (error) { [weakSelf showError:error]; return; }
        weakSelf.detailLabel.text = data.detailText;
        weakSelf.voltageLabel.text = [NSString stringWithFormat:@"%.1f V", data.totalVoltage];
        weakSelf.currentLabel.text = [NSString stringWithFormat:@"%.1f A", data.totalCurrent];
        weakSelf.socLabel.text = [NSString stringWithFormat:@"%lu %%", (unsigned long)data.displaySOC];
        weakSelf.mosLabel.text = [NSString stringWithFormat:@"MOS：充电%@  放电%@  预充%@",
                                  data.chargeMOSOn ? @"闭合" : @"断开",
                                  data.dischargeMOSOn ? @"闭合" : @"断开",
                                  data.prechargeMOSOn ? @"闭合" : @"断开"];
        weakSelf.temperatureLabel.text = [NSString stringWithFormat:@"温度：MOS %ld℃  环境 %ld℃",
                                          (long)data.MOSTemperature, (long)data.ambientTemperature];
        NSString *faults = data.faultDescriptions.count ? [data.faultDescriptions componentsJoinedByString:@"、"] : @"无";
        weakSelf.alarmLabel.text = [NSString stringWithFormat:@"报警：%@（等级 %lu，位图 0x%04X）",
                                    faults, (unsigned long)data.faultLevel, data.faultBits];
        weakSelf.alarmLabel.textColor = data.faultLevel == 0 ? UIColor.systemGreenColor : UIColor.systemRedColor;
        [weakSelf appendLog:[NSString stringWithFormat:@"实时数据：%.1fV，%.1fA，SOC %lu%%，故障位图 0x%04X",
                             data.totalVoltage, data.totalCurrent, (unsigned long)data.displaySOC, data.faultBits]];
    }];
}

- (void)readHistoryTapped {
    if (![self requireConnection]) { return; }
    // 弹窗期间停止轮询，避免用户确认时正好存在另一条请求。
    self.autoRefreshSwitch.on = NO;
    [self refreshChanged];
    BMSClient *requestClient = self.client;
    __weak typeof(self) weakSelf = self;
    [self.client readHistoryCount:^(NSNumber *count, NSError *error) {
        if (weakSelf.client != requestClient) { return; }
        if (error) { [weakSelf showError:error]; return; }
        [weakSelf appendLog:[NSString stringWithFormat:@"历史记录总数：%@", count]];
        weakSelf.historyLabel.text = [NSString stringWithFormat:@"历史记录共 %@ 条", count];
        if (count.unsignedIntegerValue == 0) { return; }
        UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"选择历史记录" message:[NSString stringWithFormat:@"输入索引 0～%lu", (unsigned long)count.unsignedIntegerValue-1] preferredStyle:UIAlertControllerStyleAlert];
        [picker addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = @"0"; field.keyboardType = UIKeyboardTypeNumberPad; }];
        [picker addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [picker addAction:[UIAlertAction actionWithTitle:@"读取" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            if (weakSelf.client != requestClient) { return; }
            NSInteger index;
            NSScanner *scanner = [NSScanner scannerWithString:picker.textFields.firstObject.text ?: @""];
            if (![scanner scanInteger:&index] || !scanner.isAtEnd || index<0 || index>=count.integerValue) { [weakSelf appendLog:@"历史索引超出范围"]; return; }
        [requestClient readHistoryRecordAtIndex:(uint16_t)index completion:^(NSDictionary *record, NSError *recordError) {
            if (weakSelf.client != requestClient) { return; }
            if (recordError) { [weakSelf showError:recordError]; return; }
            weakSelf.historyLabel.text = [NSString stringWithFormat:@"历史 #%@ · %@\n事件 %@ · %@ V · %@ A · SOC %@%%\n单体电压(V)：%@\n探针温度(℃)：%@\nMOS温度 %@℃ · 环境 %@℃\n报警位图 %@ · MOS状态 %@", record[@"index"], record[@"time"], record[@"eventType"], record[@"totalVoltage"], record[@"totalCurrent"], record[@"soc"], [record[@"cellVoltages"] componentsJoinedByString:@", "], [record[@"temperatures"] componentsJoinedByString:@", "], record[@"mosTemperature"], record[@"ambientTemperature"], record[@"alarms"], record[@"mosStates"]];
            [weakSelf appendLog:[NSString stringWithFormat:@"首条历史：%@  %.1fV  %.1fA  SOC %@%%", record[@"time"], [record[@"totalVoltage"] doubleValue], [record[@"totalCurrent"] doubleValue], record[@"soc"]]];
        }];
        }]];
        [weakSelf presentViewController:picker animated:YES completion:nil];
    }];
}

- (void)refreshChanged {
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
    if (!self.autoRefreshSwitch.on) { return; }
    if (![self requireConnection]) { self.autoRefreshSwitch.on = NO; return; }
    __weak typeof(self) weakSelf = self;
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:10 repeats:YES block:^(NSTimer *timer) {
        if (!weakSelf.client.isBusy) { [weakSelf readDataTapped]; }
    }];
}

- (void)readInformationTapped {
    if (![self requireConnection]) { return; }
    BMSClient *client = self.client;
    __weak typeof(self) weakSelf = self;
    [client readDeviceInformation:^(NSDictionary *info, NSError *error) {
        if (weakSelf.client != client) { return; }
        if (error) { [weakSelf showError:error]; return; }
        weakSelf.informationLabel.text = [NSString stringWithFormat:@"软件：%@\n硬件：%@\n编号：%@\n设备时间：%@\n零电流原始值：%@ · 自检原始值：%@", info[@"software"], info[@"hardware"], info[@"identifier"], info[@"time"], info[@"zeroCurrent"], info[@"selfTest"]];
    }];
}

- (void)readParametersTapped {
    if (![self requireConnection]) { return; }
    BMSClient *client = self.client;
    __weak typeof(self) weakSelf = self;
    [client readCommonParameters:^(NSArray *items, NSError *error) {
        if (weakSelf.client != client) { return; }
        if (error) { [weakSelf showError:error]; return; }
        NSMutableArray *lines = NSMutableArray.array;
        for (NSDictionary *item in items) {
            [lines addObject:[NSString stringWithFormat:@"D%@ %@：%@ %@（原始%@）%@", item[@"address"], item[@"name"], item[@"value"], item[@"unit"], item[@"raw"], [item[@"valid"] boolValue] ? @"" : @" [超出文档范围]"]];
        }
        weakSelf.parameterLabel.text = [lines componentsJoinedByString:@"\n"];
    }];
}

- (void)openMOSTapped { [self setMOS:YES]; }
- (void)closeMOSTapped { [self setMOS:NO]; }
- (void)setMOS:(BOOL)on {
    if (![self requireConnection]) { return; }
    if (self.modeControl.selectedSegmentIndex == 1) {
        // 表格只定义了 D80/0x0050 的“充电MOS控制”触发位，没有定义开启/关闭分别写什么值。
        // 为避免误动作，实机模式不发送未经厂家确认的控制命令。
        [self appendLog:@"实机MOS控制已保护：请厂家确认0x0050位5的开启/关闭写值后再启用"];
        return;
    }
    __weak typeof(self) weakSelf = self;
    // 演示寄存器地址为 0，实际地址需用设备寄存器表替换。
    [self.client setRunningStatusAt:0 on:on completion:^(id result, NSError *error) {
        if (error) { [weakSelf showError:error]; return; }
        weakSelf.mosLabel.text = [NSString stringWithFormat:@"充电 MOS：%@", on ? @"闭合" : @"断开"];
    }];
}

- (BOOL)requireConnection {
    if (self.client.transport.isConnected) { return YES; }
    [self appendLog:@"请先连接设备"];
    return NO;
}

- (void)showError:(NSError *)error { [self appendLog:[NSString stringWithFormat:@"错误：%@", error.localizedDescription]]; }
- (void)appendLog:(NSString *)line {
    NSString *time = [self.logDateFormatter stringFromDate:NSDate.date] ?: [NSDateFormatter localizedStringFromDate:NSDate.date dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle];
    NSString *record = [NSString stringWithFormat:@"[%@] %@\n", time, line];
    self.logView.text = [self.logView.text stringByAppendingString:record];
    // 界面只保留最近约3万字符，完整报文仍写入日志文件，避免长期轮询内存持续上涨。
    if (self.logView.text.length > 30000) { self.logView.text = [self.logView.text substringFromIndex:self.logView.text.length-30000]; }
    [self.logView scrollRangeToVisible:NSMakeRange(self.logView.text.length, 0)];
    if (!self.logFileURL) { return; }
    NSData *data = [record dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingToURL:self.logFileURL error:nil];
    if (handle) {
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    }
}

- (void)preparePersistentLog {
    self.logDateFormatter = [[NSDateFormatter alloc] init];
    self.logDateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    self.logDateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *directory = [documents URLByAppendingPathComponent:@"BMSLogs" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSDateFormatter *nameFormatter = [[NSDateFormatter alloc] init];
    nameFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    nameFormatter.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *fileName = [NSString stringWithFormat:@"BMS-%@.log", [nameFormatter stringFromDate:NSDate.date]];
    self.logFileURL = [directory URLByAppendingPathComponent:fileName];
    [NSFileManager.defaultManager createFileAtPath:self.logFileURL.path contents:NSData.data attributes:nil];
    self.logView.text = @"";
    [self appendLog:@"========== BMS 调试会话开始 =========="];
    UIDevice *device = UIDevice.currentDevice;
    [self appendLog:[NSString stringWithFormat:@"设备：%@，系统：%@ %@", device.model, device.systemName, device.systemVersion]];
    [self appendLog:@"Service=00010203-0405-0607-0809-0A0B0C0DFFE0，Write=...FFE2，Notify=...FFE1"];
    [self removeOldLogFilesInDirectory:directory keepingNewest:10];
}

- (void)removeOldLogFilesInDirectory:(NSURL *)directory keepingNewest:(NSUInteger)limit {
    NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    files = [files sortedArrayUsingComparator:^NSComparisonResult(NSURL *left, NSURL *right) {
        NSDate *leftDate; NSDate *rightDate;
        [left getResourceValue:&leftDate forKey:NSURLContentModificationDateKey error:nil];
        [right getResourceValue:&rightDate forKey:NSURLContentModificationDateKey error:nil];
        return [rightDate ?: NSDate.distantPast compare:leftDate ?: NSDate.distantPast];
    }];
    for (NSUInteger index = limit; index < files.count; index++) {
        [NSFileManager.defaultManager removeItemAtURL:files[index] error:nil];
    }
}

- (void)shareLogTapped {
    if (!self.logFileURL) { [self appendLog:@"日志文件创建失败，无法分享"]; return; }
    [self appendLog:@"准备分享当前日志"];
    UIActivityViewController *controller = [[UIActivityViewController alloc] initWithActivityItems:@[self.logFileURL] applicationActivities:nil];
    controller.popoverPresentationController.sourceView = self.view;
    controller.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)clearLogTapped {
    [NSFileManager.defaultManager createFileAtPath:self.logFileURL.path contents:NSData.data attributes:nil];
    self.logView.text = @"";
    [self appendLog:@"日志已清空，开始新的诊断记录"];
}

- (UIView *)card {
    UIView *view = [[UIView alloc] init]; view.backgroundColor = UIColor.whiteColor; view.layer.cornerRadius = 12;
    view.layer.shadowColor = UIColor.blackColor.CGColor; view.layer.shadowOpacity = 0.06; view.layer.shadowRadius = 8; view.layer.shadowOffset = CGSizeMake(0, 2);
    return view;
}
- (UIStackView *)verticalStackIn:(UIView *)container {
    UIStackView *stack = [[UIStackView alloc] init]; stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 10; stack.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:stack]; [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:container.topAnchor constant:14], [stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:14], [stack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-14], [stack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-14]]]; return stack;
}
- (UILabel *)sectionTitle:(NSString *)text { return [self label:text size:17 weight:UIFontWeightSemibold]; }
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight { UILabel *label = [[UILabel alloc] init]; label.text = text; label.font = [UIFont systemFontOfSize:size weight:weight]; label.numberOfLines = 0; return label; }
- (UIButton *)button:(NSString *)title action:(SEL)action color:(UIColor *)color {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; [button setTitle:title forState:UIControlStateNormal]; [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; button.backgroundColor = color; button.layer.cornerRadius = 8; button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold]; [button.heightAnchor constraintEqualToConstant:44].active = YES; [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; return button;
}
- (UIButton *)logActionButton:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:64].active = YES;
    return button;
}
- (UILabel *)metricCardWithTitle:(NSString *)title initial:(NSString *)initial stack:(UIStackView *)stack {
    UIView *card = [self card]; UIStackView *inner = [self verticalStackIn:card]; UILabel *name = [self label:title size:12 weight:UIFontWeightRegular]; name.textColor = UIColor.secondaryLabelColor; UILabel *value = [self label:initial size:19 weight:UIFontWeightBold]; value.textColor = UIColor.systemBlueColor; value.textAlignment = NSTextAlignmentCenter; name.textAlignment = NSTextAlignmentCenter; [inner addArrangedSubview:name]; [inner addArrangedSubview:value]; [stack addArrangedSubview:card]; return value;
}

@end
