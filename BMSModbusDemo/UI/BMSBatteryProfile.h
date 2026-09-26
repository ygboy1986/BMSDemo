#import <Foundation/Foundation.h>

/// 参考界面字段与真实协议寄存器映射；不包含本地产品数据。
@interface BMSBatteryProfile : NSObject
+ (NSArray<NSDictionary *> *)fields;
@end
