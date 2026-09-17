#import "BMSBLEConfiguration.h"

@implementation BMSBLEConfiguration

+ (instancetype)demoConfiguration {
    BMSBLEConfiguration *configuration = [[self alloc] init];
    // 硬件宏中的 128 位 UUID 数组按 BLE 小端顺序保存，转换成 iOS 标准字符串时需要反转。
    // e0 ff 0d 0c ... 01 00 -> 00010203-0405-0607-0809-0A0B0C0DFFE0
    configuration.serviceUUID = @"00010203-0405-0607-0809-0A0B0C0DFFE0";
    configuration.writeCharacteristicUUID = @"00010203-0405-0607-0809-0A0B0C0DFFE2";
    configuration.notifyCharacteristicUUID = @"00010203-0405-0607-0809-0A0B0C0DFFE1";
    configuration.deviceNamePrefix = nil; // 兼容旧的单前缀配置。
    configuration.deviceNamePrefixes = @[@"YT", @"QM"];
    // 优先使用带回执写入；若特征只支持 WithoutResponse，连接时会自动校正。
    configuration.writeType = CBCharacteristicWriteWithResponse;
    configuration.automaticallyDetectUARTCharacteristics = YES;
    return configuration;
}

@end
