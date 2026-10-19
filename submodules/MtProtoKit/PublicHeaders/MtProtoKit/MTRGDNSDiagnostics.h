// MARK: Regram — diagnostic queries use the same resolver as Telegram's transport.
#import <Foundation/Foundation.h>
#import <MtProtoKit/MTSignal.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSNotificationName const MTRGDNSFailureChangedNotification;
@interface MTRGDNSDiagnostics : NSObject
+ (MTSignal *)queryHostname:(NSString *)hostname dohEndpoint:(nullable NSString *)endpoint family:(NSInteger)family;
+ (MTSignal *)queryHostname:(NSString *)hostname dohEndpoint:(nullable NSString *)endpoint family:(NSInteger)family useSystemDNS:(bool)useSystemDNS;
+ (nullable NSString *)lastFailureForEndpoint:(NSString *)endpoint NS_SWIFT_NAME(lastFailure(endpoint:));
+ (NSArray<NSString *> *)orderedAddresses:(NSArray<NSString *> *)addresses policy:(NSInteger)policy NS_SWIFT_NAME(orderedAddresses(_:policy:));
@end
NS_ASSUME_NONNULL_END
