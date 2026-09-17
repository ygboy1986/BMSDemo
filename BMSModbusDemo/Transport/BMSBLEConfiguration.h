#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

NS_ASSUME_NONNULL_BEGIN

/// BLE 参数集中配置。协议 PDF 未提供 UUID，接入实机时只需替换这些值。
@interface BMSBLEConfiguration : NSObject
@property (nonatomic, copy) NSString *serviceUUID;
@property (nonatomic, copy) NSString *writeCharacteristicUUID;
@property (nonatomic, copy) NSString *notifyCharacteristicUUID;
@property (nonatomic, copy, nullable) NSString *deviceNamePrefix;
/// 扫描结果允许显示的设备名称前缀；空数组表示不过滤。
@property (nonatomic, copy) NSArray<NSString *> *deviceNamePrefixes;
@property (nonatomic) CBCharacteristicWriteType writeType;
/// 配置 UUID 匹配失败时，是否自动选择同一服务中可写和可通知的特征。
@property (nonatomic) BOOL automaticallyDetectUARTCharacteristics;
+ (instancetype)demoConfiguration;
@end

NS_ASSUME_NONNULL_END
