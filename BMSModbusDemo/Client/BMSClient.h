#import <Foundation/Foundation.h>
#import "../Transport/BMSByteTransport.h"
#import "BMSRealtimeData.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^BMSClientCompletion)(id _Nullable result, NSError * _Nullable error);
typedef void (^BMSClientLogHandler)(NSString *line);

/// 面向业务层的 BMS API。调用者只传地址和值，不需要自行拼 MODBUS 帧。
@interface BMSClient : NSObject
@property (nonatomic, readonly) id<BMSByteTransport> transport;
@property (nonatomic) uint8_t slaveAddress; // 文档范围 1~247，默认 1。
@property (nonatomic) NSTimeInterval responseTimeout; // 默认 3 秒，超时后自动释放当前命令。
@property (nonatomic, copy, nullable) BMSClientLogHandler logHandler;
@property (nonatomic, readonly, getter=isBusy) BOOL busy;
/// 返回软件/硬件版本、识别码、RTC、零漂及自检原始位。
- (void)readDeviceInformation:(BMSClientCompletion)completion;
/// 读取0x012C起的42项常规参数，返回包含名称、单位、范围、原始值的字典数组。
- (void)readCommonParameters:(BMSClientCompletion)completion;
/// 传工程量（温度℃、容量Ah等），检查范围后写入并回读校验。
- (void)writeCommonParameterAt:(uint16_t)address engineeringValue:(double)value completion:(BMSClientCompletion)completion;

- (instancetype)initWithTransport:(id<BMSByteTransport>)transport;
/// 按旧APP抓包读取0x0060~0x00B5共86个寄存器，返回已换算的实时快照。
- (void)readRealtimeData:(BMSClientCompletion)completion;
/// 最小通信测试：只读取总电压 0x0093，成功返回 NSNumber（单位 V）。
- (void)readTotalVoltage:(BMSClientCompletion)completion;
- (void)readRunningStatusFrom:(uint16_t)start count:(uint16_t)count completion:(BMSClientCompletion)completion;
- (void)readRunningParametersFrom:(uint16_t)start count:(uint16_t)count completion:(BMSClientCompletion)completion;
- (void)setRunningStatusAt:(uint16_t)registerAddress on:(BOOL)on completion:(BMSClientCompletion)completion;
- (void)setRunningParameterAt:(uint16_t)registerAddress value:(uint16_t)value completion:(BMSClientCompletion)completion;
- (void)readHistoryCount:(BMSClientCompletion)completion;
- (void)readHistoryRecordAtIndex:(uint16_t)index completion:(BMSClientCompletion)completion;
- (void)announceFirmware:(NSData *)firmware type:(uint8_t)type version:(uint16_t)version completion:(BMSClientCompletion)completion;
- (void)sendFirmwareChunk:(NSData *)chunk type:(uint8_t)type version:(uint16_t)version offset:(uint32_t)offset completion:(BMSClientCompletion)completion;
- (void)queryFirmwareStatusForType:(uint8_t)type completion:(BMSClientCompletion)completion;
- (void)sendHeartbeat:(BMSClientCompletion)completion;
- (void)sendRawFrame:(NSData *)frame expectedLength:(NSUInteger)expectedLength completion:(BMSClientCompletion)completion;
@end

NS_ASSUME_NONNULL_END
