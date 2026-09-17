#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 协议中的功能码。0x19~0x24 为厂家自定义功能码。
typedef NS_ENUM(uint8_t, BMSFunctionCode) {
    BMSFunctionCodeReadRunningStatus      = 0x02,
    BMSFunctionCodeReadRunningParameters  = 0x04,
    BMSFunctionCodeWriteRunningStatus     = 0x05,
    BMSFunctionCodeWriteRunningParameter  = 0x06,
    BMSFunctionCodeReadHistoryCount       = 0x19,
    BMSFunctionCodeReadHistoryRecord      = 0x20,
    BMSFunctionCodeFirmwareIndex          = 0x21,
    BMSFunctionCodeFirmwareData           = 0x22,
    BMSFunctionCodeFirmwareStatus         = 0x23,
    BMSFunctionCodeHeartbeat              = 0x24,
};

/// 只负责 MODBUS RTU 帧的组装、校验与基础解析，不依赖具体蓝牙库。
@interface BMSModbusCodec : NSObject

+ (uint16_t)modbusCRC16ForData:(NSData *)data;
+ (uint16_t)xmodemCRC16ForData:(NSData *)data;
+ (NSData *)frameWithAddress:(uint8_t)address function:(BMSFunctionCode)function payload:(NSData *)payload;
+ (BOOL)validateFrame:(NSData *)frame error:(NSError **)error;
+ (NSString *)hexStringFromData:(NSData *)data;

+ (nullable NSData *)readRunningStatusWithAddress:(uint8_t)address start:(uint16_t)start count:(uint16_t)count error:(NSError **)error;
+ (nullable NSData *)readRunningParametersWithAddress:(uint8_t)address start:(uint16_t)start count:(uint16_t)count error:(NSError **)error;
+ (NSData *)writeRunningStatusWithAddress:(uint8_t)address registerAddress:(uint16_t)registerAddress on:(BOOL)on;
+ (NSData *)writeRunningParameterWithAddress:(uint8_t)address registerAddress:(uint16_t)registerAddress value:(uint16_t)value;
+ (NSData *)readHistoryCountWithAddress:(uint8_t)address;
+ (NSData *)readHistoryRecordWithAddress:(uint8_t)address index:(uint16_t)index;
+ (NSData *)firmwareIndexWithAddress:(uint8_t)address type:(uint8_t)type version:(uint16_t)version firmware:(NSData *)firmware;
+ (nullable NSData *)firmwareChunkWithAddress:(uint8_t)address type:(uint8_t)type version:(uint16_t)version offset:(uint32_t)offset data:(NSData *)data error:(NSError **)error;
+ (NSData *)firmwareStatusWithAddress:(uint8_t)address type:(uint8_t)type;
+ (NSData *)heartbeatWithAddress:(uint8_t)address;

@end

FOUNDATION_EXPORT NSErrorDomain const BMSModbusErrorDomain;

NS_ASSUME_NONNULL_END
