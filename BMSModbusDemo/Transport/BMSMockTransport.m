#import "BMSMockTransport.h"
#import "../Protocol/BMSModbusCodec.h"

@interface BMSMockTransport ()
@property (nonatomic, readwrite, getter=isConnected) BOOL connected;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *parameters;
@end

@implementation BMSMockTransport

- (instancetype)init {
    if (self = [super init]) {
        _parameters = NSMutableDictionary.dictionary;
        uint16_t defaults[] = {3800,0,3600,2200,0,2400,1500,1000,800,1,3300,30,0,0,0,0,0,0,0,0,0,1000,60,110,95,35,45,120,105,10,30,10,10,40,40,16,1,1,10000,1,12,7800};
        for (NSUInteger i=0; i<42; i++) { _parameters[@(300+i)] = @(defaults[i]); }
    }
    return self;
}

- (void)connect {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.connected = YES;
        if (self.stateHandler) { self.stateHandler(YES, @"模拟 BMS 已连接"); }
    });
}

- (void)disconnect {
    self.connected = NO;
    if (self.stateHandler) { self.stateHandler(NO, @"模拟 BMS 已断开"); }
}

- (void)sendData:(NSData *)data {
    if (!self.connected || data.length < 4) {
        if (self.errorHandler) {
            self.errorHandler([NSError errorWithDomain:@"com.demo.bms.mock" code:1 userInfo:@{NSLocalizedDescriptionKey: @"模拟设备未连接或请求帧无效"}]);
        }
        return;
    }
    NSData *response = [self responseForRequest:data];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.receiveHandler) { self.receiveHandler(response); }
    });
}

- (NSData *)responseForRequest:(NSData *)request {
    const uint8_t *bytes = request.bytes;
    uint8_t address = bytes[0];
    BMSFunctionCode function = bytes[1];
    NSMutableData *payload = NSMutableData.data;
    switch (function) {
        case BMSFunctionCodeReadRunningStatus: {
            uint16_t count = (uint16_t)((bytes[4] << 8) | bytes[5]);
            uint8_t byteCount = (uint8_t)((count + 7) / 8);
            [payload appendBytes:&byteCount length:1];
            for (uint8_t i = 0; i < byteCount; i++) { uint8_t sample = (uint8_t)(0x05 ^ i); [payload appendBytes:&sample length:1]; }
            break;
        }
        case BMSFunctionCodeReadRunningParameters: {
            uint16_t start = (uint16_t)((bytes[2] << 8) | bytes[3]);
            uint16_t count = (uint16_t)((bytes[4] << 8) | bytes[5]);
            uint16_t byteCount = count * 2;
            uint8_t lengthBytes[] = {(uint8_t)(byteCount >> 8), (uint8_t)byteCount};
            [payload appendBytes:lengthBytes length:2];
            for (uint16_t i = 0; i < count; i++) {
                // 兼容早期的三个演示寄存器，同时提供 Ver1.4 真实地址区的模拟值。
                uint16_t samples[] = {520, 10015, 78};
                uint16_t sample = i < 3 ? samples[i] : (uint16_t)(600 + i);
                if (start == 0x0093 && count == 1) { sample = 520; } // 单寄存器总电压测试：52.0V。
                if ((start == 0x008E && count == 40) || (start == 0x0060 && count == 86)) {
                    sample = 0;
                    switch ((NSInteger)start + i - 0x008E) {
                        case 0: sample = 0x4E4E; break; // 真实/显示 SOC 均为 78%。
                        case 1: sample = 95; break;     // SOH。
                        case 4: sample = 10015; break;  // +1.5 A。
                        case 5: sample = 520; break;    // 52.0 V。
                        case 24: sample = 65; break;    // MOS 25℃（偏移40）。
                        case 25: sample = 64; break;    // 环境 24℃。
                        case 35: case 36: sample = 1; break;
                        default: break;
                    }
                    NSInteger address = start+i;
                    if (address>=104 && address<120) { sample = 3250+(address-104); }
                    if (address>=136 && address<=141) { sample = 65; }
                }
                if (self.parameters[@(start+i)]) { sample = self.parameters[@(start+i)].unsignedShortValue; }
                if (start==0 && count==50) {
                    // 与设备信息区地址边界一致：40字节软件、30字节硬件、20字节编号。
                    uint8_t info[100] = {0};
                    memcpy(info, "YT_DEMO_software_1.0", 20);
                    memcpy(info+40, "YT_DEMO_hardware_1.0", 20);
                    memcpy(info+70, "DEMO0000000000000001", 20);
                    uint8_t date[] = {26,9,17,18,30,0};
                    memcpy(info+90, date, 6);
                    sample = (info[i*2]<<8)|info[i*2+1];
                }
                uint8_t pair[] = {(uint8_t)(sample >> 8), (uint8_t)sample};
                [payload appendBytes:pair length:2];
            }
            break;
        }
        case BMSFunctionCodeReadHistoryCount: {
            uint8_t count[] = {0x00, 0x03}; [payload appendBytes:count length:2]; break;
        }
        case BMSFunctionCodeReadHistoryRecord:
            [self appendMockHistoryToPayload:payload index:(uint16_t)((bytes[2] << 8) | bytes[3])]; break;
        case BMSFunctionCodeFirmwareStatus: {
            [payload appendBytes:&bytes[2] length:1]; uint8_t success = 0; [payload appendBytes:&success length:1]; break;
        }
        case BMSFunctionCodeWriteRunningParameter: {
            uint16_t reg = (bytes[2]<<8)|bytes[3];
            self.parameters[@(reg)] = @((bytes[4]<<8)|bytes[5]);
            [payload appendBytes:bytes+2 length:4];
            break;
        }
        default:
            // 写寄存器、固件索引/数据、心跳均按协议回显请求的数据域。
            [payload appendData:[request subdataWithRange:NSMakeRange(2, request.length - 4)]]; break;
    }
    return [BMSModbusCodec frameWithAddress:address function:function payload:payload];
}

- (void)appendMockHistoryToPayload:(NSMutableData *)payload index:(uint16_t)index {
    uint8_t indexBytes[] = {(uint8_t)(index >> 8), (uint8_t)index};
    [payload appendBytes:indexBytes length:2];
    // 时间 YY MM DD HH mm ss；之后严格按 PDF 第 16 页的字段顺序构造 93 字节数据。
    uint8_t header[] = {26, 9, 10, 11, 55, 36, 0x01, 0x14, 0x50, 0x27, 0x42, 0x4E};
    [payload appendBytes:header length:sizeof(header)]; // 520.0V, +5.0A, SOC 78%
    for (NSUInteger i = 0; i < 32; i++) { uint16_t mv = (uint16_t)(3300 + i); uint8_t pair[] = {(uint8_t)(mv >> 8), (uint8_t)mv}; [payload appendBytes:pair length:2]; }
    uint8_t tail[] = {65, 66, 64, 67, 65, 66, 70, 64, 0x00, 0x00, 1, 1, 0, 0, 0, 0x2A, 0, 0, 0, 0, 0, 0};
    [payload appendBytes:tail length:sizeof(tail)];
}

@end
