// MARK: Regram — deterministic external I/O adapters; the facade is compiled unchanged.
#import "Support.h"
#import "MTRGProxyConnection.h"
#import "MTDNS.h"
static NSArray *resolved;
static bool lookupFails;
static NSMutableArray *children, *timers;
static NSMutableDictionary<NSValue *, NSDictionary *> *childState;
@implementation MTMetaDisposable
- (void)setDisposable:(id<MTDisposable>)value {}
- (void)dispose {}
@end
@implementation MTSignal
- (MTSignal *)deliverOn:(id)queue { return self; }
- (id<MTDisposable>)startWithNext:(void (^)(id))next error:(void (^)(id))error completed:(void (^)(void))completed {
    if (lookupFails) error(nil); else { next(resolved); completed(); } return nil;
}
@end
@implementation MTQueue
- (dispatch_queue_t)nativeQueue { return dispatch_get_main_queue(); }
- (void)dispatchOnQueue:(dispatch_block_t)block { block(); }
@end
@interface MTTimer ()
@property(copy) dispatch_block_t callback;
@property bool invalid;
@end
@implementation MTTimer
- (id)initWithTimeout:(NSTimeInterval)timeout repeat:(bool)repeat completion:(dispatch_block_t)completion queue:(dispatch_queue_t)queue {
    NSCAssert(timeout == 4 && !repeat, @"Four-second attempt deadline");
    if ((self = [super init])) { self.callback = completion; [timers addObject:self]; } return self;
}
- (void)start {}
- (void)invalidate { self.invalid = true; }
- (void)fire { if (!self.invalid) self.callback(); }
@end
@implementation MTSocksProxySettings
- (id)initWithIp:(NSString *)ip port:(uint16_t)port username:(NSString *)username password:(NSString *)password secret:(NSData *)secret {
    if ((self = [super init])) { self.ip = ip; self.port = port; self.username = username; self.password = password; self.secret = secret; } return self;
}
@end
@implementation MTApiEnvironment
@end
@implementation MTContext
@end
@implementation MTDNS
+ (MTSignal *)resolveHostnameNative:(NSString *)host port:(int32_t)port { abort(); }
+ (MTSignal *)resolveHostnameUniversal:(NSString *)host port:(int32_t)port { abort(); }
+ (MTSignal *)resolveHostname:(NSString *)host port:(int32_t)port dohEndpoint:(NSString *)endpoint preference:(NSInteger)preference { abort(); }
+ (MTSignal *)resolveProxyHostname:(NSString *)host dohEndpoint:(NSString *)endpoint preference:(NSInteger)preference { return [MTSignal new]; }
@end
@implementation MTTcpConnection
+ (MTQueue *)tcpQueue { static MTQueue *queue; if (!queue) queue = [MTQueue new]; return queue; }
- (instancetype)initWithContext:(MTContext *)context datacenterId:(NSInteger)dc scheme:(MTTransportScheme *)scheme interface:(NSString *)interface usageCalculationInfo:(MTNetworkUsageCalculationInfo *)usage getLogPrefix:(NSString *(^)())prefix { return [self initRGWithContext:context datacenterId:dc scheme:scheme interface:interface usageCalculationInfo:usage getLogPrefix:prefix proxyOverride:nil]; }
- (instancetype)initRGWithContext:(MTContext *)context datacenterId:(NSInteger)dc scheme:(MTTransportScheme *)scheme interface:(NSString *)interface usageCalculationInfo:(MTNetworkUsageCalculationInfo *)usage getLogPrefix:(NSString *(^)())prefix proxyOverride:(MTSocksProxySettings *)proxy {
    if ((self = [super init])) { _scheme = scheme; _interface = interface; self.getLogPrefix = prefix; _internalId = [NSObject new]; if (proxy) { [children addObject:self]; childState[[NSValue valueWithNonretainedObject:self]] = @{@"proxy": proxy, @"sent": [NSMutableArray new]}; } } return self;
}
- (void)start { if ([self.delegate respondsToSelector:@selector(tcpConnectionOpened:)]) [self.delegate tcpConnectionOpened:self]; }
- (void)stop {}
- (void)setUsageCalculationInfo:(MTNetworkUsageCalculationInfo *)usage {}
- (void)sendDatas:(NSArray *)data completion:(void (^)(bool))completion requestQuickAck:(bool)ack expectDataInResponse:(bool)response {
    [childState[[NSValue valueWithNonretainedObject:self]][@"sent"] addObject:data]; if (completion) completion(true);
}
@end
@interface Observer : NSObject <MTTcpConnectionDelegate>
@property int opens;
@property int closes;
@property int received;
@property(copy) dispatch_block_t onOpen;
@end
@implementation Observer
- (void)tcpConnectionOpened:(MTTcpConnection *)connection { self.opens++; if (self.onOpen) self.onOpen(); }
- (void)tcpConnectionClosed:(MTTcpConnection *)connection error:(bool)error { self.closes++; }
- (void)tcpConnectionReceivedData:(MTTcpConnection *)connection networkType:(int32_t)type data:(NSData *)data { self.received++; }
@end
static MTRGProxyConnection *create(MTContext *context, Observer *observer) {
    MTRGProxyConnection *facade = [[MTRGProxyConnection alloc] initWithContext:context datacenterId:1 scheme:nil interface:nil usageCalculationInfo:nil getLogPrefix:nil]; facade.delegate = observer; return facade;
}
static NSString *address(MTTcpConnection *child) { return [childState[[NSValue valueWithNonretainedObject:child]][@"proxy"] ip]; }
int main(void) { @autoreleasepool {
    children = [NSMutableArray new]; timers = [NSMutableArray new]; childState = [NSMutableDictionary new];
    resolved = @[@"192.0.2.1", @"192.0.2.2", @"2001:db8::1"];
    MTContext *context = [MTContext new]; context.apiEnvironment = [MTApiEnvironment new]; context.apiEnvironment.rgIPVersionPreference = 4;
    context.apiEnvironment.socksProxySettings = [[MTSocksProxySettings alloc] initWithIp:@"proxy.example" port:443 username:@"u" password:@"p" secret:[@"secret" dataUsingEncoding:4]];
    Observer *observer = [Observer new]; MTRGProxyConnection *facade = create(context, observer);
    __block int completions = 0;
    [facade sendDatas:@[[NSData dataWithBytes:"request" length:7]] completion:^(bool success) { NSCAssert(success, @"Packet accepted"); completions++; } requestQuickAck:true expectDataInResponse:true];
    [facade start]; MTTcpConnection *first = children.lastObject; id<MTTcpConnectionDelegate> lateDelegate = first.delegate;
    NSCAssert([address(first) isEqual:resolved[0]] && observer.opens == 1 && completions == 1, @"First ordered IP, queued send");
    [timers.lastObject fire]; MTTcpConnection *second = children.lastObject;
    NSCAssert(first != second && [address(second) isEqual:resolved[1]] && observer.opens == 1 && completions == 1, @"Timeout rotates, new child, exactly-once callback");
    NSCAssert([childState[[NSValue valueWithNonretainedObject:second]][@"sent"] count] == 1, @"Unconfirmed handshake is replayed");
    MTSocksProxySettings *childProxy = childState[[NSValue valueWithNonretainedObject:second]][@"proxy"];
    NSCAssert([childProxy.secret isEqual:context.apiEnvironment.socksProxySettings.secret] && [childProxy.password isEqual:@"p"], @"Authentication preserved");
    [lateDelegate tcpConnectionClosed:first error:true]; NSCAssert(children.lastObject == second, @"Stale close ignored");
    [second.delegate tcpConnectionReceivedData:second networkType:0 data:[NSData data]];
    [timers.lastObject fire]; NSCAssert(observer.received == 1 && children.lastObject == second, @"Server reply confirms attempt");
    [second.delegate tcpConnectionClosed:second error:true]; NSCAssert(observer.closes == 1 && children.lastObject == second, @"Confirmed disconnect uses outer reconnect");
    [facade stop]; NSCAssert(observer.closes == 1, @"Stop closes once");
    observer = [Observer new]; facade = create(context, observer); [facade start];
    NSCAssert([address(children.lastObject) isEqual:resolved[1]], @"Successful IP promoted within preferred family");
    [facade stop]; NSUInteger count = children.count; [timers.lastObject fire]; NSCAssert(children.count == count && observer.closes == 1, @"Cancellation invalidates timeout");
    context.apiEnvironment.rgIPVersionPreference = 6; resolved = @[@"2001:db8::1", @"192.0.2.1"];
    observer = [Observer new]; facade = create(context, observer); [facade start];
    NSCAssert([address(children.lastObject) isEqual:resolved[0]], @"Family preference isolated from cached success");
    [facade tcpConnectionClosed:children.lastObject error:true];
    NSCAssert([address(children.lastObject) isEqual:resolved[1]], @"Connection error falls back to other family");
    [facade tcpConnectionClosed:children.lastObject error:true]; NSCAssert(observer.closes == 1, @"Exhaustion closes");
    lookupFails = true; observer = [Observer new]; facade = create(context, observer);
    __block int failures = 0;
    [facade sendDatas:@[[NSData data]] completion:^(bool ok) { NSCAssert(!ok, @"Lookup failure"); failures++; } requestQuickAck:false expectDataInResponse:true]; [facade start];
    NSCAssert(failures == 1 && observer.closes == 1, @"DNS failure completes pending packet");
    lookupFails = false; context.apiEnvironment.rgIPVersionPreference = 0;
    context.apiEnvironment.socksProxySettings.secret = nil;
    resolved = @[@"192.0.2.1", @"2001:db8::1"];
    observer = [Observer new]; facade = create(context, observer); [facade start];
    [facade tcpConnectionClosed:children.lastObject error:true];
    [facade tcpConnectionReceivedQuickAck:children.lastObject quickAck:1]; [facade stop];
    facade = create(context, [Observer new]); [facade start];
    NSCAssert([address(children.lastObject) isEqual:resolved[1]], @"Automatic mode promotes successful family; SOCKS5 has no MTProxy secret");
    [facade stop];
    observer = [Observer new]; facade = create(context, observer); [facade start];
    [facade sendDatas:@[[NSMutableData dataWithLength:8 * 1024 * 1024 + 1]] completion:nil requestQuickAck:false expectDataInResponse:true];
    NSCAssert(observer.closes == 1, @"Unresponsive replay window is bounded");
    observer = [Observer new]; facade = create(context, observer);
    __weak MTRGProxyConnection *reentrant = facade;
    observer.onOpen = ^{ [reentrant sendDatas:@[[NSData data]] completion:nil requestQuickAck:false expectDataInResponse:true]; };
    [facade sendDatas:@[[NSData data]] completion:nil requestQuickAck:false expectDataInResponse:true]; [facade start];
    NSCAssert([childState[[NSValue valueWithNonretainedObject:children.lastObject]][@"sent"] count] == 2, @"Sending from the opened callback does not duplicate replay");
    [facade stop];
    puts("Proxy facade: ordered IPs, timeout/error rotation, fresh children, replay, auth preservation, success cache, family isolation, stale callbacks, cancellation and exactly-once completion passed.");
} return 0; }
