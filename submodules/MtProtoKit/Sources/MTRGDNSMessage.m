// MARK: Regram
#import "MTRGDNSMessage.h"
#import <arpa/inet.h>

static uint16_t rgRead16(const uint8_t *p) { return ((uint16_t)p[0] << 8) | p[1]; }
static uint32_t rgRead32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3]; }
static NSString *rgName(const uint8_t *b, NSUInteger length, NSUInteger *offset) {
    NSUInteger p = *offset, end = 0, expanded = 0;
    NSMutableArray *labels = [NSMutableArray array]; NSMutableSet *visited = [NSMutableSet set];
    for (NSUInteger step = 0; step < 128; step++) {
        if (p >= length || [visited containsObject:@(p)]) return nil;
        [visited addObject:@(p)]; uint8_t n = b[p++];
        if ((n & 0xc0) == 0xc0) { if (p >= length) return nil; if (!end) end = p + 1; p = ((NSUInteger)(n & 0x3f) << 8) | b[p]; continue; }
        if (n & 0xc0) return nil;
        if (!n) { *offset = end ?: p; return [[labels componentsJoinedByString:@"."] lowercaseString]; }
        if (n > 63 || p + n > length || (expanded += n + 1) > 255) return nil;
        NSString *label = [[NSString alloc] initWithBytes:b + p length:n encoding:NSASCIIStringEncoding]; if (!label) return nil;
        [labels addObject:label]; p += n;
    }
    return nil;
}
@implementation MTRGDNSMessage
+ (NSData *)queryForHost:(NSString *)host type:(uint16_t)type {
    if (type != 1 && type != 28) return nil;
    NSString *name = [[host lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"."]];
    NSData *ascii = [name dataUsingEncoding:NSASCIIStringEncoding]; if (!ascii || !ascii.length || ascii.length > 253) return nil;
    uint8_t header[12] = {0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0}; NSMutableData *data = [NSMutableData dataWithBytes:header length:12];
    for (NSString *part in [name componentsSeparatedByString:@"."]) {
        NSData *label = [part dataUsingEncoding:NSASCIIStringEncoding]; if (!label.length || label.length > 63) return nil;
        uint8_t size = (uint8_t)label.length; [data appendBytes:&size length:1]; [data appendData:label];
    }
    uint8_t tail[5] = {0, (uint8_t)(type >> 8), (uint8_t)type, 0, 1}; [data appendBytes:tail length:5]; return data;
}
+ (NSDictionary *)addressFromResponse:(NSData *)data host:(NSString *)host type:(uint16_t)type {
    NSDictionary *result = [self addressesFromResponse:data host:host type:type];
    NSString *first = [result[@"addresses"] firstObject];
    return first ? @{@"address": first, @"ttl": result[@"ttl"]} : nil;
}
+ (NSDictionary *)addressesFromResponse:(NSData *)data host:(NSString *)host type:(uint16_t)type {
    if (data.length < 12 || data.length > 65535) return nil;
    const uint8_t *b = data.bytes;
    if (rgRead16(b) != 0 || (b[2] & 0x80) == 0 || (b[2] & 0x7a) != 0 || (b[3] & 0x0f) != 0 || rgRead16(b + 4) != 1) return nil;
    NSString *name = [[host lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"."]];
    NSUInteger offset = 12; NSString *question = rgName(b, data.length, &offset);
    if (![question isEqualToString:name] || offset + 4 > data.length || rgRead16(b + offset) != type || rgRead16(b + offset + 2) != 1) return nil;
    offset += 4; NSMutableDictionary *aliases = [NSMutableDictionary dictionary]; NSMutableArray *answers = [NSMutableArray array];
    uint16_t count = rgRead16(b + 6); if (count > 1024) return nil;
    for (uint16_t i = 0; i < count; i++) {
        NSString *owner = rgName(b, data.length, &offset); if (!owner || offset + 10 > data.length) return nil;
        uint16_t kind = rgRead16(b + offset), cls = rgRead16(b + offset + 2), size = rgRead16(b + offset + 8); uint32_t ttl = rgRead32(b + offset + 4);
        offset += 10; if (offset + size > data.length) return nil;
        if (cls == 1 && kind == 5) { NSUInteger p = offset; NSString *target = rgName(b, data.length, &p); if (!target || p > offset + size) return nil; aliases[owner] = @{@"name": target, @"ttl": @(ttl)}; }
        else if (cls == 1 && kind == type && ((type == 1 && size == 4) || (type == 28 && size == 16))) {
            char ip[INET6_ADDRSTRLEN]; if (inet_ntop(type == 1 ? AF_INET : AF_INET6, b + offset, ip, sizeof(ip))) [answers addObject:@{@"owner": owner, @"address": [NSString stringWithUTF8String:ip], @"ttl": @(ttl)}];
        }
        offset += size;
    }
    uint32_t ttl = UINT32_MAX; NSMutableSet *seen = [NSMutableSet set];
    for (NSUInteger i = 0; i < 16 && ![seen containsObject:name]; i++) {
        [seen addObject:name]; NSMutableOrderedSet *addresses = [NSMutableOrderedSet orderedSet];
        for (NSDictionary *answer in answers) if ([answer[@"owner"] isEqualToString:name]) {
            [addresses addObject:answer[@"address"]]; ttl = MIN(ttl, [answer[@"ttl"] unsignedIntValue]);
        }
        if (addresses.count) return @{@"addresses": addresses.array, @"ttl": @(ttl)};
        NSDictionary *alias = aliases[name]; if (!alias) return nil; ttl = MIN(ttl, [alias[@"ttl"] unsignedIntValue]); name = alias[@"name"];
    }
    return nil;
}
+ (NSDictionary *)addressesFromJSONResponse:(NSData *)data host:(NSString *)host type:(uint16_t)type {
    if (!data.length || data.length > 65535 || (type != 1 && type != 28)) return nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![object isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *json = object;
    if (![json[@"Status"] isKindOfClass:NSNumber.class]) return nil;
    NSInteger status = [json[@"Status"] integerValue];
    if (status != 0 && status != 3) return nil;
    NSString *name = [[host lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"."]];
    if (json[@"Question"]) {
        NSArray *questions = json[@"Question"];
        if (![questions isKindOfClass:NSArray.class] || questions.count != 1 || ![questions[0] isKindOfClass:NSDictionary.class]) return nil;
        id question = questions[0]; id questionName = question[@"name"];
        if (![questionName isKindOfClass:NSString.class] || ![[[questionName lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"."]] isEqualToString:name] || ![question[@"type"] isKindOfClass:NSNumber.class] || [question[@"type"] unsignedIntValue] != type) return nil;
    }
    NSArray *records = json[@"Answer"] ?: @[];
    if (![records isKindOfClass:NSArray.class] || records.count > 1024) return nil;
    if (status == 3) return records.count ? nil : @{@"addresses": @[], @"ttl": @0};
    NSMutableDictionary *aliases = [NSMutableDictionary dictionary]; NSMutableArray *answers = [NSMutableArray array];
    for (id record in records) {
        if (![record isKindOfClass:NSDictionary.class] || ![record[@"name"] isKindOfClass:NSString.class] || ![record[@"type"] isKindOfClass:NSNumber.class] || ![record[@"data"] isKindOfClass:NSString.class]) continue;
        NSString *owner = [[record[@"name"] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"."]];
        uint32_t ttl = [record[@"TTL"] isKindOfClass:NSNumber.class] ? (uint32_t)MAX(0, MIN(UINT32_MAX, [record[@"TTL"] doubleValue])) : 0;
        uint32_t kind = [record[@"type"] unsignedIntValue];
        if (kind == 5) aliases[owner] = @{@"name": [[record[@"data"] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"."]], @"ttl": @(ttl)};
        else if (kind == type) {
            uint8_t bytes[16]; int family = type == 1 ? AF_INET : AF_INET6;
            if (inet_pton(family, [record[@"data"] UTF8String], bytes) == 1) {
                char ip[INET6_ADDRSTRLEN]; inet_ntop(family, bytes, ip, sizeof(ip));
                [answers addObject:@{@"owner": owner, @"address": [NSString stringWithUTF8String:ip], @"ttl": @(ttl)}];
            }
        }
    }
    uint32_t ttl = UINT32_MAX; NSMutableSet *seen = [NSMutableSet set];
    for (NSUInteger i = 0; i < 16 && ![seen containsObject:name]; i++) {
        [seen addObject:name]; NSMutableOrderedSet *addresses = [NSMutableOrderedSet orderedSet];
        for (NSDictionary *answer in answers) if ([answer[@"owner"] isEqualToString:name]) { [addresses addObject:answer[@"address"]]; ttl = MIN(ttl, [answer[@"ttl"] unsignedIntValue]); }
        if (addresses.count) return @{@"addresses": addresses.array, @"ttl": @(ttl)};
        NSDictionary *alias = aliases[name]; if (!alias) return @{@"addresses": @[], @"ttl": @0};
        ttl = MIN(ttl, [alias[@"ttl"] unsignedIntValue]); name = alias[@"name"];
    }
    return nil;
}

+ (NSDictionary *)textRecordsFromJSONResponse:(NSData *)data host:(NSString *)host {
    if (!data.length || data.length > 65535) return nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![object isKindOfClass:NSDictionary.class] || ![object[@"Status"] isKindOfClass:NSNumber.class] || [object[@"Status"] integerValue] != 0) return nil;
    NSString *name = [[host lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"."]];
    NSArray *questions = object[@"Question"];
    if (questions) {
        if (![questions isKindOfClass:NSArray.class] || questions.count != 1 || ![questions[0] isKindOfClass:NSDictionary.class]) return nil;
        id question = questions[0];
        if (![question[@"name"] isKindOfClass:NSString.class] || ![[[question[@"name"] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"."]] isEqualToString:name] || ![question[@"type"] isKindOfClass:NSNumber.class] || [question[@"type"] intValue] != 16) return nil;
    }
    NSArray *records = object[@"Answer"];
    if (![records isKindOfClass:NSArray.class] || records.count > 1024) return nil;
    NSMutableDictionary *aliases = [NSMutableDictionary dictionary]; NSMutableArray *answers = [NSMutableArray array];
    for (id record in records) {
        if (![record isKindOfClass:NSDictionary.class] || ![record[@"name"] isKindOfClass:NSString.class] || ![record[@"data"] isKindOfClass:NSString.class] || ![record[@"type"] isKindOfClass:NSNumber.class]) continue;
        NSString *owner = [[record[@"name"] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"."]];
        uint32_t ttl = [record[@"TTL"] isKindOfClass:NSNumber.class] ? (uint32_t)MAX(0, MIN(UINT32_MAX, [record[@"TTL"] doubleValue])) : 0;
        if ([record[@"type"] intValue] == 5) aliases[owner] = @{@"name": [[record[@"data"] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"."]], @"ttl": @(ttl)};
        else if ([record[@"type"] intValue] == 16) [answers addObject:@{@"owner": owner, @"value": record[@"data"], @"ttl": @(ttl)}];
    }
    uint32_t ttl = UINT32_MAX; NSMutableSet *seen = [NSMutableSet set];
    for (NSUInteger i = 0; i < 16 && ![seen containsObject:name]; i++) {
        [seen addObject:name]; NSMutableArray *values = [NSMutableArray array];
        for (NSDictionary *answer in answers) if ([answer[@"owner"] isEqualToString:name]) { [values addObject:answer[@"value"]]; ttl = MIN(ttl, [answer[@"ttl"] unsignedIntValue]); }
        if (values.count) return @{@"records": values, @"ttl": @(ttl)};
        NSDictionary *alias = aliases[name]; if (!alias) return nil;
        ttl = MIN(ttl, [alias[@"ttl"] unsignedIntValue]); name = alias[@"name"];
    }
    return nil;
}

@end
