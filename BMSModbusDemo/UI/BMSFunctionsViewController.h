#import <UIKit/UIKit.h>
#import "../Client/BMSClient.h"

NS_ASSUME_NONNULL_BEGIN
@interface BMSFunctionsViewController : UITableViewController
@property (nonatomic, strong) BMSClient *client;
@property (nonatomic, copy, nullable) void (^connectionAction)(void);
- (void)connectionChanged:(BOOL)connected message:(NSString *)message;
@end
NS_ASSUME_NONNULL_END
