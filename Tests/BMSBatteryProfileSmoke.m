#import <Foundation/Foundation.h>
#import "../BMSModbusDemo/UI/BMSBatteryProfile.h"

int main(void) {
    @autoreleasepool {
        NSArray *fields = BMSBatteryProfile.fields;
        NSCAssert(fields.count==21, @"应保留参考界面的21项参数");
        NSSet *supported = [NSSet setWithArray:@[@300,@302,@303,@305,@310,@311,@323,@324,@325,@326,@327,@328,@329,@330]];
        NSMutableSet *mapped = NSMutableSet.set;
        for (NSDictionary *field in fields) {
            NSNumber *address = field[@"address"];
            NSCAssert(field[@"name"] && field[@"unit"], @"参数缺少名称或单位");
            if (address.intValue) { NSCAssert([supported containsObject:address], @"不得猜测未确认的参数地址"); [mapped addObject:address]; }
            if ([field[@"unit"] isEqual:@"A"] || [field[@"unit"] isEqual:@"ms"]) { NSCAssert(address.intValue==0, @"禁止把档位误当成 A/ms"); }
        }
        NSCAssert([mapped isEqual:supported], @"已确认的保护/温度/均衡字段应全部映射");
        NSLog(@"BMS real parameter mapping tests passed");
    }
    return 0;
}
