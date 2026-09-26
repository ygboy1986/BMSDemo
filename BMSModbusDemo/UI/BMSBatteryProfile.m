#import "BMSBatteryProfile.h"

@implementation BMSBatteryProfile
+ (NSArray<NSDictionary *> *)fields {
    NSArray *names = @[@"单体充电过压值",@"单体充电过压恢复值",@"单体放电欠压值",@"单体放电欠压恢复值",@"充电过流保护值",@"充电过流保护延时",@"充电过流恢复延时",@"放电过流保护值",@"放电过流保护延时",@"放电过流恢复延时",@"充电高温保护值",@"充电高温恢复值",@"充电低温保护值",@"充电低温恢复值",@"放电高温保护值",@"放电高温恢复值",@"放电低温保护值",@"放电低温恢复值",@"均衡开启电压值",@"均衡开启压差",@"均衡关闭压差"];
    // 0 表示当前协议没有对应工程值，不能将档位误当作 A/ms，也不能猜测写入地址。
    NSArray *registers = @[@300,@302,@303,@305,@0,@0,@0,@0,@0,@0,@323,@324,@325,@326,@327,@328,@329,@330,@310,@311,@0];
    NSMutableArray *result = NSMutableArray.array;
    for (NSUInteger i=0; i<names.count; i++) {
        BOOL temperature = i>=10 && i<=17;
        NSString *unit = temperature ? @"℃" : (i<4 || i>=18 ? @"mV" : (i==4 || i==7 ? @"A" : @"ms"));
        NSInteger min = temperature ? -40 : (i<4 || i==18 ? 1600 : 1);
        NSInteger max = temperature ? 120 : (i<4 || i==18 ? 4300 : (i==4 || i==7 ? 500 : (i>=19 ? 2000 : 60000)));
        [result addObject:@{@"name":names[i], @"unit":unit, @"address":registers[i], @"min":@(min), @"max":@(max)}];
    }
    return result;
}
@end
