// 独立 Simulator 测试宿主，不加入正式 App target；只在测试进程注入离线值。
#import <UIKit/UIKit.h>
#import "../BMSModbusDemo/UI/ViewController.h"
#import "../BMSModbusDemo/UI/BMSMonitorViewController.h"
#import "../BMSModbusDemo/Protocol/BMSModbusCodec.h"

@interface BMSMonitorViewController (TestAccess)
- (void)manualRead;
- (void)tick;
- (void)toggleProbes;
- (void)showCells;
- (void)applicationInactive;
- (void)connectionTapped;
- (void)logTapped;
@end
@interface BMSTestTransport : NSObject <BMSByteTransport>
@property (nonatomic,copy) BMSTransportStateHandler stateHandler;
@property (nonatomic,copy) BMSTransportReceiveHandler receiveHandler;
@property (nonatomic,copy) BMSTransportErrorHandler errorHandler;
@property (nonatomic,getter=isConnected) BOOL connected;
@property (nonatomic,strong) NSData *sent;
@property (nonatomic) NSUInteger sends;
@end
@implementation BMSTestTransport
- (void)connect { self.connected=YES; }
- (void)disconnect { self.connected=NO; }
- (void)sendData:(NSData *)data { self.sent=data; self.sends++; }
@end
static NSData *Response(NSArray<NSNumber *> *words) {
    NSMutableData *payload=[NSMutableData data]; NSUInteger length=words.count*2;
    uint8_t head[]={(uint8_t)(length>>8),(uint8_t)length}; [payload appendBytes:head length:2];
    for (NSNumber *word in words) { uint16_t raw=word.unsignedShortValue; uint8_t bytes[]={(uint8_t)(raw>>8),(uint8_t)raw}; [payload appendBytes:bytes length:2]; }
    return [BMSModbusCodec frameWithAddress:1 function:4 payload:payload];
}
static void Check(BOOL ok, NSString *message) { if (!ok) { NSLog(@"UI TEST FAILED: %@",message); abort(); } }
@interface BMSMonitorTestApp : UIResponder <UIApplicationDelegate>
@property (nonatomic,strong) UIWindow *window;
@property (nonatomic,strong) ViewController *root;
@end
@implementation BMSMonitorTestApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.root=[ViewController new]; self.window.rootViewController=self.root; [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{ [self runTests]; });
    return YES;
}
- (void)shot:(NSString *)name {
    [self.window layoutIfNeeded];
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithBounds:self.window.bounds];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) { [self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:YES]; }];
    NSString *dir=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    [UIImagePNGRepresentation(image) writeToFile:[dir stringByAppendingPathComponent:[name stringByAppendingString:@".png"]] atomically:YES];
}
- (void)runTests {
    __block BMSMonitorViewController *monitor;
    __block UISwitch *automatic;
    __block BMSTestTransport *transport;
    __block BMSClient *client;
    __block NSData *frame;
    __block NSDictionary<NSString *,UILabel *> *values;
    __block UIScrollView *scroll;
    __block UITableViewController *cellsPage;
    // 每一步返回主队列，让 UIKit 正常完成导航和外观生命周期回调。
    NSArray<dispatch_block_t> *steps = @[
    ^{
    Check(self.root.viewControllers.count==5,@"五个Tab必须保留");
    BMSClient *original=[self.root valueForKey:@"client"]; original.transport.stateHandler=nil;
    self.root.selectedIndex=1;
    }, ^{
    monitor=[self.root valueForKey:@"monitorController"];
    [monitor loadViewIfNeeded]; [monitor applicationInactive];
    automatic=[monitor valueForKey:@"autoSwitch"]; automatic.on=NO;
    transport=[BMSTestTransport new]; transport.connected=YES;
    client=[[BMSClient alloc] initWithTransport:transport]; monitor.client=client;
    [monitor connectionChanged:YES message:@"离线测试宿主 · 非实机数据"];
    [monitor applicationInactive];
    [self shot:@"monitor-empty"];
    [monitor manualRead];
    Check([[BMSModbusCodec hexStringFromData:transport.sent] hasPrefix:@"01 04 01 4F 00 01"],@"监控必须读取真实D335串数");
    transport.receiveHandler(Response(@[@8]));
    Check([[BMSModbusCodec hexStringFromData:transport.sent] isEqual:@"01 04 00 60 00 56 70 2A"],@"完整实时区请求不正确");
    NSMutableArray *words=NSMutableArray.array; for (NSUInteger i=0;i<86;i++) { [words addObject:@0]; }
    NSArray *cells=@[@3313,@3298,@3329,@4369,@4770,@799,@3298,@3341];
    for (NSUInteger i=0;i<8;i++) { words[8+i]=cells[i]; }
    for (NSUInteger i=0;i<6;i++) { words[40+i]=i==0 ? @71 : @40; }
    words[47]=@100; words[50]=@10000; words[51]=@265; words[54]=@1;
    words[67]=@0x1003; words[68]=@2; words[70]=@70; words[71]=@40;
    frame=Response(words);
    transport.receiveHandler([frame subdataWithRange:NSMakeRange(0,80)]);
    Check([monitor valueForKey:@"snapshot"]==nil,@"半帧不可更新UI");
    transport.receiveHandler([frame subdataWithRange:NSMakeRange(80,frame.length-80)]);
    values=[monitor valueForKey:@"values"];
    Check([values[@"voltage"].text isEqual:@"26.500 V"] && [values[@"difference"].text isEqual:@"3971 mV"],@"真实响应未映射到卡片");
    }, ^{
    [self shot:@"monitor-data"];
    [monitor toggleProbes]; Check(![[monitor valueForKey:@"probes"] isHidden],@"探针无法展开");
    scroll=(UIScrollView *)monitor.view.subviews.firstObject;
    [scroll setContentOffset:CGPointMake(0,650) animated:NO];
    }, ^{
    [self shot:@"monitor-temperatures"];
    [monitor toggleProbes]; Check([[monitor valueForKey:@"probes"] isHidden],@"探针无法收起");
    [monitor showCells];
    }, ^{
    cellsPage=(UITableViewController *)monitor.navigationController.topViewController;
    Check([cellsPage.tableView numberOfRowsInSection:0]==32,@"单节详情必须有32路");
    automatic.on=YES; NSUInteger count=transport.sends;
    [monitor tick]; Check(transport.sends==count+1,@"单节详情也应刷新");
    [monitor tick]; Check(transport.sends==count+1,@"忙碌时不能重叠请求");
    transport.receiveHandler(frame);
    [self shot:@"monitor-cells"];
    self.root.selectedIndex=2; count=transport.sends; [monitor tick]; Check(transport.sends==count,@"其他Tab不得轮询");
    }, ^{
    self.root.selectedIndex=1;
    }, ^{
    [monitor tick]; Check(client.isBusy,@"应发起实时读取");
    [client cancelPendingRequest];
    Check([values[@"voltage"].text isEqual:@"26.500 V"],@"读失败应保留并标注旧值");
    UILabel *status=[monitor valueForKey:@"statusLabel"]; Check([status.text containsString:@"失败"],@"失败必须标记读数未更新");
    [monitor connectionChanged:NO message:@"设备断开"]; transport.connected=NO;
    Check([values[@"voltage"].text isEqual:@"—"] && [monitor valueForKey:@"snapshot"]==nil,@"断开必须清除旧设备读数");
    UITableViewCell *first=[cellsPage.tableView.dataSource tableView:cellsPage.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    Check([first.textLabel.text containsString:@"—"],@"断开必须清除单节详情");
    [monitor.navigationController popToRootViewControllerAnimated:NO];
    }, ^{
    [monitor connectionTapped];
    }, ^{
    Check(monitor.navigationController.topViewController==[self.root valueForKey:@"diagnosticsController"],@"设备/日志入口应打开原蓝牙与日志页");
    NSUInteger sentBeforeDiagnostics=transport.sends;
    [monitor tick]; Check(transport.sends==sentBeforeDiagnostics,@"设备与日志页不得轮询");
    [monitor.navigationController popToRootViewControllerAnimated:NO];
    }, ^{
    [monitor logTapped];
    }, ^{
    Check(monitor.navigationController.topViewController==[self.root valueForKey:@"diagnosticsController"],@"日志按钮必须打开日志页");
    [monitor.navigationController popToRootViewControllerAnimated:NO];
    }, ^{
    [scroll setContentOffset:CGPointZero animated:NO];
    NSLog(@"BMS monitor UI smoke tests passed");
    NSString *dir=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    [@"BMS monitor UI smoke tests passed" writeToFile:[dir stringByAppendingPathComponent:@"result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }];
    [self performSteps:steps index:0];
}
- (void)performSteps:(NSArray<dispatch_block_t> *)steps index:(NSUInteger)index {
    if (index >= steps.count) { return; }
    steps[index]();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 600*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        [self performSteps:steps index:index+1];
    });
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(BMSMonitorTestApp.class)); } }
