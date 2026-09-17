#import <Foundation/Foundation.h>
#import "BMSByteTransport.h"

NS_ASSUME_NONNULL_BEGIN

/// 模拟 BMS，从请求中识别功能码并返回带正确 CRC 的响应。
@interface BMSMockTransport : NSObject <BMSByteTransport>
@property (nonatomic, copy, nullable) BMSTransportStateHandler stateHandler;
@property (nonatomic, copy, nullable) BMSTransportReceiveHandler receiveHandler;
@property (nonatomic, copy, nullable) BMSTransportErrorHandler errorHandler;
@end

NS_ASSUME_NONNULL_END
