#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import "BMSByteTransport.h"

@class BMSBLEConfiguration;

NS_ASSUME_NONNULL_BEGIN

/// 扫描结果的轻量展示模型，不把 CoreBluetooth 对象暴露给界面层。
@interface BMSBLEDevice : NSObject
@property (nonatomic, copy, readonly) NSUUID *identifier;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, strong, readonly) NSNumber *RSSI;
@end

typedef void (^BMSBLEDevicesHandler)(NSArray<BMSBLEDevice *> *devices);

/// CoreBluetooth 实现：扫描 -> 连接 -> 发现服务/特征 -> 打开通知 -> 写入字节。
@interface BMSBLETransport : NSObject <BMSByteTransport, CBCentralManagerDelegate, CBPeripheralDelegate>
@property (nonatomic, copy, nullable) BMSTransportStateHandler stateHandler;
@property (nonatomic, copy, nullable) BMSTransportReceiveHandler receiveHandler;
@property (nonatomic, copy, nullable) BMSTransportErrorHandler errorHandler;
@property (nonatomic, copy, nullable) BMSBLEDevicesHandler devicesHandler;
@property (nonatomic, readonly, getter=isScanning) BOOL scanning;
- (instancetype)initWithConfiguration:(BMSBLEConfiguration *)configuration;
/// 连接用户从扫描列表中选中的设备。
- (void)connectToDevice:(BMSBLEDevice *)device;
@end

NS_ASSUME_NONNULL_END
