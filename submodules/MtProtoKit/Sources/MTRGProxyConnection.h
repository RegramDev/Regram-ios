// MARK: Regram — complete child connections keep TLS/SOCKS/obfuscation state isolated per IP.
#import "MTTcpConnection.h"
@class MTSocksProxySettings;
@interface MTTcpConnection (RGProxyChild)
- (instancetype)initRGWithContext:(MTContext *)context datacenterId:(NSInteger)datacenterId scheme:(MTTransportScheme *)scheme interface:(NSString *)interface usageCalculationInfo:(MTNetworkUsageCalculationInfo *)usage getLogPrefix:(NSString *(^)())prefix proxyOverride:(MTSocksProxySettings *)proxy;
@end
@interface MTRGProxyConnection : MTTcpConnection <MTTcpConnectionDelegate>
@end
