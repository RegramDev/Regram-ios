// MARK: Regram — run with Foundation on macOS; exercises the production DNS wire parser.
#import <Foundation/Foundation.h>
#import "MTRGDNSMessage.h"
static NSMutableData *response(NSString *host, uint16_t type, NSData *address) {
    NSMutableData *data = [[MTRGDNSMessage queryForHost:host type:type] mutableCopy];
    uint8_t *header = data.mutableBytes; header[2] = 0x81; header[3] = 0x80; header[7] = 1;
    uint8_t record[] = {0xc0, 0x0c, (uint8_t)(type >> 8), (uint8_t)type, 0, 1, 0, 0, 0, 60, 0, (uint8_t)address.length};
    [data appendBytes:record length:sizeof(record)]; [data appendData:address]; return data;
}
static int rgRunDNSTests(void) { @autoreleasepool {
    NSString *host = @"proxy.example"; uint8_t ipv4[] = {192,0,2,7};
    NSMutableData *answer = response(host, 1, [NSData dataWithBytes:ipv4 length:4]);
    NSCAssert([[MTRGDNSMessage addressFromResponse:answer host:host type:1][@"address"] isEqualToString:@"192.0.2.7"], @"Compressed A answer");
    NSMutableData *multiple = [answer mutableCopy];
    ((uint8_t *)multiple.mutableBytes)[7] = 3;
    uint8_t another[] = {0xc0,0x0c,0,1,0,1,0,0,0,30,0,4,192,0,2,8};
    [multiple appendBytes:another length:sizeof(another)];
    [multiple appendBytes:another length:sizeof(another)];
    NSDictionary *list = [MTRGDNSMessage addressesFromResponse:multiple host:host type:1];
    NSCAssert([list[@"addresses"] isEqual:(@[@"192.0.2.7", @"192.0.2.8"])], @"Ordered full address list, duplicates removed");
    NSCAssert([list[@"ttl"] intValue] == 30, @"Minimum address TTL");
    NSMutableData *cname = [[MTRGDNSMessage queryForHost:host type:1] mutableCopy];
    ((uint8_t *)cname.mutableBytes)[2] = 0x81; ((uint8_t *)cname.mutableBytes)[3] = 0x80; ((uint8_t *)cname.mutableBytes)[7] = 2;
    uint8_t alias[] = {0xc0,0x0c,0,5,0,1,0,0,0,10,0,8,5,'a','l','i','a','s',0xc0,0x12};
    NSUInteger aliasOffset = cname.length + 12;
    [cname appendBytes:alias length:sizeof(alias)];
    uint8_t aliasAnswer[] = {(uint8_t)(0xc0 | (aliasOffset >> 8)),(uint8_t)aliasOffset,0,1,0,1,0,0,0,60,0,4,192,0,2,9};
    [cname appendBytes:aliasAnswer length:sizeof(aliasAnswer)];
    NSDictionary *aliasResult = [MTRGDNSMessage addressesFromResponse:cname host:host type:1];
    NSCAssert([aliasResult[@"addresses"] isEqual:(@[@"192.0.2.9"])] && [aliasResult[@"ttl"] intValue] == 10, @"CNAME TTL bounds address cache");
    NSCAssert([MTRGDNSMessage addressFromResponse:answer host:@"other.example" type:1] == nil, @"Question mismatch rejected");
    NSCAssert([MTRGDNSMessage addressFromResponse:answer host:host type:28] == nil, @"Wrong query type rejected");
    for (NSUInteger length=0;length<answer.length;length++) NSCAssert([MTRGDNSMessage addressFromResponse:[answer subdataWithRange:NSMakeRange(0,length)] host:host type:1] == nil, @"Truncation rejected");
    uint8_t ipv6[16] = {0x20,0x01,0x0d,0xb8,0,0,0,0,0,0,0,0,0,0,0,1};
    NSCAssert([[MTRGDNSMessage addressFromResponse:response(host,28,[NSData dataWithBytes:ipv6 length:16]) host:host type:28][@"address"] isEqualToString:@"2001:db8::1"], @"AAAA answer");
    uint8_t *b=answer.mutableBytes; b[3]=0x83; NSCAssert([MTRGDNSMessage addressFromResponse:answer host:host type:1] == nil,@"NXDOMAIN rejected");b[3]=0x80;
    b[2] |= 2; NSCAssert([MTRGDNSMessage addressFromResponse:answer host:host type:1] == nil,@"Truncated flag rejected");b[2]&=~2;
    NSData *query=[MTRGDNSMessage queryForHost:host type:1]; NSUInteger offset=query.length; b=answer.mutableBytes; b[offset]=0xc0;b[offset+1]=(uint8_t)offset;
    NSCAssert([MTRGDNSMessage addressFromResponse:answer host:host type:1] == nil,@"Pointer cycle rejected");
    NSCAssert([MTRGDNSMessage queryForHost:@"bad..host" type:1] == nil,@"Empty label rejected");
    NSCAssert([MTRGDNSMessage queryForHost:[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0] type:1] == nil,@"Long label rejected");
    puts("DNS wire codec: A/AAAA, compressed names, TTL, question/type validation, truncation, NXDOMAIN and pointer cycles passed.");
} return 0; }

#if RG_STANDALONE_TESTS
int main(void) { return rgRunDNSTests(); }
#else
#import <XCTest/XCTest.h>
@interface MTRGDNSMessageTests : XCTestCase
@end
@implementation MTRGDNSMessageTests
- (void)testWireResponses { XCTAssertEqual(rgRunDNSTests(), 0); }
@end
#endif
