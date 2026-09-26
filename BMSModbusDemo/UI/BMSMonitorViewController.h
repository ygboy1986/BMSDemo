#import <UIKit/UIKit.h>
#import "../Client/BMSClient.h"

NS_ASSUME_NONNULL_BEGIN
@interface BMSMonitorViewController : UIViewController
@property (nonatomic, strong) BMSClient *client;
@property (nonatomic, copy, nullable) void (^connectionAction)(void);
@property (nonatomic, copy, nullable) void (^logAction)(void);
@property (nonatomic, copy, nullable) void (^snapshotHandler)(BMSRealtimeData *data);
- (void)connectionChanged:(BOOL)connected message:(NSString *)message;
@end
NS_ASSUME_NONNULL_END
