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

        // 监控数值映射回归：视频的八路电压作为离线测试输入，不作为App数据源。
        NSMutableArray<NSNumber *> *monitorWords = NSMutableArray.array;
        for (NSUInteger i=0; i<86; i++) { [monitorWords addObject:@0]; }
        NSArray *videoCells = @[@3313,@3298,@3329,@4369,@4770,@799,@3298,@3341];
        for (NSUInteger i=0; i<8; i++) { monitorWords[8+i] = videoCells[i]; }
        for (NSUInteger i=0; i<6; i++) { monitorWords[40+i] = i==0 ? @71 : @40; }
        monitorWords[47]=@100; monitorWords[50]=@10000; monitorWords[51]=@265;
        monitorWords[54]=@1; monitorWords[67]=@0x1003; monitorWords[68]=@2;
        monitorWords[70]=@70; monitorWords[71]=@40; monitorWords[81]=@1;
        BMSRealtimeData *monitor = [[BMSRealtimeData alloc] initWithFullRegisters:monitorWords error:&error];
        NSDictionary *display = [monitor monitorValuesForCellCount:@8];
        NSCAssert([display[@"voltage"] isEqual:@"26.500 V"] && [display[@"current"] isEqual:@"0.000 A"], @"电压/电流展示换算错误");
        NSCAssert([display[@"maxVoltage"] isEqual:@"4770 mV"] && [display[@"minVoltage"] isEqual:@"799 mV"] && [display[@"difference"] isEqual:@"3971 mV"], @"压差必须只计算配置串数，不能包含未配置的零值通道");
        NSCAssert([display[@"maxIndex"] isEqual:@"5"] && [display[@"minIndex"] isEqual:@"6"], @"电芯串号应从1开始");
        NSCAssert([display[@"maxTemp"] isEqual:@"31℃"] && [display[@"minTemp"] isEqual:@"0℃"], @"探针零温度不能丢弃或猜测为未安装");
        NSCAssert([display[@"mos0"] isEqual:@"闭合"] && [display[@"mos4"] isEqual:@"断开"], @"五路MOS映射错误");
        NSArray *alarmRows = [monitor alarmRows];
        NSCAssert(alarmRows.count==14 && [alarmRows[0][@"state"] isEqual:@"报警"] && [alarmRows[1][@"state"] isEqual:@"报警"] && [alarmRows[12][@"state"] isEqual:@"报警"] && [alarmRows[13][@"state"] isEqual:@"正常"], @"报警位图解析错误");
        NSCAssert([[monitor monitorValuesForCellCount:nil][@"maxVoltage"] isEqual:@"—"] && [[monitor monitorValuesForCellCount:@33][@"count"] isEqual:@"—"], @"不能推断缺失或超范围串数");
        NSCAssert([display[@"mode"] isEqual:@"待确认"] && [display[@"remaining"] isEqual:@"—"] && [[monitor balanceTextForCell:0] isEqual:@"待确认"], @"未定义的工作状态或均衡不能伪造");
        monitorWords[8]=@0;
        monitor = [[BMSRealtimeData alloc] initWithFullRegisters:monitorWords error:&error];
        NSCAssert([[monitor monitorValuesForCellCount:@8][@"minVoltage"] isEqual:@"0 mV"], @"有效串数内的0mV必须参与统计");
        monitorWords[8]=@65535; monitorWords[40]=@65534; monitorWords[46]=@0xFFFF;
        monitorWords[47]=@101; monitorWords[50]=@65535; monitorWords[51]=@65534;
        monitorWords[67]=@65535; monitorWords[70]=@251; monitorWords[81]=@2;
        monitor = [[BMSRealtimeData alloc] initWithFullRegisters:monitorWords error:&error];
        display = [monitor monitorValuesForCellCount:@8];
        for (NSString *key in @[@"voltage",@"current",@"power",@"soc",@"soh",@"maxVoltage",@"difference",@"maxTemp",@"mosTemp"]) { NSCAssert([display[key] isEqual:@"—"], @"无效值不得展示为正常数值：%@", key); }
        NSCAssert([display[@"mos0"] isEqual:@"未知(2)"] && [[monitor alarmRows][0][@"state"] isEqual:@"未知"], @"无效MOS/报警不能显示断开或正常");
        NSCAssert([monitor.diagnosticText containsString:@"D163(0x00A3) | 字节[138..139]=FF FF"] && [monitor.diagnosticText containsString:@"枚举待确认"], @"实时日志必须保留准确字节偏移和未确认说明");

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
        // 用户 16:33:24 抓包：D0~D49 设备信息，106 字节，原始 CRC 38 8B。
        NSData *informationCapture = Hex(@"01 04 00 64 51 4d 5f 42 41 30 30 32 35 5f 42 54 5f 38 53 28 42 2e 41 2e 30 30 32 35 29 5f 56 30 2e 30 32 00 20 20 20 20 20 20 20 20 51 4d 5f 42 41 30 30 32 35 5f 42 54 5f 56 31 2e 30 00 20 20 20 20 20 20 20 20 20 20 20 20 32 34 35 30 30 30 30 30 30 30 30 30 30 30 30 30 31 30 30 30 00 00 00 00 00 00 00 00 00 00 38 8b");
        NSCAssert(informationCapture.length==106 && [BMSModbusCodec validateFrame:informationCapture error:nil], @"设备信息抓包长度及CRC错误");
        __block BOOL capturedInformationRead = NO;
        [captureClient readDeviceInformation:^(NSDictionary *info, NSError *e) {
            NSCAssert(!e && [info[@"software"] isEqual:@"QM_BA0025_BT_8S(B.A.0025)_V0.02"] && [info[@"hardware"] isEqual:@"QM_BA0025_BT_V1.0"] && [info[@"identifier"] isEqual:@"24500000000000001000"], @"抓包中的版本和识别码必须准确解码");
            NSCAssert([info[@"time"] isEqual:@"设备时间未设置/无效"], @"全零RTC不得视为有效日期");
            capturedInformationRead = YES;
        }];
        NSCAssert([[BMSModbusCodec hexStringFromData:capture.sent] isEqual:@"01 04 00 00 00 32 71 DF"], @"设备信息请求需与原APP一致");
        capture.receiveHandler(informationCapture);
        NSCAssert(capturedInformationRead, @"设备信息抓包解析未完成");
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
        // 2026-09-26: 客户截图16:57:48与本App日志16:50:01参数包完全一致。
        NSString *fixtureFolder = @"Tests/Fixtures";
        NSString *customerHex = [NSString stringWithContentsOfFile:[fixtureFolder stringByAppendingPathComponent:@"customer-20260926-165748-parameters.hex"] encoding:NSUTF8StringEncoding error:nil];
        NSString *ourHex = [NSString stringWithContentsOfFile:[fixtureFolder stringByAppendingPathComponent:@"ours-20260926-165001-parameters.hex"] encoding:NSUTF8StringEncoding error:nil];
        NSCAssert(customerHex.length && ourHex.length, @"请从项目根目录运行测试，抓包夹具必须存在");
        NSData *customerParameters = Hex([customerHex stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]);
        NSData *ourParameters = Hex([ourHex stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]);
        NSCAssert(customerParameters.length==90 && [customerParameters isEqual:ourParameters] && [BMSModbusCodec validateFrame:customerParameters error:nil], @"两App原始参数响应必须逐字节相同且CRC有效");
        __block BOOL comparedParametersRead = NO;
        [captureClient readCommonParameters:^(NSArray *items, NSError *e) {
            NSCAssert(!e && items.count==42, @"对比抓包解码失败");
            NSDictionary *expected = @{@300:@3800, @302:@3600, @303:@2200, @305:@2400, @310:@3400, @311:@30, @323:@70, @324:@55, @325:@(-5), @326:@5, @327:@80, @328:@65, @329:@(-30), @330:@(-10), @336:@1, @338:@100};
            for (NSNumber *address in expected) {
                NSDictionary *item = items[address.integerValue-300];
                NSCAssert([item[@"value"] doubleValue]==[expected[address] doubleValue], @"抓包真实值不得为了匹配客户页面预设而更改倍率/偏移");
            }
            NSCAssert([items[0][@"raw"] intValue]==0x0ED8 && [items[23][@"raw"] intValue]==0x006E, @"保留原始字便于定位差异");
            comparedParametersRead = YES;
        }];
        capture.receiveHandler(customerParameters);
        NSCAssert(comparedParametersRead, @"客户参数包未完成解析");
        // 产品信息使用本次设备响应中的类型、容量和电压，而非本地类型预设。
        __block BOOL productRead = NO;
        [captureClient readCommonParameters:^(NSArray *items, NSError *e) {
            NSCAssert(!e && [items[36][@"raw"] intValue]==1 && [items[38][@"value"] doubleValue]==100 && [items[0][@"value"] intValue]==3800, @"铁锂设备参数应来自实际响应");
            productRead = YES;
        }];
        capture.receiveHandler(captured);
        NSCAssert(productRead, @"产品参数读取未完成");
        NSMutableData *nextPayload = [[captured subdataWithRange:NSMakeRange(2, captured.length-4)] mutableCopy];
        uint8_t *nextBytes = nextPayload.mutableBytes;
        nextBytes[2] = 0x10; nextBytes[3] = 0x68; // 4200 mV
        nextBytes[2+36*2] = 0; nextBytes[3+36*2] = 0; // 三元锂
        nextBytes[2+38*2] = 0x1F; nextBytes[3+38*2] = 0x40; // 80 Ah
        NSData *nextFrame = [BMSModbusCodec frameWithAddress:1 function:BMSFunctionCodeReadRunningParameters payload:nextPayload];
        __block BOOL nextRead = NO;
        [captureClient readCommonParameters:^(NSArray *items, NSError *e) {
            NSCAssert(!e && [items[36][@"raw"] intValue]==0 && [items[38][@"value"] doubleValue]==80 && [items[0][@"value"] intValue]==4200, @"切换设备读取不能沿用上台设备的数据");
            nextRead = YES;
        }];
        capture.receiveHandler(nextFrame);
        NSCAssert(nextRead, @"切换设备参数读取未完成");
        __block NSUInteger cancelledCalls = 0;
        [captureClient readCommonParameters:^(id value, NSError *e) { NSCAssert(!value && e, @"断开应失败而不是返回旧值"); cancelledCalls++; }];
        capture.receiveHandler([captured subdataWithRange:NSMakeRange(0, 10)]);
        [captureClient cancelPendingRequest];
        NSCAssert(!captureClient.isBusy && cancelledCalls==1, @"断开后必须释放忙碌状态");
        capture.receiveHandler([captured subdataWithRange:NSMakeRange(10, captured.length-10)]);
        __block BOOL afterReconnect = NO;
        [captureClient readCommonParameters:^(NSArray *items, NSError *e) { NSCAssert(!e && items.count==42, @"旧分包不得污染重连读取"); afterReconnect = YES; }];
        capture.receiveHandler(nextFrame);
        NSCAssert(afterReconnect && cancelledCalls==1, @"重连读取应成功且旧回调只触发一次");
        // 电芯类型切换：写 D336 -> 单项回读 -> 完整参数回读，完成之前不能报成功。
        capture.connected = YES;
        for (NSNumber *type in @[@0, @1]) {
            __block BOOL switched = NO;
            [captureClient changeBatteryType:type.integerValue completion:^(NSArray *items, NSError *e) {
                NSCAssert(!e && [items[36][@"raw"] isEqual:type] && items.count==42, @"必须返回完整设备参数"); switched = YES;
            }];
            NSData *writeFrame = [BMSModbusCodec writeRunningParameterWithAddress:1 registerAddress:336 value:type.unsignedShortValue];
            NSCAssert([capture.sent isEqual:writeFrame] && !switched, @"必须写 D336，不允许仅改变本地显示");
            capture.receiveHandler(writeFrame);
            NSData *readTypeFrame = [BMSModbusCodec readRunningParametersWithAddress:1 start:336 count:1 error:nil];
            NSCAssert([capture.sent isEqual:readTypeFrame] && !switched, @"写入回显不能代替回读校验");
            uint8_t singlePayload[] = {0, 2, 0, type.unsignedCharValue};
            capture.receiveHandler([BMSModbusCodec frameWithAddress:1 function:BMSFunctionCodeReadRunningParameters payload:[NSData dataWithBytes:singlePayload length:4]]);
            NSCAssert(!switched && [capture.sent isEqual:[BMSModbusCodec readRunningParametersWithAddress:1 start:300 count:42 error:nil]], @"须重新读取42项实际参数");
            capture.receiveHandler(type.integerValue==0 ? nextFrame : captured);
            NSCAssert(switched, @"完整回读后应完成类型切换");
        }
        NSData *previousCommand = capture.sent;
        __block BOOL unsupportedTypeRejected = NO;
        [captureClient changeBatteryType:2 completion:^(id value, NSError *e) { unsupportedTypeRejected = value==nil && e!=nil; }];
        NSCAssert(unsupportedTypeRejected && capture.sent==previousCommand, @"测试编码未确认时不允许发包");
        capture.connected = NO;
        __block BOOL offlineRejected = NO;
        [captureClient changeBatteryType:0 completion:^(id value, NSError *e) { offlineRejected = value==nil && e!=nil; }];
        NSCAssert(offlineRejected && capture.sent==previousCommand, @"未连接时不允许写入");
        capture.connected = YES;
        __block BOOL mismatchRejected = NO;
        [captureClient changeBatteryType:0 completion:^(id value, NSError *e) { mismatchRejected = value==nil && e!=nil; }];
        capture.receiveHandler([BMSModbusCodec writeRunningParameterWithAddress:1 registerAddress:336 value:0]);
        capture.receiveHandler([BMSModbusCodec frameWithAddress:1 function:BMSFunctionCodeReadRunningParameters payload:Hex(@"00 02 00 01")]);
        NSCAssert(mismatchRejected && !captureClient.isBusy, @"设备仍为旧类型时不得显示切换成功");
        __block BOOL finalMismatchRejected = NO;
        [captureClient changeBatteryType:0 completion:^(id value, NSError *e) { finalMismatchRejected = value==nil && e!=nil; }];
        capture.receiveHandler([BMSModbusCodec writeRunningParameterWithAddress:1 registerAddress:336 value:0]);
        capture.receiveHandler([BMSModbusCodec frameWithAddress:1 function:BMSFunctionCodeReadRunningParameters payload:Hex(@"00 02 00 00")]);
        capture.receiveHandler(captured); // 完整回读仍为铁锂，必须报告失败。
        NSCAssert(finalMismatchRejected, @"完整回读类型不一致不得报告成功");
        __block BOOL cancelledSwitch = NO;
        [captureClient changeBatteryType:0 completion:^(id value, NSError *e) { cancelledSwitch = value==nil && e!=nil; }];
        capture.receiveHandler([BMSModbusCodec writeRunningParameterWithAddress:1 registerAddress:336 value:0]);
        [captureClient cancelPendingRequest];
        NSCAssert(cancelledSwitch && !captureClient.isBusy, @"切换期间断开必须结束操作");
        // 日志供硬件核对：记录完整16位类型和字节位置，未知值不能误标成“测试”。
        NSMutableArray<NSString *> *diagnosticLines = NSMutableArray.array;
        captureClient.logHandler = ^(NSString *line) { [diagnosticLines addObject:line]; };
        __block BOOL diagnosticRead = NO;
        [captureClient readCommonParameters:^(NSArray *items, NSError *e) { NSCAssert(!e && items.count==42, @"诊断日志不能改变读取结果"); diagnosticRead = YES; }];
        capture.receiveHandler([customerParameters subdataWithRange:NSMakeRange(0, 77)]);
        NSCAssert(!diagnosticRead && ![[diagnosticLines componentsJoinedByString:@"\n"] containsString:@"【电芯类型解析】"], @"完整帧未校验前不能输出类型结论");
        capture.receiveHandler([customerParameters subdataWithRange:NSMakeRange(77, customerParameters.length-77)]);
        NSString *diagnosticText = [diagnosticLines componentsJoinedByString:@"\n"];
        NSCAssert(diagnosticRead && [diagnosticText containsString:@"D336(0x0150)，完整响应字节[76..77]=00 01"] && [diagnosticText containsString:@"十进制=1，当前映射=磷酸铁锂"], @"日志应准确给出类型来源和解释");
        NSCAssert([diagnosticText containsString:@"D300(0x012C) 充电过压保护 | 字节[4..5]=0E D8 | 原始=3800(0x0ED8)"] && [diagnosticText containsString:@"换算=110×1-40=70 ℃"] && [diagnosticText containsString:@"换算=10000×0.01+0=100 Ah"], @"必须记录原始字节、电压、温度偏移和容量倍率");
        NSArray *parameterLines = [diagnosticText componentsSeparatedByString:@"\n"];
        NSUInteger registerLines = 0;
        for (NSString *line in parameterLines) { if ([line hasPrefix:@"D3"]) { registerLines++; } }
        NSCAssert(registerLines==42, @"硬件核对日志必须包含全部42项参数");
        for (NSNumber *type in @[@0, @2, @256]) {
            [diagnosticLines removeAllObjects];
            NSMutableData *payload = [[customerParameters subdataWithRange:NSMakeRange(2, customerParameters.length-4)] mutableCopy];
            uint8_t *bytes = payload.mutableBytes; bytes[74] = type.unsignedShortValue >> 8; bytes[75] = type.unsignedShortValue & 0xFF;
            [captureClient readCommonParameters:^(id value, NSError *e) { NSCAssert(!e, @"保留未知类型原始值"); }];
            capture.receiveHandler([BMSModbusCodec frameWithAddress:1 function:BMSFunctionCodeReadRunningParameters payload:payload]);
            NSString *text = [diagnosticLines componentsJoinedByString:@"\n"];
            NSString *expectedTypeLog = [NSString stringWithFormat:@"十进制=%@，当前映射=%@", type, type.intValue==0 ? @"三元锂" : @"未知类型"];
            NSCAssert([text containsString:expectedTypeLog], @"类型使用完整16位，未定义值不推测映射");
        }
        [diagnosticLines removeAllObjects];
        NSMutableData *invalidDiagnosticFrame = customerParameters.mutableCopy; ((uint8_t *)invalidDiagnosticFrame.mutableBytes)[10] ^= 1;
        [captureClient readCommonParameters:^(id value, NSError *e) { NSCAssert(e && !value, @"拒绝CRC错误"); }];
        capture.receiveHandler(invalidDiagnosticFrame);
        NSCAssert(![[diagnosticLines componentsJoinedByString:@"\n"] containsString:@"【参数解析开始】"], @"CRC不通过不得记录已解码的工程值");
        NSLog(@"BMS protocol smoke tests passed");
    }
    return 0;
}
