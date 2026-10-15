// MARK: Regram
#import "MTRGIPPolicy.h"
#import <arpa/inet.h>
bool MTRGIsNumericIP(NSString *address) {
    if (!address.length) return false;
    struct in_addr a; struct in6_addr b;
    return inet_pton(AF_INET, address.UTF8String, &a) == 1 || inet_pton(AF_INET6, address.UTF8String, &b) == 1;
}
bool MTRGAllowsIP(NSString *address, NSInteger policy) {
    if (!address.length) return false;
    struct in_addr a; struct in6_addr b;
    bool v4 = inet_pton(AF_INET, address.UTF8String, &a) == 1;
    bool v6 = inet_pton(AF_INET6, address.UTF8String, &b) == 1;
    if (!v4 && !v6) return false;
    return policy == MTRGIPv4Only ? v4 : policy == MTRGIPv6Only ? v6 : true;
}
NSArray<NSString *> *MTRGOrderIPs(NSArray<NSString *> *addresses, NSInteger policy) {
    NSMutableOrderedSet *ordered = [NSMutableOrderedSet orderedSet], *v4 = [NSMutableOrderedSet orderedSet], *v6 = [NSMutableOrderedSet orderedSet];
    for (id value in addresses) {
        if (![value isKindOfClass:NSString.class] || !MTRGAllowsIP(value, policy)) continue;
        NSMutableOrderedSet *family = [value containsString:@":"] ? v6 : v4;
        if (family.count >= 8 && ![family containsObject:value]) continue;
        [family addObject:value]; [ordered addObject:value];
    }
    if (policy == MTRGPreferIPv4) return [v4.array arrayByAddingObjectsFromArray:v6.array];
    if (policy == MTRGPreferIPv6) return [v6.array arrayByAddingObjectsFromArray:v4.array];
    return ordered.array;
}
