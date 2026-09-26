#import "ViewController.h"
#import "BMSProductViewController.h"
#import "BMSMonitorViewController.h"
#import "BMSFunctionsViewController.h"
#import "../Client/BMSClient.h"
#import "../Transport/BMSBLETransport.h"
#import "../Transport/BMSBLEConfiguration.h"

@interface BMSNavigationController : UINavigationController
@end
@implementation BMSNavigationController
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
@end

@interface ViewController ()
@property (nonatomic, copy) NSString *selectedDeviceName;
@property (nonatomic, strong) BMSProductViewController *productController;
@property (nonatomic, strong) BMSMonitorViewController *monitorController;
@property (nonatomic, strong) UIViewController *diagnosticsController;
@property (nonatomic, strong) BMSFunctionsViewController *functionsController;
@property (nonatomic, strong) UIStackView *historyStack;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *connectionButton;
@property (nonatomic, strong) UILabel *deviceListTitle;
@property (nonatomic, strong) UIStackView *deviceListStack;
@property (nonatomic, copy) NSArray<BMSBLEDevice *> *nearbyDevices;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) NSURL *logFileURL;
@property (nonatomic, strong) NSDateFormatter *logDateFormatter;
@property (nonatomic, strong) BMSClient *client;
@property (nonatomic, strong) UILabel *historyLabel;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"BMS 数据监控";
    self.view.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1];
    [self buildTabs];
    [self buildUI];
    [self preparePersistentLog];
    [self rebuildClient];
}


- (UIStackView *)pageStack:(UIViewController *)controller {
    controller.view.backgroundColor = [UIColor colorWithWhite:0.97 alpha:1];
    UIScrollView *scroll = [UIScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [controller.view addSubview:scroll];
    UIStackView *stack = [UIStackView new]; stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 14; stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.topAnchor], [scroll.bottomAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:controller.view.leadingAnchor], [scroll.trailingAnchor constraintEqualToAnchor:controller.view.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16], [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:16], [stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-16]
    ]]; return stack;
}

- (void)buildTabs {
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    self.productController = [BMSProductViewController new];
    self.monitorController = [BMSMonitorViewController new];
    self.diagnosticsController = [UIViewController new]; self.diagnosticsController.title = @"设备与日志";
    self.functionsController = [BMSFunctionsViewController new];
    UIViewController *firmware = [UIViewController new];
    UIViewController *history = [UIViewController new];
    NSArray *pages = @[self.productController,self.monitorController,self.functionsController,firmware,history];
    NSArray *titles = @[@"产品信息",@"数据监控",@"设备功能",@"固件升级",@"历史数据"];
    NSArray *icons = @[@"shippingbox.fill",@"chart.bar.fill",@"internaldrive.fill",@"arrow.up.doc.fill",@"clock.arrow.circlepath"];
    NSMutableArray *controllers = NSMutableArray.array;
    UIColor *blue = [UIColor colorWithRed:0.035 green:0.40 blue:0.93 alpha:1];
    for (NSUInteger i=0; i<pages.count; i++) {
        UIViewController *page = pages[i]; page.title = titles[i];
        UINavigationController *navigation = [[BMSNavigationController alloc] initWithRootViewController:page];
        navigation.tabBarItem = [[UITabBarItem alloc] initWithTitle:titles[i] image:[UIImage systemImageNamed:icons[i]] tag:i];
        UINavigationBarAppearance *appearance = [UINavigationBarAppearance new]; [appearance configureWithOpaqueBackground]; appearance.backgroundColor = blue;
        appearance.titleTextAttributes = @{NSForegroundColorAttributeName:UIColor.whiteColor, NSFontAttributeName:[UIFont systemFontOfSize:17 weight:UIFontWeightMedium]};
        navigation.navigationBar.standardAppearance = appearance; navigation.navigationBar.scrollEdgeAppearance = appearance; navigation.navigationBar.tintColor = UIColor.whiteColor;
        [controllers addObject:navigation];
    }
    self.viewControllers = controllers;
    UITabBarAppearance *tabs = [UITabBarAppearance new]; [tabs configureWithOpaqueBackground]; tabs.backgroundColor = [UIColor colorWithRed:0.985 green:0.977 blue:0.99 alpha:1];
    self.tabBar.standardAppearance = tabs; self.tabBar.scrollEdgeAppearance = tabs; self.tabBar.tintColor = blue;
    self.tabBar.unselectedItemTintColor = UIColor.systemGrayColor;
    self.historyStack = [self pageStack:history];
    UIStackView *firmwareStack = [self pageStack:firmware];
    [firmwareStack addArrangedSubview:[self sectionTitle:@"固件升级"]];
    [firmwareStack addArrangedSubview:[self label:@"固件升级功能待接入" size:17 weight:UIFontWeightMedium]];
    [firmwareStack addArrangedSubview:[self label:@"当前版本暂不支持选择固件和执行升级。" size:14 weight:UIFontWeightRegular]];
    __weak typeof(self) weakSelf = self;
    void (^openDiagnostics)(void) = ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { return; }
        BOOL switchingTab = strongSelf.selectedIndex != 1;
        UINavigationController *navigation = (UINavigationController *)strongSelf.viewControllers[1];
        if (navigation.topViewController != strongSelf.diagnosticsController) {
            [navigation setViewControllers:@[strongSelf.monitorController, strongSelf.diagnosticsController] animated:!switchingTab];
        }
        if (switchingTab) { strongSelf.selectedIndex = 1; }
    };
    self.productController.connectionAction = ^{ openDiagnostics(); if (!weakSelf.client.transport.isConnected) { [weakSelf.client.transport connect]; } };
    self.monitorController.connectionAction = openDiagnostics;
    self.monitorController.logAction = openDiagnostics;
    self.functionsController.connectionAction = openDiagnostics;
}

- (void)buildUI {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.diagnosticsController.view addSubview:self.scrollView];
    self.stackView = [[UIStackView alloc] init];
    self.stackView.axis = UILayoutConstraintAxisVertical;
    self.stackView.spacing = 14;
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.stackView];
    UILayoutGuide *safe = self.diagnosticsController.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [self.stackView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:16],
        [self.stackView.leadingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.leadingAnchor constant:16],
        [self.stackView.trailingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.trailingAnchor constant:-16],
        [self.stackView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-20]
    ]];

    [self.stackView addArrangedSubview:[self label:@"真实蓝牙 · 选择下方电池设备" size:15 weight:UIFontWeightMedium]];

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

    [self.historyStack addArrangedSubview:[self button:@"读取历史" action:@selector(readHistoryTapped) color:UIColor.systemIndigoColor]];

    self.historyLabel = [self label:@"历史记录：未读取" size:13 weight:UIFontWeightRegular];
    [self.historyStack addArrangedSubview:self.historyLabel];

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
    self.historyLabel.text = @"历史记录：未读取";
    self.client.transport.stateHandler = nil;
    [self.client.transport disconnect];
    id<BMSByteTransport> transport = [[BMSBLETransport alloc] initWithConfiguration:BMSBLEConfiguration.demoConfiguration];
    self.client = [[BMSClient alloc] initWithTransport:transport];
    self.selectedDeviceName = nil;
    self.productController.client = self.client;
    self.monitorController.client = self.client;
    self.functionsController.client = self.client;
    [self.productController resetDevice];
    self.client.responseTimeout = 5.0;
    self.nearbyDevices = @[];
    [self updateDeviceList:@[]];
    self.deviceListTitle.hidden = NO;
    self.deviceListStack.hidden = NO;
    [self.connectionButton setTitle:@"扫描设备" forState:UIControlStateNormal];
    __weak typeof(self) weakSelf = self;
    transport.stateHandler = ^(BOOL connected, NSString *message) {
        if (connected) { weakSelf.productController.deviceName = weakSelf.selectedDeviceName; }
        [weakSelf.productController connectionChanged:connected];
        [weakSelf.monitorController connectionChanged:connected message:message];
        [weakSelf.functionsController connectionChanged:connected message:message];
        weakSelf.deviceListTitle.hidden = connected; weakSelf.deviceListStack.hidden = connected;
        weakSelf.statusLabel.text = message;
        weakSelf.statusLabel.textColor = connected ? UIColor.systemGreenColor : UIColor.systemOrangeColor;
        [weakSelf appendLog:[NSString stringWithFormat:@"BLE状态：%@", message]];
        [weakSelf.connectionButton setTitle:connected ? @"断开设备" : @"扫描设备" forState:UIControlStateNormal];
        if (!connected) {
            [weakSelf.client cancelPendingRequest];
            [weakSelf clearDeviceReadings];
        }
        if (connected) {
            [weakSelf appendLog:@"已连接真实设备，自动读取产品信息及电池参数"];

        }
    };
    if ([transport isKindOfClass:BMSBLETransport.class]) {
        BMSBLETransport *bleTransport = (BMSBLETransport *)transport;
        bleTransport.devicesHandler = ^(NSArray<BMSBLEDevice *> *devices) {
            [weakSelf updateDeviceList:devices];
        };
    }
    self.client.logHandler = ^(NSString *line) { [weakSelf appendLog:line]; };
    self.statusLabel.text = @"请扫描并连接真实电池设备";
}

- (void)clearDeviceReadings {
    self.historyLabel.text = @"历史记录：未读取";
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
        if (self.client.transport.isConnected) {
            [self showError:[NSError errorWithDomain:@"BMS.Connection" code:1 userInfo:@{NSLocalizedDescriptionKey:@"请先断开当前设备，再连接另一块电池"}]];
            return;
        }
        [self.productController resetDevice];
        self.selectedDeviceName = selected.name;
        self.productController.deviceName = selected.name;
        [self appendLog:[NSString stringWithFormat:@"选择设备：%@，RSSI=%@，identifier=%@", selected.name, selected.RSSI, selected.identifier.UUIDString]];
        if (selected.RSSI.integerValue <= -90) {
            [self appendLog:@"警告：蓝牙信号弱于 -90 dBm，请将手机靠近设备后测试，弱信号可能造成连接超时"];
        }
        [(BMSBLETransport *)self.client.transport connectToDevice:selected];
    }
}

- (void)readHistoryTapped {
    if (![self requireConnection]) { return; }
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

- (BOOL)requireConnection {
    if (self.client.transport.isConnected) { return YES; }
    [self showError:[NSError errorWithDomain:@"BMS.Connection" code:1 userInfo:@{NSLocalizedDescriptionKey:@"请先在数据监控页面连接真实设备"}]];
    return NO;
}

- (void)showError:(NSError *)error {
    [self appendLog:[NSString stringWithFormat:@"错误：%@", error.localizedDescription]];
    if (self.presentedViewController) { return; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"读取提示" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
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
