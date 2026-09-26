// 独立 Simulator 测试宿主，不加入正式 App target；只在测试进程注入离线值。
#import <UIKit/UIKit.h>
#import "../BMSModbusDemo/UI/ViewController.h"
#import "../BMSModbusDemo/UI/BMSFunctionsViewController.h"
#import "../BMSModbusDemo/Protocol/BMSModbusCodec.h"

@interface BMSFunctionsViewController (TestAccess)
- (void)refreshAll;
- (void)modeChanged;
- (void)openConnection;
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController;
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
@interface BMSFunctionsTestApp : UIResponder <UIApplicationDelegate>
@property (nonatomic,strong) UIWindow *window;
@property (nonatomic,strong) ViewController *root;
@end
@implementation BMSFunctionsTestApp
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
    __block BMSFunctionsViewController *page;
    __block BMSTestTransport *transport;
    __block BMSClient *client;
    __block NSData *realtimeFrame;
    __block NSData *informationFrame;
    __block NSData *parameterFrame;
    NSArray<dispatch_block_t> *steps = @[
    ^{
        self.root.selectedIndex=2;
    }, ^{
        page=[self.root valueForKey:@"functionsController"];
        BMSClient *original=[self.root valueForKey:@"client"]; original.transport.stateHandler=nil;
        transport=[BMSTestTransport new]; transport.connected=YES;
        client=[[BMSClient alloc] initWithTransport:transport]; page.client=client;
        [page connectionChanged:YES message:@"离线测试宿主 · 非实机数据"];
        [self shot:@"functions-empty"];
        [page refreshAll];
        Check([[BMSModbusCodec hexStringFromData:transport.sent] isEqual:@"01 04 00 60 00 56 70 2A"],@"概览必须独立读取实时区");
        NSUInteger sends=transport.sends; [page refreshAll];
        Check(transport.sends==sends,@"重复刷新不可叠加请求");
        NSMutableArray *words=NSMutableArray.array;
        for (NSUInteger i=0;i<86;i++) { [words addObject:@0]; }
        words[47]=@99; words[50]=@10000; words[51]=@265; words[67]=@1;
        words[70]=@70; words[71]=@65; words[81]=@1; words[82]=@2;
        realtimeFrame=Response(words); transport.receiveHandler(realtimeFrame);
        Check([[BMSModbusCodec hexStringFromData:transport.sent] hasPrefix:@"01 04 00 00 00 32"],@"第二步读取设备信息");
        words=NSMutableArray.array; for(NSUInteger i=0;i<50;i++){ [words addObject:@0]; }
        words[0]=@0x5631; words[20]=@0x4831; words[35]=@0x3031;
        informationFrame=Response(words); transport.receiveHandler(informationFrame);
        Check([[BMSModbusCodec hexStringFromData:transport.sent] hasPrefix:@"01 04 01 2C 00 2A"],@"第三步读取常规参数");
        words=NSMutableArray.array; for(NSUInteger i=0;i<42;i++){ [words addObject:@1]; }
        words[0]=@3800; words[2]=@3600; words[3]=@2200; words[5]=@2400;
        words[6]=@1800; words[10]=@3400; words[23]=@110; words[35]=@8;
        words[36]=@1; words[38]=@10000; words[41]=@8000;
        parameterFrame=Response(words); transport.receiveHandler(parameterFrame);
        Check(!client.isBusy && ![[page valueForKey:@"reading"] boolValue],@"顺序刷新必须结束");
        Check([[page valueForKey:@"parameters"] count]==42,@"必须保留全部42项参数");
        NSArray *sections=[page valueForKey:@"sections"];
        Check([sections[1][@"rows"][0][@"value"] isEqual:@"闭合"],@"MOS状态未更新");
        Check([sections[1][@"rows"][1][@"value"] isEqual:@"未知(2)"],@"未知MOS不能显示正常");
    }, ^{
        [self shot:@"functions-overview"];
        UISegmentedControl *mode=[page valueForKey:@"modeControl"]; mode.selectedSegmentIndex=1; [page modeChanged];
    }, ^{
        [self shot:@"functions-parameters"];
        UISearchController *search=[page valueForKey:@"search"];
        search.searchBar.text=@"d336"; [page updateSearchResultsForSearchController:search];
        NSArray *sections=[page valueForKey:@"sections"];
        Check(sections.count==3 && [sections[1][@"rows"] count]==1,@"地址搜索必须大小写不敏感");
        Check([sections[1][@"rows"][0][@"title"] containsString:@"磷酸铁锂"],@"电池类型需要显示设备值");
        [page tableView:page.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
    }, ^{
        Check([page.presentedViewController isKindOfClass:UIAlertController.class],@"参数详情应展示");
        Check([((UIAlertController *)page.presentedViewController).message containsString:@"0x0150"],@"参数详情地址错误");
        [self shot:@"functions-detail"];
        [page dismissViewControllerAnimated:NO completion:nil];
        UISearchController *search=[page valueForKey:@"search"];
        search.searchBar.text=@"不存在的参数"; [page updateSearchResultsForSearchController:search];
        Check([[page valueForKey:@"sections"] count]==2,@"无匹配参数应显示空状态");
        search.searchBar.text=@""; [page updateSearchResultsForSearchController:search];
        [page refreshAll]; [client cancelPendingRequest];
        Check(client.isBusy,@"实时区失败后仍应读取独立设备信息区");
        transport.receiveHandler(informationFrame); transport.receiveHandler(parameterFrame);
        Check([page valueForKey:@"snapshot"]!=nil,@"读取失败必须保留旧快照");
        Check([[[page valueForKey:@"readStates"] objectForKey:@"state"] containsString:@"保留上次读数"],@"旧值必须标注未更新");
        [page refreshAll];
        [page connectionChanged:NO message:@"设备断开"]; transport.connected=NO;
        [client cancelPendingRequest];
        transport.receiveHandler(realtimeFrame);
        Check([page valueForKey:@"snapshot"]==nil && [page valueForKey:@"parameters"]==nil && [page valueForKey:@"information"]==nil,@"断线必须清空全部数据，旧回调不得回填");
        NSUInteger sends=transport.sends; [page refreshAll];
        Check(transport.sends==sends,@"断线不发送请求");
        [page openConnection];
    }, ^{
        Check(self.root.selectedIndex==1,@"设备入口应切换到连接页");
        UINavigationController *nav=(UINavigationController *)self.root.selectedViewController;
        Check(nav.topViewController==[self.root valueForKey:@"diagnosticsController"],@"设备入口应打开诊断页");
        NSString *dir=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
        [@"BMS functions UI smoke tests passed" writeToFile:[dir stringByAppendingPathComponent:@"result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"BMS functions UI smoke tests passed");
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
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(BMSFunctionsTestApp.class)); } }
