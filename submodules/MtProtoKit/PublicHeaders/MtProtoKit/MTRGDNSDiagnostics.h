// MARK: Regram — diagnostic queries use the same resolver as Telegram's transport.
#import <Foundation/Foundation.h>
#import <MtProtoKit/MTSignal.h>
NS_ASSUME_NONNULL_BEGIN
@interface MTRGDNSDiagnostics : NSObject
+ (MTSignal *)queryHostname:(NSString *)hostname dohEndpoint:(nullable NSString *)endpoint family:(NSInteger)family;
@end
NS_ASSUME_NONNULL_END
