#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Ver1.4 寄存器表中的实时数据快照。
/// 调用者只使用已经换算好的工程量，不需要关心寄存器地址、倍率和偏移量。
@interface BMSRealtimeData : NSObject

@property (nonatomic, readonly) double totalVoltage;       // V，原始值单位 0.1 V。
@property (nonatomic, readonly) double totalCurrent;       // A，原始值以 1000 A 为零点、单位 0.1 A。
@property (nonatomic, readonly) NSUInteger realSOC;        // SOC 高字节。
@property (nonatomic, readonly) NSUInteger displaySOC;     // SOC 低字节，APP 显示优先使用此值。
@property (nonatomic, readonly) NSUInteger SOH;
@property (nonatomic, readonly) NSInteger MOSTemperature;  // ℃，原始值减 40。
@property (nonatomic, readonly) NSInteger ambientTemperature;
@property (nonatomic, readonly) uint16_t faultBits;
@property (nonatomic, readonly) NSUInteger faultLevel;     // 0正常、1预警、2告警。
@property (nonatomic, readonly) BOOL chargeMOSOn;
@property (nonatomic, readonly) BOOL dischargeMOSOn;
@property (nonatomic, readonly) BOOL prechargeMOSOn;
@property (nonatomic, readonly) BOOL preventionMOSOn;
@property (nonatomic, readonly) BOOL currentLimitMOSOn;
@property (nonatomic, copy, readonly) NSArray<NSString *> *faultDescriptions;
/// 完整实时区的原始寄存器，便于后续接入更多业务字段。
@property (nonatomic, copy, readonly) NSArray<NSNumber *> *rawRegisters;
/// 无效/异常值用NSNull表示，零电压保持为零，不推断电芯数量。
@property (nonatomic, copy, readonly) NSArray *cellVoltages;
@property (nonatomic, copy, readonly) NSArray *probeTemperatures;
@property (nonatomic, copy, readonly) NSString *detailText;
/// 监控页文本；无效值显示“—”，串数仅采用设备 D335，不按非零电压猜测。
- (NSDictionary<NSString *, NSString *> *)monitorValuesForCellCount:(nullable NSNumber *)cellCount;
- (NSString *)balanceTextForCell:(NSUInteger)index;
- (NSArray<NSDictionary<NSString *, NSString *> *> *)alarmRows;
@property (nonatomic, copy, readonly) NSString *diagnosticText;
- (nullable instancetype)initWithFullRegisters:(NSArray<NSNumber *> *)registers error:(NSError **)error;

/// 解析从 0x008E 开始、连续 40 个寄存器的 0x04 响应值。
- (nullable instancetype)initWithRegisters:(NSArray<NSNumber *> *)registers
                                     error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
