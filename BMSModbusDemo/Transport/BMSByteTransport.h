#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^BMSTransportStateHandler)(BOOL connected, NSString *message);
typedef void (^BMSTransportReceiveHandler)(NSData *data);
typedef void (^BMSTransportErrorHandler)(NSError *error);

/// 蓝牙和模拟器共同遵守的“字节通道”接口，业务层无需知道数据来自哪里。
@protocol BMSByteTransport <NSObject>
@property (nonatomic, copy, nullable) BMSTransportStateHandler stateHandler;
@property (nonatomic, copy, nullable) BMSTransportReceiveHandler receiveHandler;
@property (nonatomic, copy, nullable) BMSTransportErrorHandler errorHandler;
@property (nonatomic, readonly, getter=isConnected) BOOL connected;
- (void)connect;
- (void)disconnect;
- (void)sendData:(NSData *)data;
@end

NS_ASSUME_NONNULL_END
