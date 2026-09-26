#import <UIKit/UIKit.h>
@class BMSClient;

@interface BMSProductViewController : UIViewController
@property (nonatomic, strong) BMSClient *client;
@property (nonatomic, copy) NSString *deviceName;
@property (nonatomic, copy) dispatch_block_t connectionAction;
- (void)connectionChanged:(BOOL)connected;
- (void)resetDevice;
@end
