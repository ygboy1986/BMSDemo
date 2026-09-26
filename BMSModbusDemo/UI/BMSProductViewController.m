#import "BMSProductViewController.h"
#import "BMSBatteryProfile.h"
#import "../Client/BMSClient.h"

static UIColor *BMSBlue(void) { return [UIColor colorWithRed:0.035 green:0.40 blue:0.93 alpha:1]; }
static UIColor *BMSBackground(void) { return [UIColor colorWithRed:0.985 green:0.977 blue:0.99 alpha:1]; }
static UILabel *BMSText(NSString *text, CGFloat size, UIColor *color) {
    UILabel *label = [UILabel new]; label.text = text; label.font = [UIFont systemFontOfSize:size];
    label.textColor = color; label.numberOfLines = 0; return label;
}
static void BMSMessage(UIViewController *controller, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

@interface BMSRibbon : UIView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIColor *color;
@end
@implementation BMSRibbon
- (void)drawRect:(CGRect)rect {
    UIBezierPath *path = [UIBezierPath bezierPath]; [path moveToPoint:CGPointZero];
    [path addLineToPoint:CGPointMake(rect.size.width, 0)]; [path addLineToPoint:CGPointMake(rect.size.width, rect.size.height)]; [path closePath];
    [self.color setFill]; [path fill];
    CGContextRef context = UIGraphicsGetCurrentContext(); CGContextSaveGState(context);
    CGContextTranslateCTM(context, rect.size.width*0.65, rect.size.height*0.33); CGContextRotateCTM(context, M_PI_4);
    NSDictionary *attributes = @{NSFontAttributeName:[UIFont systemFontOfSize:11], NSForegroundColorAttributeName:UIColor.whiteColor};
    CGSize size = [self.text sizeWithAttributes:attributes];
    [self.text drawAtPoint:CGPointMake(-size.width/2, -size.height/2) withAttributes:attributes]; CGContextRestoreGState(context);
}
@end

@interface BMSProductViewController ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, UILabel *> *labels;
@property (nonatomic, strong) NSDate *loginDate;
@property (nonatomic, strong) NSTimer *uptimeTimer;
@property (nonatomic, strong) NSDictionary *deviceInfo;
@property (nonatomic, strong) NSArray<NSDictionary *> *deviceParameters;
@property (nonatomic) NSUInteger sessionGeneration;
@property (nonatomic, strong) UILabel *sourceLabel;
@property (nonatomic, copy) NSString *readStatus;
@property (nonatomic) BOOL reading;
@property (nonatomic, strong) NSDate *lastReadDate;
- (void)render;
- (void)readProduct:(void (^)(NSError *error))completion;
@end

@interface BMSParametersController : UIViewController <UIPickerViewDataSource, UIPickerViewDelegate>
@property (nonatomic, weak) BMSProductViewController *product;
@property (nonatomic, strong) NSMutableArray<UITextField *> *fields;
@property (nonatomic, strong) UIButton *typeButton;
@property (nonatomic, strong) UILabel *notice;
@property (nonatomic, strong) UIButton *readButton;
@property (nonatomic, strong) UIButton *applyButton;
@property (nonatomic, strong) UIPickerView *typePicker;
@property (nonatomic, strong) UIViewController *typeSheet;
@property (nonatomic) NSInteger selectedType;
@property (nonatomic) NSUInteger selectionGeneration;
@property (nonatomic) NSUInteger pickerGeneration;
@property (nonatomic) BOOL writing;
@end

@implementation BMSProductViewController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"产品信息"; self.view.backgroundColor = BMSBackground();
    self.labels = NSMutableDictionary.dictionary;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"] style:UIBarButtonItemStylePlain target:self action:@selector(refreshTapped)];
    self.navigationItem.leftBarButtonItem.accessibilityLabel = @"读取真实产品信息";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"连接" style:UIBarButtonItemStylePlain target:self action:@selector(openConnection)];
    UIScrollView *scroll = [UIScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:scroll];
    UIStackView *stack = [UIStackView new]; stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO; [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor], [scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16], [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-105],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:12], [stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-12]
    ]];
    [stack addArrangedSubview:[self cardWithTitle:@"BMS" color:UIColor.systemRedColor rows:@[@[@"name",@"蓝牙设备名"],@[@"login",@"登入时间"],@[@"uptime",@"使用时间"],@[@"software",@"软件版本"],@[@"hardware",@"硬件版本"],@[@"model",@"产品型号"]]]];
    UIView *battery = [self cardWithTitle:@"电池包" color:[UIColor colorWithRed:0.22 green:0.83 blue:0.68 alpha:1] rows:@[@[@"capacity",@"标定容量"],@[@"type",@"电池类型"],@[@"identifier",@"识别码"]]];
    [battery addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openParameters)]];
    [stack addArrangedSubview:battery];
    UIView *address = [self cardWithTitle:@"地址" color:UIColor.systemOrangeColor rows:@[@[@"address",@"设备地址"],@[@"coordinates",@"坐标"]]];
    [address addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openMap)]];
    [stack addArrangedSubview:address];
    self.sourceLabel = BMSText(@"", 12, UIColor.secondaryLabelColor); self.sourceLabel.textAlignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:self.sourceLabel];
    UIButton *refresh = [UIButton buttonWithType:UIButtonTypeSystem]; [refresh setTitle:@"刷新产品信息" forState:UIControlStateNormal];
    [refresh addTarget:self action:@selector(refreshTapped) forControlEvents:UIControlEventTouchUpInside]; [stack addArrangedSubview:refresh];
    UIButton *settings = [UIButton buttonWithType:UIButtonTypeSystem]; settings.translatesAutoresizingMaskIntoConstraints = NO;
    [settings setImage:[UIImage systemImageNamed:@"slider.vertical.3" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:29 weight:UIImageSymbolWeightRegular]] forState:UIControlStateNormal];
    settings.tintColor = UIColor.whiteColor; settings.backgroundColor = BMSBlue(); settings.layer.cornerRadius = 30;
    settings.layer.shadowOpacity = 0.18; settings.layer.shadowRadius = 7; settings.layer.shadowOffset = CGSizeMake(0,5);
    settings.accessibilityLabel = @"电芯参数"; [settings addTarget:self action:@selector(openParameters) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:settings];
    [NSLayoutConstraint activateConstraints:@[[settings.widthAnchor constraintEqualToConstant:60], [settings.heightAnchor constraintEqualToConstant:60], [settings.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-18], [settings.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-18]]];
    [self render];
}
- (UIView *)cardWithTitle:(NSString *)title color:(UIColor *)color rows:(NSArray *)rows {
    UIView *card = [UIView new]; card.backgroundColor = UIColor.whiteColor; card.layer.cornerRadius = 13;
    card.layer.shadowColor = UIColor.blackColor.CGColor; card.layer.shadowOpacity = 0.13; card.layer.shadowRadius = 9; card.layer.shadowOffset = CGSizeMake(0,8);
    UIStackView *stack = [UIStackView new]; stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 11; stack.translatesAutoresizingMaskIntoConstraints = NO; [card addSubview:stack];
    for (NSArray *row in rows) {
        UIStackView *line = [UIStackView new]; line.axis = UILayoutConstraintAxisHorizontal; line.alignment = UIStackViewAlignmentTop; line.spacing = 8;
        UILabel *dot = BMSText(@"•", 17, color); [dot.widthAnchor constraintEqualToConstant:8].active = YES;
        UILabel *name = BMSText([row[1] stringByAppendingString:@"："], 13, UIColor.systemGrayColor); [name.widthAnchor constraintEqualToConstant:78].active = YES;
        UILabel *value = BMSText(@"—", 13, UIColor.darkGrayColor); [value setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        [line addArrangedSubview:dot]; [line addArrangedSubview:name]; [line addArrangedSubview:value]; [stack addArrangedSubview:line]; self.labels[row[0]] = value;
    }
    [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:19], [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12], [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-30], [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-20]]];
    BMSRibbon *ribbon = [BMSRibbon new]; ribbon.backgroundColor = UIColor.clearColor; ribbon.color = color; ribbon.text = title; ribbon.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:ribbon]; [NSLayoutConstraint activateConstraints:@[[ribbon.topAnchor constraintEqualToAnchor:card.topAnchor], [ribbon.trailingAnchor constraintEqualToAnchor:card.trailingAnchor], [ribbon.widthAnchor constraintEqualToConstant:50], [ribbon.heightAnchor constraintEqualToConstant:50]]];
    return card;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; [self render];
    __weak typeof(self) weakSelf = self;
    self.uptimeTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { [weakSelf updateUptime]; }];
}
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self.uptimeTimer invalidate]; self.uptimeTimer = nil; }
- (void)dealloc { [self.uptimeTimer invalidate]; }
- (void)updateUptime {
    NSDate *date = self.loginDate;
    self.labels[@"uptime"].text = date ? [NSString stringWithFormat:@"%lds", (long)MAX(0, -date.timeIntervalSinceNow)] : @"未连接";
}
- (void)render {
    if (!self.isViewLoaded) { return; }
    BOOL connected = self.client.transport.isConnected;
    NSString *empty = connected ? @"未读取" : @"未连接";
    self.labels[@"name"].text = connected ? (self.deviceName ?: @"名称未提供") : @"未连接";
    NSDateFormatter *formatter = [NSDateFormatter new]; formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    self.labels[@"login"].text = self.loginDate ? [formatter stringFromDate:self.loginDate] : @"未连接";
    for (NSString *key in @[@"software", @"hardware", @"identifier"]) {
        NSString *value = self.deviceInfo[key];
        self.labels[key].text = self.deviceInfo ? (value.length ? value : @"设备未提供") : empty;
    }
    self.labels[@"model"].text = @"协议未提供";
    self.labels[@"capacity"].text = empty;
    self.labels[@"type"].text = empty;
    for (NSDictionary *item in self.deviceParameters) {
        if ([item[@"address"] intValue]==338) {
            self.labels[@"capacity"].text = [item[@"valid"] boolValue] ? [NSString stringWithFormat:@"%.0fmAh", [item[@"value"] doubleValue]*1000] : @"设备容量值无效";
        }
        if ([item[@"address"] intValue]==336) {
            NSInteger type = [item[@"raw"] integerValue];
            self.labels[@"type"].text = type==0 ? @"三元锂" : (type==1 ? @"磷酸铁锂" : [NSString stringWithFormat:@"未知类型 (%ld)", (long)type]);
        }
    }
    self.labels[@"address"].text = @"设备未提供定位信息";
    self.labels[@"coordinates"].text = @"—";
    self.sourceLabel.text = self.readStatus ?: @"请连接真实蓝牙设备，连接后自动读取产品信息";
    [self updateUptime];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"BMSProductDidUpdate" object:self];
}
- (void)resetDevice {
    self.sessionGeneration++; self.deviceInfo = nil; self.deviceParameters = nil; self.loginDate = nil; self.deviceName = nil;
    self.reading = NO; self.lastReadDate = nil; self.readStatus = nil; [self render];
}
- (void)connectionChanged:(BOOL)connected {
    self.sessionGeneration++; self.deviceInfo = nil; self.deviceParameters = nil;
    self.reading = NO; self.lastReadDate = nil; self.readStatus = nil;
    self.loginDate = connected ? NSDate.date : nil;
    if (!connected) { self.deviceName = nil; }
    [self render];
    if (connected) {
        [self readProduct:^(NSError *error) {
            // 自动读取的结果/错误显示在页面中，不弹窗遮挡连接流程。
        }];
    }
}
- (void)openConnection { if (self.connectionAction) { self.connectionAction(); } }
- (void)openParameters {
    BMSParametersController *controller = [BMSParametersController new]; controller.product = self;
    controller.hidesBottomBarWhenPushed = YES; [self.navigationController pushViewController:controller animated:YES];
}
- (void)refreshTapped { [self readProduct:^(NSError *error) { if (error) { BMSMessage(self, error.localizedDescription); } }]; }
- (void)readProduct:(void (^)(NSError *))completion {
    BMSClient *client = self.client;
    if (!client.transport.isConnected || client.isBusy || self.reading) {
        NSString *message = !client.transport.isConnected ? @"请先连接真实蓝牙设备" : @"设备正在读取，请稍后重试";
        completion([NSError errorWithDomain:@"BMS.Product" code:1 userInfo:@{NSLocalizedDescriptionKey:message}]); return;
    }
    NSUInteger generation = self.sessionGeneration;
    self.deviceInfo = nil; self.deviceParameters = nil; self.lastReadDate = nil;
    self.reading = YES; self.readStatus = @"正在读取设备版本、识别码及电池参数…"; [self render];
    NSError *(^changed)(void) = ^NSError *{
        return [NSError errorWithDomain:@"BMS.Product" code:2 userInfo:@{NSLocalizedDescriptionKey:@"连接已改变，请重新读取"}];
    };
    [client readDeviceInformation:^(NSDictionary *info, NSError *infoError) {
        if (client!=self.client || generation!=self.sessionGeneration) { completion(changed()); return; }
        if (!infoError) { self.deviceInfo = info; }
        [self render];
        // 信息区失败仍读取独立的参数区；不以样例填补任何失败字段。
        [client readCommonParameters:^(NSArray *parameters, NSError *parameterError) {
            if (client!=self.client || generation!=self.sessionGeneration) { completion(changed()); return; }
            self.reading = NO;
            if (!parameterError) { self.deviceParameters = parameters; }
            NSMutableArray *errors = NSMutableArray.array;
            if (infoError) { [errors addObject:[@"设备信息：" stringByAppendingString:infoError.localizedDescription]]; }
            if (parameterError) { [errors addObject:[@"电池参数：" stringByAppendingString:parameterError.localizedDescription]]; }
            NSError *error = nil;
            if (errors.count) {
                self.readStatus = [errors componentsJoinedByString:@"\n"];
                error = [NSError errorWithDomain:@"BMS.Product" code:3 userInfo:@{NSLocalizedDescriptionKey:self.readStatus}];
            } else {
                self.lastReadDate = NSDate.date;
                self.readStatus = [NSString stringWithFormat:@"真实设备数据 · 更新于 %@", [NSDateFormatter localizedStringFromDate:self.lastReadDate dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle]];
            }
            [self render]; completion(error);
        }];
    }];
}
- (void)openMap { BMSMessage(self, @"当前协议未返回设备定位，无法显示设备位置"); }

@end

@implementation BMSParametersController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"电芯参数"; self.view.backgroundColor = UIColor.whiteColor;
    self.fields = NSMutableArray.array;
    self.selectedType = -1; self.selectionGeneration = self.product.sessionGeneration;
    UIScrollView *scroll = [UIScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints = NO; scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag; [self.view addSubview:scroll];
    UIStackView *stack = [UIStackView new]; stack.axis = UILayoutConstraintAxisVertical; stack.translatesAutoresizingMaskIntoConstraints = NO; [scroll addSubview:stack];
    self.typeButton = [UIButton buttonWithType:UIButtonTypeSystem]; self.typeButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.typeButton.titleLabel.font = [UIFont systemFontOfSize:16];
    UIButtonConfiguration *typeConfiguration = UIButtonConfiguration.plainButtonConfiguration;
    typeConfiguration.contentInsets = NSDirectionalEdgeInsetsMake(0,16,0,16);
    typeConfiguration.image = [UIImage systemImageNamed:@"chevron.right"];
    typeConfiguration.imagePlacement = NSDirectionalRectEdgeTrailing; typeConfiguration.imagePadding = 12;
    self.typeButton.configuration = typeConfiguration;
    [self.typeButton.heightAnchor constraintEqualToConstant:54].active = YES;
    [self.typeButton addTarget:self action:@selector(selectType) forControlEvents:UIControlEventTouchUpInside]; [stack addArrangedSubview:self.typeButton];
    self.notice = BMSText(@"",12,UIColor.secondaryLabelColor); self.notice.textAlignment = NSTextAlignmentCenter; [stack addArrangedSubview:self.notice];
    NSArray *definitions = BMSBatteryProfile.fields;
    for (NSUInteger i=0; i<definitions.count; i++) {
        NSDictionary *definition = definitions[i]; UIView *row = [UIView new];
        UIStackView *line = [UIStackView new]; line.axis = UILayoutConstraintAxisHorizontal; line.spacing = 10; line.alignment = UIStackViewAlignmentCenter; line.translatesAutoresizingMaskIntoConstraints = NO; [row addSubview:line];
        UILabel *label = BMSText(definition[@"name"],15,UIColor.darkGrayColor); [label setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        UITextField *field = [UITextField new]; field.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightRegular]; field.borderStyle = UITextBorderStyleRoundedRect;
        field.keyboardType = UIKeyboardTypeNumbersAndPunctuation; field.tag = i; field.accessibilityLabel = definition[@"name"];
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        UIToolbar *toolbar = [UIToolbar new]; [toolbar sizeToFit]; toolbar.items = @[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil], [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(endEditing)]]; field.inputAccessoryView = toolbar;
        [field.widthAnchor constraintEqualToConstant:82].active = YES;
        UILabel *unit = BMSText(definition[@"unit"],12,UIColor.systemGrayColor); [unit.widthAnchor constraintEqualToConstant:26].active = YES;
        [line addArrangedSubview:label]; [line addArrangedSubview:field]; [line addArrangedSubview:unit]; [self.fields addObject:field];
        UIView *separator = [UIView new]; separator.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1]; separator.translatesAutoresizingMaskIntoConstraints = NO; [row addSubview:separator];
        [NSLayoutConstraint activateConstraints:@[[line.topAnchor constraintEqualToAnchor:row.topAnchor constant:10], [line.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-10], [line.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16], [line.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16], [row.heightAnchor constraintGreaterThanOrEqualToConstant:46], [separator.bottomAnchor constraintEqualToAnchor:row.bottomAnchor], [separator.leadingAnchor constraintEqualToAnchor:row.leadingAnchor], [separator.trailingAnchor constraintEqualToAnchor:row.trailingAnchor], [separator.heightAnchor constraintEqualToConstant:0.5]]];
        [stack addArrangedSubview:row];
    }
    UIStackView *actions = [UIStackView new]; actions.axis = UILayoutConstraintAxisHorizontal; actions.distribution = UIStackViewDistributionFillEqually; actions.translatesAutoresizingMaskIntoConstraints = NO;
    NSArray *titles = @[@"读取", @"修改"];
    for (NSUInteger i=0; i<titles.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; [button setTitle:titles[i] forState:UIControlStateNormal]; [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; button.backgroundColor = i ? BMSBlue() : [UIColor colorWithRed:0.83 green:0 blue:0.12 alpha:1];
        [button addTarget:self action:i ? @selector(applyType) : @selector(read) forControlEvents:UIControlEventTouchUpInside];
        if (i) { self.applyButton = button; } else { self.readButton = button; }
        [actions addArrangedSubview:button];
    }
    [self.view addSubview:actions];
    [NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor], [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [scroll.bottomAnchor constraintEqualToAnchor:actions.topAnchor], [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor], [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor], [stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor], [stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor], [actions.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [actions.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [actions.heightAnchor constraintEqualToConstant:50], [actions.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor]]];
    [self loadValues];
}
- (void)endEditing { [self.view endEditing:YES]; }
- (NSArray<NSString *> *)typeNames { return @[@"三元锂", @"磷酸铁锂", @"测试"]; }
- (NSInteger)deviceType {
    for (NSDictionary *item in self.product.deviceParameters) {
        if ([item[@"address"] integerValue] == 336) { return [item[@"raw"] integerValue]; }
    }
    return -1;
}
- (void)loadValues {
    if (self.selectionGeneration != self.product.sessionGeneration) {
        self.selectedType = -1; self.writing = NO;
        self.selectionGeneration = self.product.sessionGeneration;
        [self.typeSheet dismissViewControllerAnimated:NO completion:nil];
    }
    NSInteger actualType = [self deviceType];
    BOOL staged = self.selectedType >= 0 && (self.selectedType==2 || self.selectedType != actualType);
    NSString *actualName = actualType==0 || actualType==1 ? self.typeNames[actualType] : (actualType<0 ? @"未读取" : [NSString stringWithFormat:@"未知类型 (%ld)", (long)actualType]);
    NSString *selectedName = self.selectedType>=0 ? self.typeNames[self.selectedType] : actualName;
    [self.typeButton setTitle:staged ? [NSString stringWithFormat:@"待应用类型：%@", selectedName] : [NSString stringWithFormat:@"电池类型：%@", actualName] forState:UIControlStateNormal];
    self.typeButton.enabled = !self.writing;
    self.readButton.enabled = !self.writing && !self.product.reading;
    self.applyButton.enabled = !self.writing && !self.product.reading;
    self.applyButton.alpha = self.applyButton.enabled ? 1 : 0.45;
    if (self.writing) { self.notice.text = @"正在写入电芯类型并回读设备参数…"; }
    else if (staged && self.selectedType==2) { self.notice.text = [NSString stringWithFormat:@"测试类型尚未应用，写入协议待确认。以下为设备当前%@的读取值。", actualName]; }
    else if (staged) { self.notice.text = [NSString stringWithFormat:@"尚未写入%@；以下仍为设备当前%@的读取值。点击“修改”后重新读取。", selectedName, actualName]; }
    else { self.notice.text = self.product.readStatus ?: @"请连接设备并读取参数；选择类型后点击“修改”应用"; }
    self.notice.text = [self.notice.text stringByAppendingString:@"\n— 表示协议未提供或单位换算尚未确认，不代表 0。 "];
    NSArray *definitions = BMSBatteryProfile.fields;
    for (NSUInteger i=0; i<self.fields.count; i++) {
        UITextField *field = self.fields[i]; field.enabled = NO;
        field.text = [definitions[i][@"address"] intValue]==0 ? @"—" : (self.product.client.transport.isConnected ? @"未读取" : @"未连接");
        field.textColor = UIColor.darkGrayColor;
        // 选择目标类型不改变设备，也不清空已读取的当前参数。
        if (self.writing) { field.text = @"—"; continue; }
        for (NSDictionary *item in self.product.deviceParameters) {
            if ([item[@"address"] isEqual:definitions[i][@"address"]]) {
                field.text = [item[@"value"] stringValue];
                field.textColor = [item[@"valid"] boolValue] ? UIColor.darkGrayColor : UIColor.systemRedColor;
                break;
            }
        }
    }
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(productUpdated:) name:@"BMSProductDidUpdate" object:self.product];
    [self loadValues];
}
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)productUpdated:(NSNotification *)notification { [self loadValues]; }
- (void)read {
    self.selectedType = -1;
    [self.product readProduct:^(NSError *error) {
        [self loadValues];
        if (error && self.view.window) { BMSMessage(self, error.localizedDescription); }
    }];
}
- (void)selectType {
    if (self.writing) { return; }
    self.pickerGeneration = self.product.sessionGeneration;
    self.typeSheet = [UIViewController new]; self.typeSheet.view.backgroundColor = UIColor.whiteColor;
    self.typeSheet.modalPresentationStyle = UIModalPresentationPageSheet;
    self.typeSheet.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent];
    self.typePicker = [UIPickerView new]; self.typePicker.dataSource = self; self.typePicker.delegate = self;
    self.typePicker.translatesAutoresizingMaskIntoConstraints = NO;
    NSInteger actual = [self deviceType];
    NSInteger current = self.selectedType>=0 ? self.selectedType : (actual==0 || actual==1 ? actual : 0);
    [self.typePicker selectRow:current==0 || current==1 || current==2 ? current : 0 inComponent:0 animated:NO];
    UIToolbar *bar = [UIToolbar new]; bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.items = @[[[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain target:self action:@selector(cancelType)], [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil], [[UIBarButtonItem alloc] initWithTitle:@"确认" style:UIBarButtonItemStyleDone target:self action:@selector(confirmType)]];
    UILabel *hint = BMSText(@"选择后点击页面底部“修改”写入设备", 13, UIColor.secondaryLabelColor); hint.textAlignment = NSTextAlignmentCenter; hint.translatesAutoresizingMaskIntoConstraints = NO;
    [self.typeSheet.view addSubview:bar]; [self.typeSheet.view addSubview:hint]; [self.typeSheet.view addSubview:self.typePicker];
    [NSLayoutConstraint activateConstraints:@[
        [bar.topAnchor constraintEqualToAnchor:self.typeSheet.view.safeAreaLayoutGuide.topAnchor], [bar.leadingAnchor constraintEqualToAnchor:self.typeSheet.view.leadingAnchor], [bar.trailingAnchor constraintEqualToAnchor:self.typeSheet.view.trailingAnchor], [bar.heightAnchor constraintEqualToConstant:48],
        [hint.topAnchor constraintEqualToAnchor:bar.bottomAnchor constant:8], [hint.leadingAnchor constraintEqualToAnchor:self.typeSheet.view.leadingAnchor constant:16], [hint.trailingAnchor constraintEqualToAnchor:self.typeSheet.view.trailingAnchor constant:-16],
        [self.typePicker.topAnchor constraintEqualToAnchor:hint.bottomAnchor], [self.typePicker.bottomAnchor constraintEqualToAnchor:self.typeSheet.view.safeAreaLayoutGuide.bottomAnchor], [self.typePicker.leadingAnchor constraintEqualToAnchor:self.typeSheet.view.leadingAnchor], [self.typePicker.trailingAnchor constraintEqualToAnchor:self.typeSheet.view.trailingAnchor]
    ]];
    [self presentViewController:self.typeSheet animated:YES completion:nil];
}
- (void)cancelType { [self.typeSheet dismissViewControllerAnimated:YES completion:nil]; }
- (void)confirmType {
    if (self.pickerGeneration != self.product.sessionGeneration) { [self cancelType]; return; }
    self.selectedType = [self.typePicker selectedRowInComponent:0];
    [self loadValues]; [self.typeSheet dismissViewControllerAnimated:YES completion:nil];
}
- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView { return 1; }
- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component { return self.typeNames.count; }
- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component { return self.typeNames[row]; }
- (CGFloat)pickerView:(UIPickerView *)pickerView rowHeightForComponent:(NSInteger)component { return 46; }
- (void)applyType {
    NSInteger type = self.selectedType;
    if (type==2) { BMSMessage(self, @"测试类型的设备写入编码尚未确认。需要原 APP 选择“测试”并点击“修改”时的完整发送和返回报文，当前不会向设备写入猜测值。"); return; }
    if (type<0) { BMSMessage(self, @"请先点击电池类型，选择需要切换的类型"); return; }
    BMSClient *client = self.product.client;
    if (!client.transport.isConnected) { BMSMessage(self, @"请先连接真实蓝牙设备"); return; }
    if (self.product.reading || client.isBusy || self.writing) { BMSMessage(self, @"设备正在通信，请稍后重试"); return; }
    NSInteger actual = [self deviceType];
    if (actual<0) { BMSMessage(self, @"请先点击“读取”，获取设备当前类型和参数后再修改"); return; }
    if (actual==type) { self.selectedType = -1; [self loadValues]; return; }
    NSUInteger generation = self.product.sessionGeneration;
    self.writing = YES; self.product.reading = YES;
    self.product.deviceParameters = nil; self.product.lastReadDate = nil;
    self.product.readStatus = @"正在写入电芯类型并回读参数…";
    [self.product render]; [self loadValues];
    [client changeBatteryType:type completion:^(NSArray *parameters, NSError *error) {
        if (client != self.product.client || generation != self.product.sessionGeneration) { return; }
        self.writing = NO; self.product.reading = NO; self.selectedType = -1;
        if (error) {
            self.product.readStatus = [NSString stringWithFormat:@"切换结果未确认：%@。请点击读取确认设备状态。", error.localizedDescription];
        } else {
            self.product.deviceParameters = parameters; self.product.lastReadDate = NSDate.date;
            self.product.readStatus = [NSString stringWithFormat:@"已切换为%@ · 以下参数为设备实际回读值", self.typeNames[type]];
        }
        [self.product render]; [self loadValues];
        if (error && self.view.window) { BMSMessage(self, self.product.readStatus); }
    }];
}
@end
