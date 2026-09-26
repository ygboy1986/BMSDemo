#import "BMSBLETransport.h"
#import "BMSBLEConfiguration.h"

@interface BMSBLEDevice ()
@property (nonatomic, copy, readwrite) NSUUID *identifier;
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, strong, readwrite) NSNumber *RSSI;
@end

@implementation BMSBLEDevice
@end

@interface BMSBLETransport ()
@property (nonatomic, strong) BMSBLEConfiguration *configuration;
@property (nonatomic, strong) CBCentralManager *central;
@property (nonatomic, strong, nullable) CBPeripheral *peripheral;
@property (nonatomic, strong, nullable) CBCharacteristic *writeCharacteristic;
@property (nonatomic, strong, nullable) CBCharacteristic *notifyCharacteristic;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, CBPeripheral *> *discoveredPeripherals;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, BMSBLEDevice *> *discoveredDevices;
@property (nonatomic, readwrite, getter=isConnected) BOOL connected;
@property (nonatomic, readwrite, getter=isScanning) BOOL scanning;
@property (nonatomic) BOOL scanRequested;
@property (nonatomic) NSUInteger scanGeneration;
@property (nonatomic) NSInteger pendingCharacteristicDiscoveries;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, CBCharacteristic *> *> *fallbackCharacteristicPairs;
@property (nonatomic, copy) NSArray<NSString *> *discoveredServiceUUIDs;
@property (nonatomic) NSUInteger gattDiscoveryGeneration;
@property (nonatomic, strong) NSMutableArray<NSData *> *pendingWriteChunks;
@property (nonatomic) BOOL connecting;
@end

@implementation BMSBLETransport

- (instancetype)initWithConfiguration:(BMSBLEConfiguration *)configuration {
    if (self = [super init]) {
        _configuration = configuration;
        _discoveredPeripherals = NSMutableDictionary.dictionary;
        _discoveredDevices = NSMutableDictionary.dictionary;
        _fallbackCharacteristicPairs = NSMutableArray.array;
        _discoveredServiceUUIDs = @[];
        _pendingWriteChunks = NSMutableArray.array;
        _central = [[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue()];
    }
    return self;
}

- (void)connect {
    if (self.peripheral) { [self disconnect]; }
    self.scanRequested = YES;
    if (self.central.state != CBManagerStatePoweredOn) {
        [self publishState:NO message:@"等待系统蓝牙就绪…"];
        return;
    }
    [self beginScan];
}

- (void)beginScan {
    self.scanGeneration += 1;
    NSUInteger generation = self.scanGeneration;
    [self.discoveredPeripherals removeAllObjects];
    [self.discoveredDevices removeAllObjects];
    if (self.devicesHandler) { self.devicesHandler(@[]); }
    // 不用 Service UUID 过滤，因为不少透传模块不会在广播包中携带服务 UUID。
    // 禁止重复广播回调。否则每个广播包都刷新整套 UI，会造成 CPU 和内存持续升高。
    [self.central scanForPeripheralsWithServices:nil options:@{CBCentralManagerScanOptionAllowDuplicatesKey: @NO}];
    self.scanning = YES;
    [self publishState:NO message:@"正在扫描附近蓝牙设备…"];
    // 扫描不是常驻任务，12 秒后自动停止。重新扫描会递增 generation，使旧定时回调失效。
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !self.isScanning || self.scanGeneration != generation) { return; }
        [self.central stopScan];
        self.scanning = NO;
        self.scanRequested = NO;
        [self publishState:NO message:[NSString stringWithFormat:@"扫描完成，发现 %lu 台设备", (unsigned long)self.discoveredDevices.count]];
    });
}

- (void)connectToDevice:(BMSBLEDevice *)device {
    if (self.connecting || (self.peripheral && !self.connected)) {
        [self publishState:NO message:@"正在连接设备，请稍候…"];
        return;
    }
    CBPeripheral *peripheral = self.discoveredPeripherals[device.identifier];
    if (!peripheral) {
        [self publishError:@"该设备已不在扫描结果中，请重新扫描" code:15];
        return;
    }
    self.scanRequested = NO;
    self.scanning = NO;
    self.scanGeneration += 1;
    [self.central stopScan];
    self.peripheral = peripheral;
    self.connecting = YES;
    peripheral.delegate = self;
    [self.central connectPeripheral:peripheral options:nil];
    [self publishState:NO message:[NSString stringWithFormat:@"正在连接 %@…", device.name]];
}

- (void)disconnect {
    [self.central stopScan];
    if (self.peripheral) { [self.central cancelPeripheralConnection:self.peripheral]; }
    self.peripheral = nil;
    self.writeCharacteristic = nil;
    self.notifyCharacteristic = nil;
    [self.pendingWriteChunks removeAllObjects];
    self.gattDiscoveryGeneration += 1;
    self.connected = NO;
    self.connecting = NO;
    self.scanning = NO;
    self.scanRequested = NO;
    self.scanGeneration += 1;
    [self publishState:NO message:@"已断开"];
}

- (void)sendData:(NSData *)data {
    if (!self.peripheral || !self.writeCharacteristic || !self.connected) {
        [self publishError:@"蓝牙尚未连接或写特征尚未发现" code:10];
        return;
    }
    if (self.pendingWriteChunks.count) {
        [self publishError:@"上一批蓝牙数据尚未发送完成" code:19];
        return;
    }
    // CoreBluetooth 会限制单次写入长度，因此先分片，再按特征写入类型串行发送。
    NSUInteger maximum = [self.peripheral maximumWriteValueLengthForType:self.configuration.writeType];
    maximum = MAX(maximum, 1);
    for (NSUInteger offset = 0; offset < data.length; offset += maximum) {
        NSUInteger length = MIN(maximum, data.length - offset);
        NSData *chunk = [data subdataWithRange:NSMakeRange(offset, length)];
        [self.pendingWriteChunks addObject:chunk];
    }
    [self sendPendingWriteChunks];
}

- (void)sendPendingWriteChunks {
    if (!self.peripheral || !self.writeCharacteristic || !self.pendingWriteChunks.count) { return; }
    if (self.configuration.writeType == CBCharacteristicWriteWithResponse) {
        // WithResponse 每次只发一个包，等待 didWriteValue 回调后再发送下一个。
        NSData *chunk = self.pendingWriteChunks.firstObject;
        [self.pendingWriteChunks removeObjectAtIndex:0];
        [self.peripheral writeValue:chunk forCharacteristic:self.writeCharacteristic type:CBCharacteristicWriteWithResponse];
        return;
    }
    // WithoutResponse 受 CoreBluetooth 流控控制，不能无上限连续灌入数据。
    while (self.pendingWriteChunks.count && self.peripheral.canSendWriteWithoutResponse) {
        NSData *chunk = self.pendingWriteChunks.firstObject;
        [self.pendingWriteChunks removeObjectAtIndex:0];
        [self.peripheral writeValue:chunk forCharacteristic:self.writeCharacteristic type:CBCharacteristicWriteWithoutResponse];
    }
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {

    if (central.state == CBManagerStatePoweredOn) {

        if (self.scanRequested) { [self beginScan]; }
        else { [self publishState:NO message:@"蓝牙可用，点击扫描设备"] ; }
    } else {
        self.connected = NO; self.connecting = NO; self.scanning = NO;
        self.peripheral = nil; self.writeCharacteristic = nil; self.notifyCharacteristic = nil;
        [self.pendingWriteChunks removeAllObjects];
        self.gattDiscoveryGeneration++; self.scanGeneration++;
        [self publishState:NO message:@"系统蓝牙不可用"];
    }
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary<NSString *,id> *)advertisementData RSSI:(NSNumber *)RSSI {
    NSString *name = peripheral.name ?: advertisementData[CBAdvertisementDataLocalNameKey] ?: @"";
    // 仅显示指定产品系列。使用不区分大小写的比较，兼容 yt、Yt 等广播名称。
    NSMutableArray<NSString *> *allowedPrefixes = [self.configuration.deviceNamePrefixes mutableCopy] ?: NSMutableArray.array;
    if (self.configuration.deviceNamePrefix.length) { [allowedPrefixes addObject:self.configuration.deviceNamePrefix]; }
    BOOL nameMatched = allowedPrefixes.count == 0;
    NSString *uppercaseName = name.uppercaseString;
    for (NSString *prefix in allowedPrefixes) {
        if ([uppercaseName hasPrefix:prefix.uppercaseString]) { nameMatched = YES; break; }
    }
    if (!nameMatched) { return; }
    // 同一 identifier 只加入一次；列表最多展示 50 台，避免异常环境中无限持有设备对象。
    if (self.discoveredDevices[peripheral.identifier]) { return; }
    if (self.discoveredDevices.count >= 50) { return; }
    BMSBLEDevice *device = [[BMSBLEDevice alloc] init];
    device.identifier = peripheral.identifier;
    device.name = name.length ? name : @"未命名设备";
    device.RSSI = RSSI;
    // 两个字典都强引用对象，保证用户稍后点击列表时仍可连接对应的 CBPeripheral。
    self.discoveredPeripherals[peripheral.identifier] = peripheral;
    self.discoveredDevices[peripheral.identifier] = device;
    NSArray *devices = [self.discoveredDevices.allValues sortedArrayUsingComparator:^NSComparisonResult(BMSBLEDevice *left, BMSBLEDevice *right) {
        return [right.RSSI compare:left.RSSI]; // 信号较强的设备排在前面。
    }];
    if (self.devicesHandler) { self.devicesHandler(devices); }
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    if (peripheral != self.peripheral) { return; }
    self.connecting = NO;
    [self publishState:NO message:[NSString stringWithFormat:@"已连接 %@，正在发现服务…", peripheral.name ?: @"设备"]];
    self.gattDiscoveryGeneration += 1;
    NSUInteger generation = self.gattDiscoveryGeneration;
    // 先枚举全部服务。若示例 UUID 与实机不一致，仍能看到真实服务并尝试识别透传特征。
    [peripheral discoverServices:nil];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.connected || self.gattDiscoveryGeneration != generation || self.peripheral != peripheral) { return; }
        NSString *services = self.discoveredServiceUUIDs.count ? [self.discoveredServiceUUIDs componentsJoinedByString:@", "] : @"无";
        [self publishError:[NSString stringWithFormat:@"GATT 服务/特征发现超时。已发现服务：%@", services] code:18];
    });
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    if (peripheral != self.peripheral) { return; }
    self.connecting = NO;
    self.peripheral = nil;
    [self publishError:error.localizedDescription ?: @"蓝牙连接失败" code:11];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    if (peripheral != self.peripheral) { return; }
    self.connecting = NO;
    self.peripheral = nil;
    self.connected = NO;
    self.writeCharacteristic = nil;
    self.notifyCharacteristic = nil;
    [self.pendingWriteChunks removeAllObjects];
    self.gattDiscoveryGeneration += 1;
    if (error) {
        [self publishError:[NSString stringWithFormat:@"蓝牙意外断开（%ld）：%@", (long)error.code, error.localizedDescription] code:22];
    } else {
        [self publishState:NO message:@"已断开"];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    if (peripheral != self.peripheral) { return; }
    if (error) { [self publishError:error.localizedDescription code:12]; return; }
    if (peripheral.services.count == 0) {
        [self publishError:@"设备已连接，但未返回任何 GATT 服务" code:16];
        return;
    }
    NSMutableArray<NSString *> *serviceUUIDs = NSMutableArray.array;
    for (CBService *service in peripheral.services) { [serviceUUIDs addObject:service.UUID.UUIDString]; }
    self.discoveredServiceUUIDs = serviceUUIDs;
    self.writeCharacteristic = nil;
    self.notifyCharacteristic = nil;
    [self.fallbackCharacteristicPairs removeAllObjects];
    self.pendingCharacteristicDiscoveries = peripheral.services.count;
    [self publishState:NO message:[NSString stringWithFormat:@"发现 %lu 个服务，正在检查特征…", (unsigned long)peripheral.services.count]];
    for (CBService *service in peripheral.services) {
        [peripheral discoverCharacteristics:nil forService:service];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    if (peripheral != self.peripheral) { return; }
    self.pendingCharacteristicDiscoveries = MAX(0, self.pendingCharacteristicDiscoveries - 1);
    if (error) {
        if (self.pendingCharacteristicDiscoveries == 0) { [self finishCharacteristicDiscoveryForPeripheral:peripheral]; }
        return;
    }
    CBUUID *serviceUUID = [CBUUID UUIDWithString:self.configuration.serviceUUID];
    CBUUID *writeUUID = [CBUUID UUIDWithString:self.configuration.writeCharacteristicUUID];
    CBUUID *notifyUUID = [CBUUID UUIDWithString:self.configuration.notifyCharacteristicUUID];
    CBCharacteristic *fallbackWrite;
    CBCharacteristic *fallbackNotify;
    for (CBCharacteristic *characteristic in service.characteristics) {
        if ([service.UUID isEqual:serviceUUID] && [characteristic.UUID isEqual:writeUUID]) {
            self.writeCharacteristic = characteristic;
        }
        if ([service.UUID isEqual:serviceUUID] && [characteristic.UUID isEqual:notifyUUID]) {
            self.notifyCharacteristic = characteristic;
        }
        CBCharacteristicProperties properties = characteristic.properties;
        if (!fallbackWrite && (properties & (CBCharacteristicPropertyWrite | CBCharacteristicPropertyWriteWithoutResponse))) { fallbackWrite = characteristic; }
        if (!fallbackNotify && (properties & (CBCharacteristicPropertyNotify | CBCharacteristicPropertyIndicate))) { fallbackNotify = characteristic; }
    }
    if (fallbackWrite && fallbackNotify) {
        [self.fallbackCharacteristicPairs addObject:@{@"write": fallbackWrite, @"notify": fallbackNotify}];
    }
    if (self.pendingCharacteristicDiscoveries == 0) { [self finishCharacteristicDiscoveryForPeripheral:peripheral]; }
}

- (void)finishCharacteristicDiscoveryForPeripheral:(CBPeripheral *)peripheral {
    if (peripheral != self.peripheral) { return; }
    BOOL usedAutomaticDetection = NO;
    if ((!self.writeCharacteristic || !self.notifyCharacteristic) &&
        self.configuration.automaticallyDetectUARTCharacteristics && self.fallbackCharacteristicPairs.count) {
        NSDictionary<NSString *, CBCharacteristic *> *pair = self.fallbackCharacteristicPairs.firstObject;
        self.writeCharacteristic = pair[@"write"];
        self.notifyCharacteristic = pair[@"notify"];
        usedAutomaticDetection = YES;
    }
    if (!self.writeCharacteristic || !self.notifyCharacteristic) {
        NSString *services = [self.discoveredServiceUUIDs componentsJoinedByString:@", "];
        [self publishError:[NSString stringWithFormat:@"未找到可用的写入/通知特征。设备服务：%@", services] code:17];
        return;
    }
    CBCharacteristicProperties writeProperties = self.writeCharacteristic.properties;
    // 尊重配置的优先类型；如果硬件不支持，则自动切换到它实际声明的写入方式。
    if (self.configuration.writeType == CBCharacteristicWriteWithoutResponse && !(writeProperties & CBCharacteristicPropertyWriteWithoutResponse)) {
        self.configuration.writeType = CBCharacteristicWriteWithResponse;
    } else if (self.configuration.writeType == CBCharacteristicWriteWithResponse && !(writeProperties & CBCharacteristicPropertyWrite)) {
        self.configuration.writeType = CBCharacteristicWriteWithoutResponse;
    }
    [peripheral setNotifyValue:YES forCharacteristic:self.notifyCharacteristic];
    NSString *prefix = usedAutomaticDetection ? @"自动识别" : @"配置匹配";
    [self publishState:NO message:[NSString stringWithFormat:@"%@完成，正在启用通知…", prefix]];
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if (peripheral != self.peripheral) { return; }
    if (error) { [self publishError:[NSString stringWithFormat:@"启用通知失败：%@", error.localizedDescription] code:20]; return; }
    if (characteristic != self.notifyCharacteristic || !characteristic.isNotifying) { return; }
    NSUInteger generation = self.gattDiscoveryGeneration;
    // 给部分串口透传固件一点时间完成 CCCD 后处理，再允许业务层发送首帧。
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.gattDiscoveryGeneration != generation || peripheral.state != CBPeripheralStateConnected) { return; }
        self.connected = YES;
        self.gattDiscoveryGeneration += 1;
        NSString *writeMode = self.configuration.writeType == CBCharacteristicWriteWithoutResponse ? @"WithoutResponse" : @"WithResponse";
        NSString *detail = [NSString stringWithFormat:@"服务 %@，写 %@（%@），通知 %@",
                            self.writeCharacteristic.service.UUID.UUIDString,
                            self.writeCharacteristic.UUID.UUIDString,
                            writeMode,
                            self.notifyCharacteristic.UUID.UUIDString];
        [self publishState:YES message:[NSString stringWithFormat:@"已连接 %@（%@）", peripheral.name ?: @"BMS", detail]];
    });
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if (peripheral != self.peripheral) { return; }
    if (error) {
        [self.pendingWriteChunks removeAllObjects];
        [self publishError:[NSString stringWithFormat:@"蓝牙写入失败：%@", error.localizedDescription] code:21];
        return;
    }
    [self sendPendingWriteChunks];
}

- (void)peripheralIsReadyToSendWriteWithoutResponse:(CBPeripheral *)peripheral {
    if (peripheral != self.peripheral) { return; }
    [self sendPendingWriteChunks];
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if (peripheral != self.peripheral) { return; }
    if (error) { [self publishError:error.localizedDescription code:14]; return; }
    if (characteristic.value.length && self.receiveHandler) { self.receiveHandler(characteristic.value); }
}

- (void)publishState:(BOOL)connected message:(NSString *)message {
    if (self.stateHandler) { self.stateHandler(connected, message); }
}

- (void)publishError:(NSString *)message code:(NSInteger)code {
    NSError *error = [NSError errorWithDomain:@"com.demo.bms.ble" code:code userInfo:@{NSLocalizedDescriptionKey: message}];
    if (!self.connected) { [self publishState:NO message:[NSString stringWithFormat:@"连接失败：%@", message]]; }
    if (self.errorHandler) { self.errorHandler(error); }
}

@end
