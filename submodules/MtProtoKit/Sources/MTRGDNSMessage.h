// MARK: Regram — bounded DNS wire codec for RFC 8484.
#import <Foundation/Foundation.h>
@interface MTRGDNSMessage : NSObject
+ (NSData *)queryForHost:(NSString *)host type:(uint16_t)type;
+ (NSDictionary *)addressesFromResponse:(NSData *)data host:(NSString *)host type:(uint16_t)type;
+ (NSDictionary *)addressesFromJSONResponse:(NSData *)data host:(NSString *)host type:(uint16_t)type;
+ (NSDictionary *)textRecordsFromJSONResponse:(NSData *)data host:(NSString *)host;
+ (NSDictionary *)addressFromResponse:(NSData *)data host:(NSString *)host type:(uint16_t)type;
@end
