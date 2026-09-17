#import "BMSModbusCodec.h"

NSErrorDomain const BMSModbusErrorDomain = @"com.demo.bms.modbus";

@implementation BMSModbusCodec

+ (uint16_t)modbusCRC16ForData:(NSData *)data {
    // MODBUS CRC-16: poly=0xA001, init=0xFFFF。帧中按低字节、高字节发送。
    uint16_t crc = 0xFFFF;
    const uint8_t *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) {
        crc ^= bytes[i];
        for (NSInteger bit = 0; bit < 8; bit++) {
            crc = (crc & 1) ? (uint16_t)((crc >> 1) ^ 0xA001) : (uint16_t)(crc >> 1);
        }
    }
    return crc;
}

+ (uint16_t)xmodemCRC16ForData:(NSData *)data {
    // 固件内容使用 CRC-16/XMODEM: poly=0x1021, init=0x0000。
    uint16_t crc = 0;
    const uint8_t *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) {
        crc ^= (uint16_t)(bytes[i] << 8);
        for (NSInteger bit = 0; bit < 8; bit++) {
            crc = (crc & 0x8000) ? (uint16_t)((crc << 1) ^ 0x1021) : (uint16_t)(crc << 1);
        }
    }
    return crc;
}

+ (NSData *)frameWithAddress:(uint8_t)address function:(BMSFunctionCode)function payload:(NSData *)payload {
    NSMutableData *frame = [NSMutableData dataWithBytes:&address length:1];
    uint8_t fc = function;
    [frame appendBytes:&fc length:1];
    [frame appendData:payload ?: NSData.data];
    uint16_t crc = [self modbusCRC16ForData:frame];
    uint8_t crcBytes[] = {(uint8_t)(crc & 0xFF), (uint8_t)(crc >> 8)};
    [frame appendBytes:crcBytes length:2];
    return frame;
}

+ (BOOL)validateFrame:(NSData *)frame error:(NSError **)error {
    if (frame.length < 4) {
        [self setError:error code:1 message:@"响应帧长度不足"];
        return NO;
    }
    NSData *body = [frame subdataWithRange:NSMakeRange(0, frame.length - 2)];
    uint16_t expected = [self modbusCRC16ForData:body];
    const uint8_t *bytes = frame.bytes;
    uint16_t actual = (uint16_t)(bytes[frame.length - 2] | (bytes[frame.length - 1] << 8));
    if (expected != actual) {
        [self setError:error code:2 message:@"CRC 校验失败"];
        return NO;
    }
    return YES;
}

+ (NSString *)hexStringFromData:(NSData *)data {
    const uint8_t *bytes = data.bytes;
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:data.length];
    for (NSUInteger i = 0; i < data.length; i++) { [parts addObject:[NSString stringWithFormat:@"%02X", bytes[i]]]; }
    return [parts componentsJoinedByString:@" "];
}

+ (NSData *)readRunningStatusWithAddress:(uint8_t)address start:(uint16_t)start count:(uint16_t)count error:(NSError **)error {
    if (count == 0 || count > 2000) {
        [self setError:error code:3 message:@"运行状态读取数量必须为 1~2000"];
        return nil;
    }
    return [self frameWithAddress:address function:BMSFunctionCodeReadRunningStatus payload:[self dataWithWords:@[@(start), @(count)]]];
}

+ (NSData *)readRunningParametersWithAddress:(uint8_t)address start:(uint16_t)start count:(uint16_t)count error:(NSError **)error {
    if (count == 0 || count > 127) {
        [self setError:error code:4 message:@"运行参数读取数量必须为 1~127"];
        return nil;
    }
    return [self frameWithAddress:address function:BMSFunctionCodeReadRunningParameters payload:[self dataWithWords:@[@(start), @(count)]]];
}

+ (NSData *)writeRunningStatusWithAddress:(uint8_t)address registerAddress:(uint16_t)registerAddress on:(BOOL)on {
    // 按协议正文使用 0x0001/0x0000；若实机遵循标准 MODBUS 线圈值 0xFF00，可在这里集中调整。
    return [self frameWithAddress:address function:BMSFunctionCodeWriteRunningStatus payload:[self dataWithWords:@[@(registerAddress), @(on ? 1 : 0)]]];
}

+ (NSData *)writeRunningParameterWithAddress:(uint8_t)address registerAddress:(uint16_t)registerAddress value:(uint16_t)value {
    return [self frameWithAddress:address function:BMSFunctionCodeWriteRunningParameter payload:[self dataWithWords:@[@(registerAddress), @(value)]]];
}

+ (NSData *)readHistoryCountWithAddress:(uint8_t)address {
    return [self frameWithAddress:address function:BMSFunctionCodeReadHistoryCount payload:[self dataWithWords:@[@0]]];
}

+ (NSData *)readHistoryRecordWithAddress:(uint8_t)address index:(uint16_t)index {
    return [self frameWithAddress:address function:BMSFunctionCodeReadHistoryRecord payload:[self dataWithWords:@[@(index)]]];
}

+ (NSData *)firmwareIndexWithAddress:(uint8_t)address type:(uint8_t)type version:(uint16_t)version firmware:(NSData *)firmware {
    NSMutableData *payload = [NSMutableData dataWithBytes:&type length:1];
    [self appendUInt16:version toData:payload];
    [self appendUInt32:(uint32_t)firmware.length toData:payload];
    [self appendUInt16:[self xmodemCRC16ForData:firmware] toData:payload];
    return [self frameWithAddress:address function:BMSFunctionCodeFirmwareIndex payload:payload];
}

+ (NSData *)firmwareChunkWithAddress:(uint8_t)address type:(uint8_t)type version:(uint16_t)version offset:(uint32_t)offset data:(NSData *)data error:(NSError **)error {
    if (data.length > UINT16_MAX) {
        [self setError:error code:5 message:@"单个固件分片不能超过 65535 字节"];
        return nil;
    }
    NSMutableData *payload = [NSMutableData dataWithBytes:&type length:1];
    [self appendUInt16:version toData:payload];
    [self appendUInt32:offset toData:payload];
    [self appendUInt16:(uint16_t)data.length toData:payload];
    [payload appendData:data];
    return [self frameWithAddress:address function:BMSFunctionCodeFirmwareData payload:payload];
}

+ (NSData *)firmwareStatusWithAddress:(uint8_t)address type:(uint8_t)type {
    return [self frameWithAddress:address function:BMSFunctionCodeFirmwareStatus payload:[NSData dataWithBytes:&type length:1]];
}

+ (NSData *)heartbeatWithAddress:(uint8_t)address {
    uint8_t zeros[] = {0, 0};
    return [self frameWithAddress:address function:BMSFunctionCodeHeartbeat payload:[NSData dataWithBytes:zeros length:2]];
}

+ (NSData *)dataWithWords:(NSArray<NSNumber *> *)words {
    NSMutableData *data = NSMutableData.data;
    for (NSNumber *word in words) { [self appendUInt16:word.unsignedShortValue toData:data]; }
    return data;
}

+ (void)appendUInt16:(uint16_t)value toData:(NSMutableData *)data {
    uint8_t bytes[] = {(uint8_t)(value >> 8), (uint8_t)(value & 0xFF)};
    [data appendBytes:bytes length:2];
}

+ (void)appendUInt32:(uint32_t)value toData:(NSMutableData *)data {
    uint8_t bytes[] = {(uint8_t)(value >> 24), (uint8_t)(value >> 16), (uint8_t)(value >> 8), (uint8_t)value};
    [data appendBytes:bytes length:4];
}

+ (void)setError:(NSError **)error code:(NSInteger)code message:(NSString *)message {
    if (error) { *error = [NSError errorWithDomain:BMSModbusErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}]; }
}

@end
