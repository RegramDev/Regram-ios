// MARK: Regram — coalesced JSON DoH, bounded TTLs, provider racing and cancellation.
#import <Foundation/Foundation.h>
#import <MtProtoKit/MTSignal.h>
@interface MTRGDoHResolver : NSObject
+ (MTSignal *)queryHostname:(NSString *)hostname type:(uint16_t)type endpoint:(NSString *)endpoint useCache:(bool)useCache;
+ (NSMutableURLRequest *)jsonRequestForHostname:(NSString *)hostname type:(uint16_t)type endpoint:(NSString *)endpoint;
+ (NSString *)normalizedEndpoint:(NSString *)endpoint;
+ (NSString *)lastFailureForEndpoint:(NSString *)endpoint;
@end
