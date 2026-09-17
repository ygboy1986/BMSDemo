#import "BMSClient.h"
#import <math.h>
#import "../Protocol/BMSModbusCodec.h"

@interface BMSClient ()
@property (nonatomic, readwrite) id<BMSByteTransport> transport;
@property (nonatomic, strong) NSMutableData *receiveBuffer;
@property (nonatomic, copy, nullable) BMSClientCompletion pendingCompletion;
@property (nonatomic) uint8_t pendingFunction;
@property (nonatomic) uint16_t pendingCount;
@property (nonatomic) NSUInteger explicitExpectedLength;
@property (nonatomic) NSUInteger requestGeneration;
@property (nonatomic, copy) NSData *pendingFrame;
@end

@implementation BMSClient

// 旧APP抓包：01 04 00 60 00 56 70 2A，读取整个实时区。
static const uint16_t BMSRealtimeStartRegister = 0x0060;
static const uint16_t BMSRealtimeRegisterCount = 86;

- (BOOL)isBusy { return self.pendingCompletion != nil; }

- (void)readDeviceInformation:(BMSClientCompletion)completion {
    [self readRunningParametersFrom:0 count:50 completion:^(NSArray<NSNumber *> *values, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSMutableData *bytes = NSMutableData.data;
        for (NSNumber *word in values) {
            uint8_t pair[] = {(uint8_t)(word.unsignedShortValue >> 8), (uint8_t)word.unsignedShortValue};
            [bytes appendBytes:pair length:2];
        }
        NSString *(^stringAt)(NSUInteger, NSUInteger) = ^NSString *(NSUInteger start, NSUInteger length) {
            NSData *part = [bytes subdataWithRange:NSMakeRange(start, length)];
            NSString *text = [[NSString alloc] initWithData:part encoding:NSASCIIStringEncoding] ?: @"无法解码";
            return [[text stringByReplacingOccurrencesOfString:@"\0" withString:@""] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        };
        const uint8_t *b = bytes.bytes;
        // 主表硬件版本占15个寄存器，即30字节（说明列“20字节”与数量冲突，以地址边界为准）。
        NSString *time = [NSString stringWithFormat:@"%04u-%02u-%02u %02u:%02u:%02u", 2000+b[90], b[91], b[92], b[93], b[94], b[95]];
        if (b[91] < 1 || b[91] > 12 || b[92] < 1 || b[92] > 31 || b[93] > 23 || b[94] > 59 || b[95] > 59) { time = @"设备时间未设置/无效"; }
        completion(@{@"software":stringAt(0,40), @"hardware":stringAt(40,30), @"identifier":stringAt(70,20), @"time":time, @"zeroCurrent":@((int16_t)values[48].unsignedShortValue), @"selfTest":values[49]}, nil);
    }];
}

/// 与Ver1.4主表D300~D341逐项对应；range为原始值范围，scale/offset用于工程量换算。
- (NSArray<NSDictionary *> *)commonParameterDefinitions {
    NSArray *names = @[@"充电过压保护", @"充电过压延时", @"充电过压恢复", @"放电欠压保护", @"放电欠压延时档位", @"放电欠压恢复", @"单节失效电压", @"失效压差保护", @"失效压差恢复", @"均衡模式", @"均衡电压", @"均衡启动压差", @"充电过流档位", @"充电过流延时档位", @"放电过流1档位", @"放电过流1延时档位", @"放电过流2档位", @"放电过流2延时档位", @"短路电流档位", @"短路延时档位", @"小电流开关", @"放电最小电流", @"无电流关机时间", @"充电高温保护", @"充电高温恢复", @"充电低温保护", @"充电低温恢复", @"放电高温保护", @"放电高温恢复", @"放电低温保护", @"放电低温恢复", @"充电校准倍率", @"放电校准倍率", @"温度A校准", @"温度B校准", @"电池串数", @"电池类型(0三元/1铁锂)", @"采样电阻", @"设计容量", @"休眠唤醒开关", @"循环次数", @"剩余容量"];
    NSMutableArray *items = NSMutableArray.array;
    for (NSUInteger i=0; i<names.count; i++) {
        NSInteger min=0,max=15; double scale=1,offset=0; NSString *unit=@"档";
        if (i==0 || i==2 || i==3 || i==5 || i==6 || i==10) { min=1600; max=4300; unit=@"mV"; }
        else if (i==7 || i==8 || i==11) { min=1; max=2000; unit=@"mV"; }
        else if (i==9 || i==20 || i==36 || i==39) { max=1; unit=@""; }
        else if (i==1) { unit=@"s"; }
        else if (i==21) { min=1; max=5000; unit=@"mA"; }
        else if (i==22) { min=1; max=120; unit=@"s"; }
        else if ((i>=23 && i<=30) || i==33 || i==34) { max=250; offset=-40; unit=@"℃"; }
        else if (i==31 || i==32) { max=255; scale=0.1; unit=@"倍"; }
        else if (i==35 || i==37) { min=1; max=255; unit=i==35 ? @"串" : @"mΩ"; }
        else if (i==38 || i==41) { min=1; max=65530; scale=0.01; unit=@"Ah"; }
        else if (i==40) { max=65535; unit=@"次"; }
        [items addObject:@{@"address":@(300+i), @"name":names[i], @"unit":unit, @"min":@(min), @"max":@(max), @"scale":@(scale), @"offset":@(offset)}];
    }
    return items;
}

- (void)readCommonParameters:(BMSClientCompletion)completion {
    [self readRunningParametersFrom:300 count:42 completion:^(NSArray *words, NSError *error) {
        if (error) { completion(nil,error); return; }
        NSMutableArray *result = NSMutableArray.array;
        NSArray *definitions = [self commonParameterDefinitions];
        for (NSUInteger i=0; i<42; i++) {
            NSMutableDictionary *item = [definitions[i] mutableCopy];
            item[@"raw"] = words[i];
            item[@"value"] = @([words[i] doubleValue]*[item[@"scale"] doubleValue]+[item[@"offset"] doubleValue]);
            item[@"valid"] = @([words[i] integerValue]>=[item[@"min"] integerValue] && [words[i] integerValue]<=[item[@"max"] integerValue]);
            [result addObject:item];
        }
        completion(result,nil);
    }];
}

- (void)writeCommonParameterAt:(uint16_t)address engineeringValue:(double)value completion:(BMSClientCompletion)completion {
    if (address<300 || address>341 || !isfinite(value)) { completion(nil,[self errorWithCode:40 message:@"参数地址或数值无效"]); return; }
    NSDictionary *item = [self commonParameterDefinitions][address-300];
    double raw = (value-[item[@"offset"] doubleValue])/[item[@"scale"] doubleValue];
    if (raw<[item[@"min"] doubleValue] || raw>[item[@"max"] doubleValue] || fabs(raw-round(raw))>0.000001) {
        completion(nil,[self errorWithCode:41 message:@"数值超出协议范围或精度不符合要求"]); return;
    }
    uint16_t word = (uint16_t)llround(raw);
    __weak typeof(self) weakSelf = self;
    [self setRunningParameterAt:address value:word completion:^(id result, NSError *error) {
        if (error) { completion(nil,error); return; }
        [weakSelf readRunningParametersFrom:address count:1 completion:^(NSArray *words, NSError *readError) {
            if (readError) { completion(nil,readError); return; }
            if ([words[0] unsignedShortValue]!=word) { completion(nil,[weakSelf errorWithCode:42 message:@"写入后回读不一致，请重新读取设备参数"]); return; }
            completion(@(value),nil);
        }];
    }];
}

- (instancetype)initWithTransport:(id<BMSByteTransport>)transport {
    if (self = [super init]) {
        _transport = transport;
        _slaveAddress = 1;
        _responseTimeout = 3.0;
        _receiveBuffer = NSMutableData.data;
        __weak typeof(self) weakSelf = self;
        transport.receiveHandler = ^(NSData *data) { [weakSelf consumeData:data]; };
        transport.errorHandler = ^(NSError *error) {
            [weakSelf log:[NSString stringWithFormat:@"蓝牙错误：%@", error.localizedDescription]];
            [weakSelf finishWithResult:nil error:error];
        };
    }
    return self;
}

- (void)readRealtimeData:(BMSClientCompletion)completion {
    [self readRunningParametersFrom:BMSRealtimeStartRegister count:BMSRealtimeRegisterCount completion:^(NSArray<NSNumber *> *values, NSError *readError) {
        if (readError) { completion(nil, readError); return; }
        NSError *parseError;
        // 模型的起点为0x008E，位于完整实时区的第46个偏移处。
        BMSRealtimeData *data = [[BMSRealtimeData alloc] initWithFullRegisters:values error:&parseError];
        completion(data, parseError);
    }];
}

- (void)readTotalVoltage:(BMSClientCompletion)completion {
    // 保持功能码、地址和CRC规则不变，仅将读取数量缩小为1，不发送握手或其他探测命令。
    [self readRunningParametersFrom:0x0093 count:1 completion:^(NSArray<NSNumber *> *values, NSError *readError) {
        if (readError) { completion(nil, readError); return; }
        uint16_t raw = values.firstObject.unsignedShortValue;
        if (raw > 60000) {
            completion(nil, [self errorWithCode:31 message:[NSString stringWithFormat:@"总电压无效或异常：原始值0x%04X", raw]]);
            return;
        }
        completion(@(raw / 10.0), nil);
    }];
}

- (void)readRunningStatusFrom:(uint16_t)start count:(uint16_t)count completion:(BMSClientCompletion)completion {
    if (self.pendingCompletion) {
        completion(nil, [self errorWithCode:21 message:@"上一条命令尚未完成，请稍后重试"]); return;
    }
    NSError *error;
    NSData *frame = [BMSModbusCodec readRunningStatusWithAddress:self.slaveAddress start:start count:count error:&error];
    if (!frame) { completion(nil, error); return; }
    self.pendingCount = count;
    [self sendFrame:frame function:BMSFunctionCodeReadRunningStatus completion:completion];
}

- (void)readRunningParametersFrom:(uint16_t)start count:(uint16_t)count completion:(BMSClientCompletion)completion {
    // 忙碌时不能覆盖 pendingCount，否则重复点击会改变正在等待响应的解析长度。
    if (self.pendingCompletion) {
        completion(nil, [self errorWithCode:21 message:@"上一条命令尚未完成，请稍后重试"]); return;
    }
    NSError *error;
    NSData *frame = [BMSModbusCodec readRunningParametersWithAddress:self.slaveAddress start:start count:count error:&error];
    if (!frame) { completion(nil, error); return; }
    self.pendingCount = count;
    [self sendFrame:frame function:BMSFunctionCodeReadRunningParameters completion:completion];
}

- (void)setRunningStatusAt:(uint16_t)registerAddress on:(BOOL)on completion:(BMSClientCompletion)completion {
    NSData *frame = [BMSModbusCodec writeRunningStatusWithAddress:self.slaveAddress registerAddress:registerAddress on:on];
    [self sendFrame:frame function:BMSFunctionCodeWriteRunningStatus completion:completion];
}

- (void)setRunningParameterAt:(uint16_t)registerAddress value:(uint16_t)value completion:(BMSClientCompletion)completion {
    NSData *frame = [BMSModbusCodec writeRunningParameterWithAddress:self.slaveAddress registerAddress:registerAddress value:value];
    [self sendFrame:frame function:BMSFunctionCodeWriteRunningParameter completion:completion];
}

- (void)readHistoryCount:(BMSClientCompletion)completion {
    [self sendFrame:[BMSModbusCodec readHistoryCountWithAddress:self.slaveAddress] function:BMSFunctionCodeReadHistoryCount completion:completion];
}

- (void)readHistoryRecordAtIndex:(uint16_t)index completion:(BMSClientCompletion)completion {
    [self sendFrame:[BMSModbusCodec readHistoryRecordWithAddress:self.slaveAddress index:index] function:BMSFunctionCodeReadHistoryRecord completion:completion];
}

- (void)announceFirmware:(NSData *)firmware type:(uint8_t)type version:(uint16_t)version completion:(BMSClientCompletion)completion {
    [self sendFrame:[BMSModbusCodec firmwareIndexWithAddress:self.slaveAddress type:type version:version firmware:firmware] function:BMSFunctionCodeFirmwareIndex completion:completion];
}

- (void)sendFirmwareChunk:(NSData *)chunk type:(uint8_t)type version:(uint16_t)version offset:(uint32_t)offset completion:(BMSClientCompletion)completion {
    NSError *error;
    NSData *frame = [BMSModbusCodec firmwareChunkWithAddress:self.slaveAddress type:type version:version offset:offset data:chunk error:&error];
    if (!frame) { completion(nil, error); return; }
    [self sendFrame:frame function:BMSFunctionCodeFirmwareData completion:completion];
}

- (void)queryFirmwareStatusForType:(uint8_t)type completion:(BMSClientCompletion)completion {
    [self sendFrame:[BMSModbusCodec firmwareStatusWithAddress:self.slaveAddress type:type] function:BMSFunctionCodeFirmwareStatus completion:completion];
}

- (void)sendHeartbeat:(BMSClientCompletion)completion {
    [self sendFrame:[BMSModbusCodec heartbeatWithAddress:self.slaveAddress] function:BMSFunctionCodeHeartbeat completion:completion];
}

- (void)sendRawFrame:(NSData *)frame expectedLength:(NSUInteger)expectedLength completion:(BMSClientCompletion)completion {
    if (self.pendingCompletion) {
        completion(nil, [self errorWithCode:21 message:@"上一条命令尚未完成，请稍后重试"]); return;
    }
    if (frame.length < 2) {
        completion(nil, [self errorWithCode:20 message:@"原始帧长度不足"]); return;
    }
    self.explicitExpectedLength = expectedLength;
    const uint8_t *bytes = frame.bytes;
    [self sendFrame:frame function:bytes[1] completion:completion];
}

- (void)sendFrame:(NSData *)frame function:(uint8_t)function completion:(BMSClientCompletion)completion {
    if (self.pendingCompletion) {
        completion(nil, [self errorWithCode:21 message:@"上一条命令尚未完成，请稍后重试"]); return;
    }
    self.pendingCompletion = completion;
    self.pendingFunction = function;
    self.pendingFrame = frame;
    self.requestGeneration += 1;
    NSUInteger generation = self.requestGeneration;
    [self.receiveBuffer setLength:0];
    [self log:[NSString stringWithFormat:@">> %@", [BMSModbusCodec hexStringFromData:frame]]];
    [self.transport sendData:frame];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.responseTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !self.pendingCompletion || self.requestGeneration != generation) { return; }
        NSString *message = [NSString stringWithFormat:@"等待功能码 0x%02X 响应超时（%.1f秒）", function, self.responseTimeout];
        [self log:[NSString stringWithFormat:@"!! %@", message]];
        [self finishWithResult:nil error:[self errorWithCode:24 message:message]];
    });
}

- (void)consumeData:(NSData *)data {
    // 每个通知分包也记录，便于区分完全无响应与收到不完整响应。
    [self log:[NSString stringWithFormat:@"RX分包（%lu字节）：%@", (unsigned long)data.length, [BMSModbusCodec hexStringFromData:data]]];
    if (!self.pendingCompletion) { return; }
    [self.receiveBuffer appendData:data];
    if (self.receiveBuffer.length > 4096) {
        [self finishWithResult:nil error:[self errorWithCode:33 message:@"接收数据超出上限"]]; return;
    }
    if (!self.explicitExpectedLength && self.pendingFunction == BMSFunctionCodeReadRunningParameters && self.receiveBuffer.length >= 4) {
        const uint8_t *header = self.receiveBuffer.bytes;
        if (header[1] == BMSFunctionCodeReadRunningParameters && ((header[2] << 8) | header[3]) != self.pendingCount * 2) {
            [self finishWithResult:nil error:[self errorWithCode:32 message:@"寄存器响应的两字节长度与请求数量不匹配"]]; return;
        }
    }
    NSUInteger expected = [self expectedResponseLength];
    if (expected == 0 || self.receiveBuffer.length < expected) { return; }
    NSData *frame = [self.receiveBuffer subdataWithRange:NSMakeRange(0, expected)];
    [self.receiveBuffer replaceBytesInRange:NSMakeRange(0, expected) withBytes:NULL length:0];
    [self log:[NSString stringWithFormat:@"<< %@", [BMSModbusCodec hexStringFromData:frame]]];

    NSError *error;
    if (![BMSModbusCodec validateFrame:frame error:&error]) { [self finishWithResult:nil error:error]; return; }
    const uint8_t *bytes = frame.bytes;
    if (bytes[0] != self.slaveAddress) { [self finishWithResult:nil error:[self errorWithCode:22 message:@"响应设备地址不匹配"]]; return; }
    if (bytes[1] & 0x80) { [self finishWithResult:nil error:[self errorWithCode:bytes[2] message:[NSString stringWithFormat:@"BMS 返回异常码 0x%02X", bytes[2]]]]; return; }
    if (bytes[1] != self.pendingFunction) { [self finishWithResult:nil error:[self errorWithCode:23 message:@"响应功能码不匹配"]]; return; }
    if ((self.pendingFunction == BMSFunctionCodeWriteRunningParameter || self.pendingFunction == BMSFunctionCodeWriteRunningStatus) && ![frame isEqualToData:self.pendingFrame]) {
        [self finishWithResult:nil error:[self errorWithCode:43 message:@"写入响应的地址或数值与请求不一致"]]; return;
    }
    if (self.pendingFunction == BMSFunctionCodeReadHistoryRecord && self.pendingFrame.length >= 4 && memcmp(bytes+2, (const uint8_t *)self.pendingFrame.bytes+2, 2) != 0) {
        [self finishWithResult:nil error:[self errorWithCode:44 message:@"历史记录响应索引与请求不一致"]]; return;
    }
    if (!self.explicitExpectedLength && self.pendingFunction == BMSFunctionCodeReadRunningParameters && ((bytes[2] << 8) | bytes[3]) != self.pendingCount * 2) {
        [self finishWithResult:nil error:[self errorWithCode:32 message:@"寄存器响应字节数与请求数量不匹配"]]; return;
    }
    [self finishWithResult:self.explicitExpectedLength ? frame : [self parseFrame:frame] error:nil];
}

- (NSUInteger)expectedResponseLength {
    if (self.explicitExpectedLength) { return self.explicitExpectedLength; }
    if (self.receiveBuffer.length >= 2) {
        const uint8_t *bytes = self.receiveBuffer.bytes;
        if (bytes[1] & 0x80) { return 5; }
    }
    switch (self.pendingFunction) {
        case BMSFunctionCodeReadRunningStatus:
            if (self.receiveBuffer.length < 3) { return 0; }
            return ((const uint8_t *)self.receiveBuffer.bytes)[2] + 5;
        case BMSFunctionCodeReadRunningParameters: {
            // 厂家0x04使用16位大端字节数：01 04 00 AC + 172字节 + CRC。
            if (self.receiveBuffer.length < 4) { return 0; }
            const uint8_t *b = self.receiveBuffer.bytes;
            return ((b[2] << 8) | b[3]) + 6;
        }
        case BMSFunctionCodeReadHistoryCount:
        case BMSFunctionCodeFirmwareStatus:
        case BMSFunctionCodeHeartbeat: return 6;
        case BMSFunctionCodeReadHistoryRecord: return 104;
        case BMSFunctionCodeFirmwareIndex:
        case BMSFunctionCodeFirmwareData: return 13;
        default: return 8;
    }
}

- (id)parseFrame:(NSData *)frame {
    const uint8_t *bytes = frame.bytes;
    switch (self.pendingFunction) {
        case BMSFunctionCodeReadRunningStatus: {
            NSMutableArray *states = [NSMutableArray arrayWithCapacity:self.pendingCount];
            for (uint16_t i = 0; i < self.pendingCount; i++) { [states addObject:@((bytes[3 + i / 8] >> (i % 8)) & 1)]; }
            return states;
        }
        case BMSFunctionCodeReadRunningParameters: {
            NSMutableArray *values = [NSMutableArray arrayWithCapacity:self.pendingCount];
            for (uint16_t i = 0; i < self.pendingCount; i++) { [values addObject:@((uint16_t)((bytes[4 + i * 2] << 8) | bytes[5 + i * 2]))]; }
            return values;
        }
        case BMSFunctionCodeReadHistoryCount: return @((uint16_t)((bytes[2] << 8) | bytes[3]));
        case BMSFunctionCodeReadHistoryRecord: return [self parseHistoryFrame:frame];
        case BMSFunctionCodeFirmwareStatus: return @{ @"type": @(bytes[2]), @"success": @(bytes[3] == 0) };
        case BMSFunctionCodeFirmwareData: return @((uint16_t)((bytes[9] << 8) | bytes[10]));
        default: return frame;
    }
}

- (NSDictionary *)parseHistoryFrame:(NSData *)frame {
    const uint8_t *b = frame.bytes;
    NSUInteger p = 2;
    uint16_t index = (uint16_t)((b[p] << 8) | b[p + 1]); p += 2;
    NSString *time = [NSString stringWithFormat:@"%04u-%02u-%02u %02u:%02u:%02u", 2000 + b[p], b[p+1], b[p+2], b[p+3], b[p+4], b[p+5]]; p += 6;
    uint8_t event = b[p++];
    uint16_t voltageRaw = (uint16_t)((b[p] << 8) | b[p+1]); p += 2;
    uint16_t currentRaw = (uint16_t)((b[p] << 8) | b[p+1]); p += 2;
    uint8_t soc = b[p++];
    NSMutableArray *cellVoltages = [NSMutableArray arrayWithCapacity:32];
    for (NSInteger i = 0; i < 32; i++) { uint16_t v = (uint16_t)((b[p] << 8) | b[p+1]); p += 2; [cellVoltages addObject:@(v / 1000.0)]; }
    NSMutableArray *temperatures = [NSMutableArray arrayWithCapacity:6];
    for (NSInteger i = 0; i < 6; i++) { [temperatures addObject:@((NSInteger)b[p++] - 40)]; }
    NSInteger mosTemperature = (NSInteger)b[p++] - 40;
    NSInteger ambientTemperature = (NSInteger)b[p++] - 40;
    uint16_t alarms = (uint16_t)((b[p] << 8) | b[p+1]); p += 2;
    NSArray *mosStates = @[@(b[p]), @(b[p+1]), @(b[p+2]), @(b[p+3]), @(b[p+4])];
    return @{ @"index": @(index), @"time": time, @"eventType": @(event),
              @"totalVoltage": @(voltageRaw / 10.0), @"totalCurrent": @(((NSInteger)currentRaw - 10000) / 10.0),
              @"soc": @(soc), @"cellVoltages": cellVoltages, @"temperatures": temperatures,
              @"mosTemperature": @(mosTemperature), @"ambientTemperature": @(ambientTemperature),
              @"alarms": @(alarms), @"mosStates": mosStates };
}

- (void)finishWithResult:(id)result error:(NSError *)error {
    BMSClientCompletion completion = self.pendingCompletion;
    self.pendingCompletion = nil;
    self.pendingFunction = 0;
    self.pendingCount = 0;
    self.explicitExpectedLength = 0;
    [self.receiveBuffer setLength:0];
    if (completion) { completion(result, error); }
}

- (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message {
    return [NSError errorWithDomain:BMSModbusErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

- (void)log:(NSString *)line { if (self.logHandler) { self.logHandler(line); } }

@end
