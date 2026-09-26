#import "BMSRealtimeData.h"
#import "../Protocol/BMSModbusCodec.h"

@interface BMSRealtimeData ()
@property (nonatomic, readwrite) double totalVoltage;
@property (nonatomic, readwrite) double totalCurrent;
@property (nonatomic, readwrite) NSUInteger realSOC;
@property (nonatomic, readwrite) NSUInteger displaySOC;
@property (nonatomic, readwrite) NSUInteger SOH;
@property (nonatomic, readwrite) NSInteger MOSTemperature;
@property (nonatomic, readwrite) NSInteger ambientTemperature;
@property (nonatomic, readwrite) uint16_t faultBits;
@property (nonatomic, readwrite) NSUInteger faultLevel;
@property (nonatomic, readwrite) BOOL chargeMOSOn;
@property (nonatomic, readwrite) BOOL dischargeMOSOn;
@property (nonatomic, readwrite) BOOL prechargeMOSOn;
@property (nonatomic, readwrite) BOOL preventionMOSOn;
@property (nonatomic, readwrite) BOOL currentLimitMOSOn;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *faultDescriptions;
@property (nonatomic, copy, readwrite) NSArray<NSNumber *> *rawRegisters;
@property (nonatomic, copy, readwrite) NSArray *cellVoltages;
@property (nonatomic, copy, readwrite) NSArray *probeTemperatures;
@property (nonatomic, copy, readwrite) NSString *detailText;
@end

@implementation BMSRealtimeData

- (instancetype)initWithFullRegisters:(NSArray<NSNumber *> *)registers error:(NSError **)error {
    if (registers.count != 86) {
        if (error) { *error = [NSError errorWithDomain:BMSModbusErrorDomain code:30 userInfo:@{NSLocalizedDescriptionKey:@"完整实时区需要86个寄存器"}]; }
        return nil;
    }
    self = [self initWithRegisters:[registers subarrayWithRange:NSMakeRange(46, 40)] error:error];
    if (!self) { return nil; }
    _rawRegisters = registers.copy;
    NSMutableArray *cells = NSMutableArray.array, *temperatures = NSMutableArray.array;
    NSMutableString *text = NSMutableString.string;
    [text appendFormat:@"SOH：%@\n真实SOC：%@\n循环次数：%@\n充电次数：%@\n短路次数：%@\n",
     self.SOH <= 100 ? [NSString stringWithFormat:@"%lu%%", (unsigned long)self.SOH] : @"无效/异常",
     self.realSOC <= 100 ? [NSString stringWithFormat:@"%lu%%", (unsigned long)self.realSOC] : @"无效/异常",
     registers[54], registers[53], registers[52]];
    // 双寄存器量按高字在前解析；原始寄存器同时保留，便于厂家核验字序。
    NSArray *capacityNames = @[@"剩余容量", @"满充容量", @"循环容量", @"标称容量"];
    for (NSUInteger i = 0; i < 4; i++) {
        NSUInteger offset = 72 + i * 2;
        uint32_t raw = ((uint32_t)registers[offset].unsignedShortValue << 16) | registers[offset + 1].unsignedShortValue;
        [text appendFormat:@"%@：%@\n", capacityNames[i], raw <= 1000000 ? [NSString stringWithFormat:@"%.3f Ah", raw / 1000.0] : @"无效/异常"];
    }
    [text appendFormat:@"均衡原始字：0x%04X 0x%04X\n工作状态原始字：0x%04X 0x%04X\n", registers[63].unsignedShortValue, registers[64].unsignedShortValue, registers[65].unsignedShortValue, registers[66].unsignedShortValue];
    [text appendString:@"\n单体电压（0值保留，未推断串数）\n"];
    for (NSUInteger i = 0; i < 32; i++) {
        uint16_t raw = registers[8 + i].unsignedShortValue;
        id value = raw <= 6000 ? @(raw / 1000.0) : NSNull.null;
        [cells addObject:value];
        [text appendFormat:@"%02lu：%@%@", (unsigned long)i + 1, value == NSNull.null ? @"无效/异常" : [NSString stringWithFormat:@"%.3fV", [value doubleValue]], i % 2 ? @"\n" : @"    "];
    }
    [text appendString:@"\n探针温度\n"];
    for (NSUInteger i = 0; i < 6; i++) {
        uint16_t raw = registers[40 + i].unsignedShortValue;
        id value = raw <= 250 ? @((NSInteger)raw - 40) : NSNull.null;
        [temperatures addObject:value];
        [text appendFormat:@"探针%lu：%@\n", (unsigned long)i + 1, value == NSNull.null ? @"无效/异常" : [NSString stringWithFormat:@"%@℃", value]];
    }
    NSArray *mosNames = @[@"充电", @"放电", @"预充", @"预放", @"限流"];
    for (NSUInteger i = 0; i < 5; i++) {
        uint16_t raw = registers[81 + i].unsignedShortValue;
        [text appendFormat:@"%@MOS：%@\n", mosNames[i], raw == 1 ? @"闭合" : raw == 0 ? @"断开" : @"无效/异常"];
    }
    _cellVoltages = cells.copy; _probeTemperatures = temperatures.copy; _detailText = text.copy;
    return self;
}

- (instancetype)initWithRegisters:(NSArray<NSNumber *> *)registers error:(NSError **)error {
    // 0x008E~0x00B5 一共 40 个寄存器。用完整区块读取可保持同一时刻的数据一致性。
    if (registers.count != 40) {
        if (error) {
            *error = [NSError errorWithDomain:BMSModbusErrorDomain
                                         code:30
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"实时寄存器数量错误：期望40，收到%lu", (unsigned long)registers.count]}];
        }
        return nil;
    }
    if (self = [super init]) {
        uint16_t socWord = registers[0].unsignedShortValue;        // 0x008E
        _realSOC = (socWord >> 8) & 0xFF;
        _displaySOC = socWord & 0xFF;
        _SOH = registers[1].unsignedShortValue;                    // 0x008F
        _totalCurrent = ((NSInteger)registers[4].unsignedShortValue - 10000) / 10.0; // 0x0092
        _totalVoltage = registers[5].unsignedShortValue / 10.0;    // 0x0093
        _faultBits = registers[21].unsignedShortValue;             // 0x00A3
        _faultLevel = registers[22].unsignedShortValue;            // 0x00A4
        _MOSTemperature = (NSInteger)registers[24].unsignedShortValue - 40; // 0x00A6
        _ambientTemperature = (NSInteger)registers[25].unsignedShortValue - 40; // 0x00A7
        _chargeMOSOn = registers[35].unsignedShortValue == 1;      // 0x00B1
        _dischargeMOSOn = registers[36].unsignedShortValue == 1;   // 0x00B2
        _prechargeMOSOn = registers[37].unsignedShortValue == 1;   // 0x00B3
        _preventionMOSOn = registers[38].unsignedShortValue == 1;  // 0x00B4
        _currentLimitMOSOn = registers[39].unsignedShortValue == 1;// 0x00B5

        NSArray<NSString *> *names = @[
            @"充电过压", @"放电欠压", @"充电过流", @"放电过流1", @"放电过流2",
            @"短路", @"充电高温", @"充电低温", @"放电高温", @"放电低温",
            @"压差故障", @"DC-DC温度", @"SOC低", @"绝缘故障"
        ];
        NSMutableArray<NSString *> *activeFaults = NSMutableArray.array;
        for (NSUInteger bit = 0; bit < names.count; bit++) {
            if (_faultBits & (1U << bit)) { [activeFaults addObject:names[bit]]; }
        }
        _faultDescriptions = activeFaults.copy;
    }
    return self;
}

- (NSDictionary<NSString *, NSString *> *)monitorValuesForCellCount:(NSNumber *)cellCount {
    if (self.rawRegisters.count != 86) { return @{}; }
    NSArray<NSNumber *> *r = self.rawRegisters;
    NSMutableDictionary *v = NSMutableDictionary.dictionary;
    NSString *(^number)(NSUInteger, NSUInteger, double, double, NSString *) = ^NSString *(NSUInteger i, NSUInteger max, double scale, double offset, NSString *unit) {
        NSUInteger raw = r[i].unsignedIntegerValue;
        if (raw > max) { return @"—"; }
        return [NSString stringWithFormat:@"%g%@", raw * scale + offset, unit];
    };
    v[@"voltage"] = r[51].unsignedIntegerValue <= 60000 ? [NSString stringWithFormat:@"%.3f V", self.totalVoltage] : @"—";
    v[@"current"] = r[50].unsignedIntegerValue <= 20000 ? [NSString stringWithFormat:@"%.3f A", self.totalCurrent] : @"—";
    v[@"power"] = r[51].unsignedIntegerValue <= 60000 && r[50].unsignedIntegerValue <= 20000 ? [NSString stringWithFormat:@"%.1f W", self.totalVoltage * self.totalCurrent] : @"—";
    v[@"soc"] = self.displaySOC <= 100 ? [NSString stringWithFormat:@"%lu%%", (unsigned long)self.displaySOC] : @"—";
    v[@"soh"] = number(47, 100, 1, 0, @"%");
    // 工作状态字缺少枚举定义，不能用电流方向或 MOS 状态冒充设备状态。
    v[@"mode"] = @"待确认"; v[@"state"] = @"待确认"; v[@"remaining"] = @"—";
    v[@"count"] = cellCount && cellCount.integerValue >= 1 && cellCount.integerValue <= 32 ? [NSString stringWithFormat:@"%@ S", cellCount] : @"—";
    v[@"maxVoltage"] = @"—"; v[@"minVoltage"] = @"—"; v[@"difference"] = @"—";
    v[@"maxIndex"] = @"—"; v[@"minIndex"] = @"—";
    // 根据设备配置的有效串数计算，同一 CRC 校验通过的快照内计算，0mV 也是读数。
    NSInteger count = cellCount.integerValue;
    if (count >= 1 && count <= 32) {
        NSInteger high = -1, low = 6001; NSUInteger highIndex = 0, lowIndex = 0; BOOL valid = YES;
        for (NSUInteger i = 0; i < (NSUInteger)count; i++) {
            NSInteger raw = r[8+i].integerValue;
            if (raw > 6000) { valid = NO; break; }
            if (raw > high) { high = raw; highIndex = i+1; }
            if (raw < low) { low = raw; lowIndex = i+1; }
        }
        if (valid) {
            v[@"maxVoltage"] = [NSString stringWithFormat:@"%ld mV", (long)high];
            v[@"minVoltage"] = [NSString stringWithFormat:@"%ld mV", (long)low];
            v[@"difference"] = [NSString stringWithFormat:@"%ld mV", (long)(high-low)];
            v[@"maxIndex"] = @(highIndex).stringValue; v[@"minIndex"] = @(lowIndex).stringValue;
        }
    }
    v[@"ambient"] = number(71, 250, 1, -40, @"℃");
    v[@"mosTemp"] = number(70, 250, 1, -40, @"℃");
    // 不排除 0℃ 探针，不猜测哪些探针已安装。
    NSInteger highT = -41, lowT = 211; BOOL validT = YES;
    for (id temperature in self.probeTemperatures) {
        if (temperature == NSNull.null) { validT = NO; break; }
        highT = MAX(highT, [temperature integerValue]); lowT = MIN(lowT, [temperature integerValue]);
    }
    v[@"maxTemp"] = validT ? [NSString stringWithFormat:@"%ld℃", (long)highT] : @"—";
    v[@"minTemp"] = validT ? [NSString stringWithFormat:@"%ld℃", (long)lowT] : @"—";
    for (NSUInteger i=0; i<6; i++) { v[[NSString stringWithFormat:@"probe%lu", (unsigned long)i]] = number(40+i, 250, 1, -40, @"℃"); }
    for (NSUInteger i=0; i<5; i++) {
        NSInteger raw = r[81+i].integerValue;
        v[[NSString stringWithFormat:@"mos%lu", (unsigned long)i]] = raw == 0 ? @"断开" : raw == 1 ? @"闭合" : [NSString stringWithFormat:@"未知(%ld)", (long)raw];
    }
    v[@"cycles"] = number(54, 65533, 1, 0, @"次");
    return v.copy;
}

- (NSString *)balanceTextForCell:(NSUInteger)index {
    // D159/160 已保留，但缺少“位→电芯”的映射，不能把未知状态显示为未均衡。
    return @"待确认";
}

- (NSArray<NSDictionary<NSString *,NSString *> *> *)alarmRows {
    NSArray *names = @[@"充电过压报警", @"放电欠压报警", @"充电过流报警", @"放电过流报警1", @"放电过流报警2", @"短路报警", @"充电高温报警", @"充电低温报警", @"放电高温报警", @"放电低温报警", @"压差异常报警", @"DC-DC温度报警", @"SOC低报警", @"绝缘报警"];
    NSMutableArray *rows = NSMutableArray.array;
    for (NSUInteger bit=0; bit<names.count; bit++) {
        BOOL unknown = self.faultBits >= 0xFFFE;
        BOOL active = (self.faultBits & (1U << bit)) != 0;
        [rows addObject:@{@"name":names[bit], @"state":unknown ? @"未知" : active ? @"报警" : @"正常"}];
    }
    return rows.copy;
}

- (NSString *)diagnosticText {
    if (self.rawRegisters.count != 86) { return @"实时区未读取"; }
    NSMutableArray *lines = NSMutableArray.array;
    [lines addObject:@"【实时区解析】D96～D181，86个寄存器，CRC通过；字节位置从完整响应0开始计数"];
    NSDictionary *descriptions = @{@142:@"SOC：高字节真实值，低字节显示值", @143:@"SOH (%)", @146:@"电流：raw×0.1−1000 A", @147:@"总电压：raw×0.1 V", @150:@"循环次数", @159:@"均衡原始字1：位映射待确认", @160:@"均衡原始字2：位映射待确认", @161:@"工作状态原始字1：枚举待确认", @162:@"工作状态原始字2：枚举待确认", @163:@"报警位图：当前按Ver1.4主表，附录地址冲突待确认", @164:@"报警等级", @166:@"MOS温度：raw−40 ℃", @167:@"环境温度：raw−40 ℃"};
    for (NSUInteger i=0; i<86; i++) {
        NSUInteger address = 96+i; uint16_t raw = self.rawRegisters[i].unsignedShortValue;
        NSString *meaning = descriptions[@(address)] ?: @"保留原始值";
        if (address>=104 && address<=135) { meaning = [NSString stringWithFormat:@"电芯%lu：%u mV", (unsigned long)address-103, raw]; }
        if (address>=136 && address<=141) { meaning = [NSString stringWithFormat:@"探针%lu：%@", (unsigned long)address-135, raw<=250 ? [NSString stringWithFormat:@"%d ℃", raw-40] : @"无效/异常"]; }
        if (address>=177) { meaning = @"MOS：0断开/1闭合，其他未知"; }
        [lines addObject:[NSString stringWithFormat:@"D%lu(0x%04lX) | 字节[%lu..%lu]=%02X %02X | 原始=%u(0x%04X) | %@", (unsigned long)address, (unsigned long)address, (unsigned long)(4+2*i), (unsigned long)(5+2*i), raw>>8, raw&255, raw, raw, meaning]];
    }
    [lines addObject:@"最高/最低电压及串号：按D335配置串数，从本次单节电压计算；压差=最高−最低。探针最高/最低：计算全部6路，保留0℃，不推断探针数量。功率=总电压×电流。剩余时间暂未确认来源。"];
    return [lines componentsJoinedByString:@"\n"];
}

@end
