#import <Foundation/Foundation.h>
#import "../BMSModbusDemo/Protocol/BMSModbusCodec.h"
#import "../BMSModbusDemo/Transport/BMSMockTransport.h"
#import "../BMSModbusDemo/Client/BMSClient.h"

// 手动注入通知，覆盖真实BLE任意分包边界，不依赖模拟器的帧生成规则。
@interface BMSCaptureTransport : NSObject <BMSByteTransport>
@property (nonatomic, copy) BMSTransportStateHandler stateHandler;
@property (nonatomic, copy) BMSTransportReceiveHandler receiveHandler;
@property (nonatomic, copy) BMSTransportErrorHandler errorHandler;
@property (nonatomic, getter=isConnected) BOOL connected;
@property (nonatomic, strong) NSData *sent;
@end
@implementation BMSCaptureTransport
- (void)connect { self.connected = YES; }
- (void)disconnect { self.connected = NO; }
- (void)sendData:(NSData *)data { self.sent = data; }
@end

static NSData *Hex(NSString *string) {
    NSMutableData *data = NSMutableData.data;
    for (NSString *part in [string componentsSeparatedByString:@" "]) {
        if (!part.length) { continue; }
        unsigned int value = 0;
        [[NSScanner scannerWithString:part] scanHexInt:&value];
        uint8_t byte = value;
        [data appendBytes:&byte length:1];
    }
    return data;
}

static void WaitUntil(BOOL *finished) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!*finished && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    NSCAssert(*finished, @"异步模拟测试超时");
}

int main(void) {
    @autoreleasepool {
        NSData *test = [@"123456789" dataUsingEncoding:NSASCIIStringEncoding];
        NSCAssert([BMSModbusCodec modbusCRC16ForData:test] == 0x4B37, @"MODBUS CRC 测试失败");
        NSCAssert([BMSModbusCodec xmodemCRC16ForData:test] == 0x31C3, @"XMODEM CRC 测试失败");

        NSError *error;
        NSData *request = [BMSModbusCodec readRunningParametersWithAddress:1 start:0 count:3 error:&error];
        NSCAssert(request && [BMSModbusCodec validateFrame:request error:&error], @"请求帧生成失败");
        NSCAssert([[BMSModbusCodec hexStringFromData:request] isEqualToString:@"01 04 00 00 00 03 B0 0B"], @"请求帧字节不符合预期");
        NSData *heartbeat = [BMSModbusCodec heartbeatWithAddress:1];
        NSCAssert(heartbeat.length == 6 && [BMSModbusCodec validateFrame:heartbeat error:&error], @"心跳帧生成失败");
        NSData *realtimeRequest = [BMSModbusCodec readRunningParametersWithAddress:1 start:0x0060 count:86 error:&error];
        NSCAssert([[BMSModbusCodec hexStringFromData:realtimeRequest] isEqualToString:@"01 04 00 60 00 56 70 2A"], @"旧APP实时区请求帧错误");

        BMSMockTransport *transport = [[BMSMockTransport alloc] init];
        BMSClient *client = [[BMSClient alloc] initWithTransport:transport];
        __block BOOL connected = NO;
        transport.stateHandler = ^(BOOL value, NSString *message) { connected = value; };
        [transport connect];
        WaitUntil(&connected);

        __block BOOL parametersFinished = NO;
        [client readRunningParametersFrom:0 count:3 completion:^(NSArray *values, NSError *readError) {
            NSCAssert(!readError && values.count == 3, @"参数读取失败");
            NSCAssert([values[0] unsignedIntegerValue] == 520 && [values[1] unsignedIntegerValue] == 10015 && [values[2] unsignedIntegerValue] == 78, @"参数解析错误");
            parametersFinished = YES;
        }];
        WaitUntil(&parametersFinished);

        __block BOOL voltageFinished = NO;
        [client readTotalVoltage:^(NSNumber *voltage, NSError *readError) {
            NSCAssert(!readError && fabs(voltage.doubleValue - 52.0) < 0.001, @"单寄存器总电压读取失败");
            voltageFinished = YES;
        }];
        WaitUntil(&voltageFinished);

        __block BOOL realtimeFinished = NO;
        [client readRealtimeData:^(BMSRealtimeData *data, NSError *readError) {
            NSCAssert(!readError && data, @"实时数据读取失败");
            NSCAssert(fabs(data.totalVoltage - 52.0) < 0.001, @"实时总电压换算错误");
            NSCAssert(fabs(data.totalCurrent - 1.5) < 0.001, @"实时总电流换算错误");
            NSCAssert(data.displaySOC == 78 && data.chargeMOSOn, @"实时SOC或MOS解析错误");
            NSCAssert(data.cellVoltages.count == 32 && data.probeTemperatures.count == 6 && data.rawRegisters.count == 86, @"完整实时区解析错误");
            realtimeFinished = YES;
        }];
        WaitUntil(&realtimeFinished);

        __block BOOL infoFinished = NO;
        [client readDeviceInformation:^(NSDictionary *info, NSError *e) {
            NSCAssert(!e && [info[@"software"] isEqual:@"YT_DEMO_software_1.0"] && [info[@"time"] isEqual:@"2026-09-17 18:30:00"], @"设备信息解析失败");
            infoFinished = YES;
        }];
        WaitUntil(&infoFinished);
        __block BOOL commonFinished = NO;
        [client readCommonParameters:^(NSArray *items, NSError *e) {
            NSCAssert(!e && items.count==42 && [items[38][@"value"] doubleValue]==100, @"参数换算失败");
            commonFinished = YES;
        }];
        WaitUntil(&commonFinished);
        __block BOOL writeFinished = NO;
        [client writeCommonParameterAt:338 engineeringValue:80.25 completion:^(id value, NSError *e) {
            NSCAssert(!e && [value doubleValue]==80.25, @"参数写入回读失败");
            writeFinished = YES;
        }];
        WaitUntil(&writeFinished);
        __block BOOL invalidRejected = NO;
        [client writeCommonParameterAt:338 engineeringValue:80.251 completion:^(id value, NSError *e) { invalidRejected = e != nil; }];
        NSCAssert(invalidRejected, @"不允许丢失精度后写入");

        __block BOOL historyFinished = NO;
        [client readHistoryRecordAtIndex:0 completion:^(NSDictionary *record, NSError *historyError) {
            NSCAssert(!historyError && [record[@"cellVoltages"] count] == 32, @"历史记录解析失败");
            NSCAssert([record[@"time"] isEqual:@"2026-09-10 11:55:36"], @"历史时间应按二进制而非十六进制显示");
            NSCAssert(fabs([record[@"totalVoltage"] doubleValue] - 520.0) < 0.001, @"历史总电压错误");
            NSCAssert(fabs([record[@"totalCurrent"] doubleValue] - 5.0) < 0.001, @"历史总电流错误");
            historyFinished = YES;
        }];
        WaitUntil(&historyFinished);

        // 截图4，18:13:52参数区响应，保留设备原始CRC 64 43。
        NSData *captured = Hex(@"01 04 00 54 0e d8 00 00 0e 10 08 98 00 00 09 60 05 dc 03 e8 03 20 00 01 0c e4 00 1e 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 03 e8 07 08 00 6e 00 5f 00 23 00 2d 00 78 00 69 00 0a 00 1e 00 00 00 00 00 28 00 28 00 08 00 01 00 00 27 10 00 01 00 01 00 00 64 43");
        NSCAssert(captured.length == 90 && [BMSModbusCodec validateFrame:captured error:&error], @"截图报文转录/CRC错误");
        BMSCaptureTransport *capture = [BMSCaptureTransport new];
        BMSClient *captureClient = [[BMSClient alloc] initWithTransport:capture];
        // 遍历每个切割位置，包含把两个长度字节、寄存器以及CRC拆开的情况。
        for (NSUInteger split = 1; split < captured.length; split++) {
            __block BOOL done = NO;
            [captureClient readRunningParametersFrom:0x012C count:42 completion:^(NSArray *words, NSError *e) {
                NSCAssert(!e && words.count == 42 && [words[0] intValue] == 3800 && [words[2] intValue] == 3600, @"抓包解析错误");
                done = YES;
            }];
            NSCAssert([[BMSModbusCodec hexStringFromData:capture.sent] isEqualToString:@"01 04 01 2C 00 2A B1 E0"], @"参数请求与旧APP不一致");
            capture.receiveHandler([captured subdataWithRange:NSMakeRange(0, split)]);
            NSCAssert(!done, @"分包尚未完成不应解析");
            capture.receiveHandler([captured subdataWithRange:NSMakeRange(split, captured.length - split)]);
            NSCAssert(done, @"完整分包未完成解析");
        }
        __block BOOL rejected = NO;
        [captureClient readRunningParametersFrom:0x012C count:42 completion:^(id value, NSError *e) { rejected = e != nil; }];
        NSMutableData *damaged = captured.mutableCopy;
        ((uint8_t *)damaged.mutableBytes)[10] ^= 1;
        capture.receiveHandler(damaged);
        NSCAssert(rejected, @"CRC损坏必须拒绝");
        __block BOOL echoRejected = NO;
        [captureClient setRunningParameterAt:338 value:8000 completion:^(id value, NSError *e) { echoRejected = e != nil; }];
        capture.receiveHandler([BMSModbusCodec writeRunningParameterWithAddress:1 registerAddress:338 value:8001]);
        NSCAssert(echoRejected, @"CRC正确但写值不同的响应必须拒绝");
        NSLog(@"BMS protocol smoke tests passed");
    }
    return 0;
}
