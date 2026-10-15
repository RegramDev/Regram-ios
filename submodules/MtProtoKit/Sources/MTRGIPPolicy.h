// MARK: Regram — shared address filtering for discovery, transport and proxy DNS.
#import <Foundation/Foundation.h>
typedef NS_ENUM(NSInteger, MTRGIPPolicy) {
    MTRGIPAutomatic = 0,
    MTRGIPv4Only = 1,
    MTRGIPv6Only = 2,
    MTRGPreferIPv4 = 4,
    MTRGPreferIPv6 = 6
};
bool MTRGIsNumericIP(NSString *address);
bool MTRGAllowsIP(NSString *address, NSInteger policy);
NSArray<NSString *> *MTRGOrderIPs(NSArray<NSString *> *addresses, NSInteger policy);
