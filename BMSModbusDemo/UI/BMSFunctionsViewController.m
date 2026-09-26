#import "BMSFunctionsViewController.h"

@interface BMSFunctionsViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, strong) BMSRealtimeData *snapshot;
@property (nonatomic, copy) NSDictionary *information;
@property (nonatomic, copy) NSArray<NSDictionary *> *parameters;
@property (nonatomic, copy) NSArray<NSDictionary *> *sections;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *readStates;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *lastUpdates;
@property (nonatomic, weak) UIAlertController *parameterDetail;
@property (nonatomic, copy) NSString *connectionMessage;
@property (nonatomic, copy) NSString *activityMessage;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) BOOL reading;
@end

@implementation BMSFunctionsViewController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"设备功能";
    self.tableView.backgroundColor = [UIColor colorWithWhite:0.965 alpha:1];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 68;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"设备" style:UIBarButtonItemStylePlain target:self action:@selector(openConnection)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"全部刷新" style:UIBarButtonItemStylePlain target:self action:@selector(refreshAll)];
    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"设备概览", @"常规参数"]];
    self.modeControl.selectedSegmentIndex = 0;
    [self.modeControl addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0,0,320,58)];
    self.modeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:self.modeControl];
    [NSLayoutConstraint activateConstraints:@[
        [self.modeControl.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [self.modeControl.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [self.modeControl.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [self.modeControl.heightAnchor constraintEqualToConstant:34]
    ]];
    self.tableView.tableHeaderView = header;
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self; self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = @"搜索参数名称或地址，如 D336";
    self.search.searchBar.searchTextField.backgroundColor = UIColor.whiteColor;
    self.definesPresentationContext = YES;
    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(refreshAll) forControlEvents:UIControlEventValueChanged];
    if (!self.readStates) { self.readStates = NSMutableDictionary.dictionary; }
    if (!self.lastUpdates) { self.lastUpdates = NSMutableDictionary.dictionary; }
    [self rebuildSections];
}
- (void)openConnection {
    if (self.search.isActive) {
        [self.search dismissViewControllerAnimated:NO completion:self.connectionAction];
    } else if (self.connectionAction) { self.connectionAction(); }
}
- (void)modeChanged {
    self.navigationItem.searchController = self.modeControl.selectedSegmentIndex == 1 ? self.search : nil;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    [self rebuildSections];
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self rebuildSections]; }
- (void)connectionChanged:(BOOL)connected message:(NSString *)message {
    self.generation++; self.reading = NO;
    self.snapshot = nil; self.information = nil; self.parameters = nil;
    self.readStates = NSMutableDictionary.dictionary;
    self.lastUpdates = NSMutableDictionary.dictionary;
    [self.parameterDetail dismissViewControllerAnimated:NO completion:nil];
    self.connectionMessage = message;
    self.activityMessage = connected ? @"点击“全部刷新”读取设备状态、信息和参数" : @"请先连接电池设备";
    if (self.isViewLoaded) {
        self.navigationItem.rightBarButtonItem.enabled = YES;
        [self.refreshControl endRefreshing]; [self rebuildSections];
    }
}
- (void)refreshAll {
    if (self.reading) { [self.refreshControl endRefreshing]; return; }
    if (!self.client.transport.isConnected || self.client.isBusy) {
        self.activityMessage = self.client.transport.isConnected ? @"设备正在处理其他请求，请稍后刷新" : @"未连接设备，请点击左上角“设备”连接";
        [self.refreshControl endRefreshing]; [self rebuildSections]; return;
    }
    self.reading = YES; self.navigationItem.rightBarButtonItem.enabled = NO;
    NSUInteger generation = self.generation;
    [self readStage:0 client:self.client generation:generation];
}
- (void)readStage:(NSUInteger)stage client:(BMSClient *)client generation:(NSUInteger)generation {
    if (generation != self.generation || client != self.client) { return; }
    NSArray *keys = @[@"state", @"info", @"parameters"];
    NSArray *names = @[@"设备状态", @"设备信息", @"常规参数"];
    if (stage == keys.count || !client.transport.isConnected) {
        self.reading = NO; self.navigationItem.rightBarButtonItem.enabled = YES;
        BOOL failed = NO;
        for (NSString *state in self.readStates.allValues) { if ([state containsString:@"失败"]) { failed = YES; } }
        self.activityMessage = !client.transport.isConnected ? @"连接已断开，请重新连接" : failed ? @"部分读取失败，请查看各分组状态后重试" : @"设备状态、信息和参数均已更新";
        [self.refreshControl endRefreshing]; [self rebuildSections]; return;
    }
    self.activityMessage = [NSString stringWithFormat:@"正在读取%@（%lu/3）…", names[stage], (unsigned long)stage+1];
    [self rebuildSections];
    __weak typeof(self) weakSelf = self;
    BMSClientCompletion completion = ^(id result, NSError *error) {
        typeof(self) self = weakSelf;
        if (!self || generation != self.generation || self.client != client) { return; }
        NSString *key = keys[stage];
        if (error) {
            NSString *previous = self.lastUpdates[key];
            if (previous.length) {
                self.readStates[key] = [NSString stringWithFormat:@"读取失败：%@；%@，保留上次读数", error.localizedDescription, previous];
            } else { self.readStates[key] = [NSString stringWithFormat:@"读取失败：%@%@", error.localizedDescription, previous.length ? @"；已有读数未更新" : @""]; }
        } else {
            if (stage == 0) { self.snapshot = result; }
            else if (stage == 1) { self.information = result; }
            else { self.parameters = result; }
            NSDateFormatter *format = [NSDateFormatter new]; format.dateFormat = @"yyyy-MM-dd HH:mm:ss";
            self.readStates[key] = [@"更新于 " stringByAppendingString:[format stringFromDate:NSDate.date]];
            self.lastUpdates[key] = self.readStates[key];
        }
        [self readStage:stage+1 client:client generation:generation];
    };
    if (stage == 0) { [client readRealtimeData:completion]; }
    else if (stage == 1) { [client readDeviceInformation:completion]; }
    else { [client readCommonParameters:completion]; }
}
- (NSDictionary *)row:(NSString *)title value:(NSString *)value {
    return @{@"title":title, @"value":value.length ? value : @"—"};
}
- (NSDictionary *)section:(NSString *)title rows:(NSArray *)rows footer:(NSString *)footer {
    return @{@"title":title, @"rows":rows, @"footer":footer ?: @""};
}
- (NSString *)stateFor:(NSString *)key { return self.readStates[key] ?: @"尚未读取"; }
- (void)rebuildSections {
    if (!self.isViewLoaded) { return; }
    NSMutableArray *sections = NSMutableArray.array;
    NSString *connection = self.connectionMessage ?: @"未连接设备";
    [sections addObject:[self section:@"连接与读取" rows:@[[self row:connection value:self.activityMessage ?: @"连接后点击“全部刷新”"]] footer:@""]];
    if (self.modeControl.selectedSegmentIndex == 0) {
        NSDictionary *v = [self.snapshot monitorValuesForCellCount:nil];
        NSMutableArray *states = NSMutableArray.array;
        NSArray *names = @[@"充电 MOS", @"放电 MOS", @"预充 MOS", @"预放 MOS", @"限流 MOS"];
        for (NSUInteger i=0; i<names.count; i++) { [states addObject:[self row:names[i] value:v[[NSString stringWithFormat:@"mos%lu",(unsigned long)i]]]]; }
        [states addObject:[self row:@"MOS 温度 / 环境温度" value:[NSString stringWithFormat:@"%@ / %@",v[@"mosTemp"] ?: @"—", v[@"ambient"] ?: @"—"]]];
        NSString *fault = @"—";
        if (self.snapshot) {
            if (self.snapshot.faultBits >= 0xFFFE || self.snapshot.faultLevel > 2) { fault = @"故障状态无效或未知"; }
            else if (!self.snapshot.faultBits && !self.snapshot.faultLevel) { fault = @"正常"; }
            else {
                fault = [NSString stringWithFormat:@"%@ · 等级 %lu · 0x%04X", self.snapshot.faultDescriptions.count ? [self.snapshot.faultDescriptions componentsJoinedByString:@"、"] : @"设备返回故障等级或未定义故障位", (unsigned long)self.snapshot.faultLevel, self.snapshot.faultBits];
            }
        }
        [states addObject:[self row:@"报警状态" value:fault]];
        [sections addObject:[self section:@"设备状态" rows:states footer:[self stateFor:@"state"]]];
        NSArray *infoNames = @[@"软件版本", @"硬件版本", @"设备识别码", @"设备时间", @"零电流原始值", @"自检原始值"];
        NSArray *infoKeys = @[@"software", @"hardware", @"identifier", @"time", @"zeroCurrent", @"selfTest"];
        NSMutableArray *infoRows = NSMutableArray.array;
        for (NSUInteger i=0; i<infoNames.count; i++) {
            id value = self.information[infoKeys[i]];
            [infoRows addObject:[self row:infoNames[i] value:value ? [value description] : nil]];
        }
        [sections addObject:[self section:@"设备信息" rows:infoRows footer:[self stateFor:@"info"]]];
        [sections addObject:[self section:@"设备控制" rows:@[[self row:@"MOS 开关控制" value:@"暂不可用 · 等待确认设备控制协议"]] footer:@"目前可查看开关状态，确认设备控制协议后再接入操作。"]];
    } else {
        NSString *query = [self.search.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        NSArray *titles = @[@"电压保护", @"均衡设置", @"电流保护", @"温度保护", @"校准参数", @"电池配置"];
        NSArray *limits = @[@309, @312, @323, @331, @335, @342];
        NSUInteger start = 300, matches = 0;
        for (NSUInteger group=0; group<titles.count; group++) {
            NSMutableArray *rows = NSMutableArray.array;
            for (NSDictionary *item in self.parameters) {
                NSUInteger address = [item[@"address"] unsignedIntegerValue];
                if (address < start || address >= [limits[group] unsignedIntegerValue]) { continue; }
                NSString *searchText = [NSString stringWithFormat:@"%@ D%@ %@", item[@"name"], item[@"address"], item[@"unit"]];
                if (query.length && [searchText rangeOfString:query options:NSCaseInsensitiveSearch].location == NSNotFound) { continue; }
                NSString *display = [NSString stringWithFormat:@"%g %@",[item[@"value"] doubleValue],item[@"unit"]];
                if (address == 336) { display = [item[@"raw"] integerValue] == 0 ? @"三元锂" : [item[@"raw"] integerValue] == 1 ? @"磷酸铁锂" : [NSString stringWithFormat:@"未知类型 (%@)", item[@"raw"]]; }
                [rows addObject:@{@"title":[NSString stringWithFormat:@"%@  ·  %@", item[@"name"], display], @"value":[NSString stringWithFormat:@"D%@ · %@",item[@"address"],[item[@"valid"] boolValue] ? @"点击查看详情" : @"超出协议范围 · 点击查看原值"], @"parameter":item}];
            }
            if (rows.count) { [sections addObject:[self section:titles[group] rows:rows footer:@""]]; matches += rows.count; }
            start = [limits[group] unsignedIntegerValue];
        }
        NSString *summary = self.parameters ? [NSString stringWithFormat:@"显示 %lu / %lu 项参数",(unsigned long)matches,(unsigned long)self.parameters.count] : @"尚未读取设备参数";
        [sections addObject:[self section:summary rows:matches ? @[] : @[[self row:self.parameters ? @"没有匹配的参数" : @"点击“全部刷新”读取参数" value:self.parameters ? @"尝试参数名称或 D300～D341 地址" : @"读取后可搜索并查看参数详情"]] footer:[NSString stringWithFormat:@"%@\n参数只读；电流和延时档位按设备原值展示。",[self stateFor:@"parameters"]]]];
    }
    self.sections = sections; [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self.sections[section][@"rows"] count]; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return self.sections[section][@"title"]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return self.sections[section][@"footer"]; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"function"];
    if (!cell) { cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"function"]; }
    NSDictionary *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    cell.textLabel.text = row[@"title"]; cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium]; cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.text = row[@"value"]; cell.detailTextLabel.font = [UIFont systemFontOfSize:14]; cell.detailTextLabel.numberOfLines = 0;
    NSDictionary *parameter = row[@"parameter"];
    cell.detailTextLabel.textColor = parameter && ![parameter[@"valid"] boolValue] ? UIColor.systemRedColor : UIColor.secondaryLabelColor;
    cell.accessoryType = parameter ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    cell.selectionStyle = parameter ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = self.sections[indexPath.section][@"rows"][indexPath.row][@"parameter"];
    if (!item) { return; }
    double scale = [item[@"scale"] doubleValue], offset = [item[@"offset"] doubleValue];
    NSString *message = [NSString stringWithFormat:@"当前值：%g %@\n寄存器：D%@ (0x%04X)\n原始值：%@ (0x%04X)\n换算：原始值 × %g %+.0f\n协议范围：%g～%g %@\n%@\n%@", [item[@"value"] doubleValue],item[@"unit"],item[@"address"],[item[@"address"] unsignedIntValue],item[@"raw"],[item[@"raw"] unsignedIntValue],scale,offset,[item[@"min"] doubleValue]*scale+offset,[item[@"max"] doubleValue]*scale+offset,item[@"unit"],[item[@"valid"] boolValue] ? @"数值在协议范围内" : @"数值超出协议范围，已保留设备原值",[self stateFor:@"parameters"]];
    if ([item[@"unit"] isEqual:@"档"]) { message = [message stringByAppendingString:@"\n档位对应的电流或时间换算尚未确认。"]; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:item[@"name"] message:message preferredStyle:UIAlertControllerStyleAlert];
    self.parameterDetail = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    UIViewController *presenter = self.search.isActive ? self.search : self;
    [presenter presentViewController:alert animated:YES completion:nil];
}
@end
