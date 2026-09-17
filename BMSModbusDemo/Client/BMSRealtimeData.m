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

@end
