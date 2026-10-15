// MARK: Regram — only HTTP transport is replaced; DNS parsing, policy, signals and timers are production code.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "MTDNS.h"
#import "MTRGIPPolicy.h"
#import "MTRGDoHResolver.h"
#import "MTRGDNSMessage.h"
#import <MtProtoKit/MTSignal.h>
static NSLock *statsLock;
static NSMutableArray<NSURLRequest *> *requests;
static NSUInteger cancellations;
static NSUInteger count(NSString *name, int type) {
    [statsLock lock]; NSUInteger result=0;
    for (NSURLRequest *request in requests) {
        NSURLComponents *url=[NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:false];
        NSString *host=nil,*kind=nil;
        for (NSURLQueryItem *item in url.queryItems) { if ([item.name isEqual:@"name"]) host=item.value; if ([item.name isEqual:@"type"]) kind=item.value; }
        if ([host isEqual:name] && kind.intValue==type) result++;
    }
    [statsLock unlock];return result;
}
@interface RGFixtureDNSProtocol : NSURLProtocol
@property bool stopped;
@end
@implementation RGFixtureDNSProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return true; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    [statsLock lock]; [requests addObject:self.request]; [statsLock unlock];
    NSURLComponents *url=[NSURLComponents componentsWithURL:self.request.URL resolvingAgainstBaseURL:false];
    NSString *name=@"wire.example";int type=1;
    for (NSURLQueryItem *item in url.queryItems) { if ([item.name isEqual:@"name"]) name=item.value; if ([item.name isEqual:@"type"]) type=item.value.intValue; }
    if ([name isEqual:@"race.example"] && [url.host isEqual:@"dns.google"]) return;
    NSTimeInterval delay=[name isEqual:@"coalesce.example"] || [name isEqual:@"cancel.example"] ? 0.12 : 0.005;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{
        if (self.stopped) return;
        NSData *data;
        NSInteger status=200;
        if ([url.host isEqual:@"invalid.resolver.example"]) data=[@"<html>bad response</html>" dataUsingEncoding:4];
        else if ([url.host isEqual:@"wire.resolver.example"]) {
            if (![self.request.HTTPMethod isEqual:@"POST"]) { status=415; data=[NSData data]; }
            else {
                NSMutableData *wire=[[MTRGDNSMessage queryForHost:@"wire.example" type:1] mutableCopy];
                uint8_t *bytes=wire.mutableBytes;bytes[2]=0x81;bytes[3]=0x80;bytes[7]=1;
                uint8_t answer[]={0xc0,0x0c,0,1,0,1,0,0,0,60,0,4,192,0,2,9};[wire appendBytes:answer length:sizeof(answer)];data=wire;
            }
        } else {
            NSArray *answer=[name isEqual:@"missing6.example"] && type==28 ? @[] : @[@{@"name":name,@"type":@(type),@"TTL":@60,@"data":type==1?@"192.0.2.1":type==28?@"2001:db8::2":@"\"c3ludGhldGlj\""}];
            data=[NSJSONSerialization dataWithJSONObject:@{@"Status":@0,@"Question":@[@{@"name":name,@"type":@(type)}],@"Answer":answer} options:0 error:nil];
        }
        NSURL *responseURL=[url.host isEqual:@"redirect.resolver.example"]?[NSURL URLWithString:@"https://different.example/dns-query"]:self.request.URL;
        NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:responseURL statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/dns-json",@"Date":@"Thu, 15 Oct 2026 00:00:00 GMT"}];
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [self.client URLProtocol:self didLoadData:data];[self.client URLProtocolDidFinishLoading:self];
    });
}
- (void)stopLoading { self.stopped=true;[statsLock lock];cancellations++;[statsLock unlock]; }
@end
@interface NSURLSessionConfiguration (RGDNSFixture)
+ (NSURLSessionConfiguration *)rgFixtureEphemeral;
@end
@implementation NSURLSessionConfiguration (RGDNSFixture)
+ (NSURLSessionConfiguration *)rgFixtureEphemeral {
    NSURLSessionConfiguration *config=[self rgFixtureEphemeral];config.protocolClasses=@[RGFixtureDNSProtocol.class];return config;
}
@end
static id result(MTSignal *signal, bool shouldFail) {
    dispatch_semaphore_t semaphore=dispatch_semaphore_create(0);__block id value;__block bool failed=false;
    id<MTDisposable> disposable=[signal startWithNext:^(id next){value=next;dispatch_semaphore_signal(semaphore);} error:^(__unused id error){failed=true;dispatch_semaphore_signal(semaphore);} completed:^{}];
    NSCAssert(dispatch_semaphore_wait(semaphore,dispatch_time(DISPATCH_TIME_NOW,4*NSEC_PER_SEC))==0,@"Resolver completion timeout");
    [disposable dispose];NSCAssert(failed==shouldFail,@"Unexpected DNS result");return value;
}
static MTSignal *resolve(NSString *host, NSInteger policy) { return [MTDNS resolveProxyHostname:host dohEndpoint:@"https://resolver.example" preference:policy useSystemDNS:false]; }
int main(void) { @autoreleasepool {
    statsLock=[NSLock new];requests=[NSMutableArray new];
    Method original=class_getClassMethod(NSURLSessionConfiguration.class,@selector(ephemeralSessionConfiguration));
    Method replacement=class_getClassMethod(NSURLSessionConfiguration.class,@selector(rgFixtureEphemeral));method_exchangeImplementations(original,replacement);
    NSArray *mixed=@[@"2001:db8::1",@"192.0.2.1",@"2001:db8::1",@"192.0.2.2",@"bad"];
    NSCAssert([MTRGOrderIPs(mixed,0) isEqual:(@[@"2001:db8::1",@"192.0.2.1",@"192.0.2.2"])],@"Automatic keeps upstream order and deduplicates");
    NSCAssert([MTRGOrderIPs(mixed,1) isEqual:(@[@"192.0.2.1",@"192.0.2.2"])],@"IPv4 only");
    NSCAssert([MTRGOrderIPs(mixed,2) isEqual:(@[@"2001:db8::1"])],@"IPv6 only");
    NSCAssert([[MTRGOrderIPs(mixed,4) firstObject] isEqual:@"192.0.2.1"] && [[MTRGOrderIPs(mixed,6) firstObject] isEqual:@"2001:db8::1"],@"Family preference order");
    NSArray *v4=result(resolve(@"strict4.example",1),false);NSCAssert(v4.count==1 && [v4[0] isEqual:@"192.0.2.1"] && count(@"strict4.example",28)==0,@"Strict v4 never queries v6");
    NSArray *v6=result(resolve(@"strict6.example",2),false);NSCAssert(v6.count==1 && [v6[0] isEqual:@"2001:db8::2"] && count(@"strict6.example",1)==0,@"Strict v6 never queries v4");
    result(resolve(@"missing6.example",2),true);NSCAssert(count(@"missing6.example",1)==0,@"Strict v6 never falls back to v4");
    NSCAssert([[result(resolve(@"missing6.example",6),false) firstObject] isEqual:@"192.0.2.1"],@"Preferred v6 can fall back");
    NSCAssert([[result(resolve(@"both.example",6),false) firstObject] isEqual:@"2001:db8::2"],@"Prefer v6");
    NSUInteger before=requests.count;
    result([MTDNS resolveProxyHostname:@"192.0.2.1" dohEndpoint:nil preference:2 useSystemDNS:false],true);
    result([MTDNS resolveProxyHostname:@"2001:db8::1" dohEndpoint:nil preference:1 useSystemDNS:false],true);
    NSCAssert(requests.count==before,@"Wrong-family literals fail without DNS");
    NSArray *native=result([MTDNS resolveProxyHostname:@"localhost" dohEndpoint:nil preference:1 useSystemDNS:true],false);
    for (NSString *address in native) NSCAssert(MTRGAllowsIP(address,1),@"Native strict policy");
    NSCAssert(requests.count==before,@"System DNS bypasses DoH");
    id cached=result([MTRGDoHResolver queryHostname:@"cached.example" type:1 endpoint:@"https://resolver.example" useCache:true],false);
    NSCAssert([cached[@"addresses"] count]==1,@"JSON result");
    result([MTRGDoHResolver queryHostname:@"cached.example" type:1 endpoint:@"https://resolver.example" useCache:true],false);NSCAssert(count(@"cached.example",1)==1,@"TTL cache");
    result([MTRGDoHResolver queryHostname:@"cached.example" type:1 endpoint:@"https://resolver.example" useCache:false],false);NSCAssert(count(@"cached.example",1)==2,@"Diagnostics bypass cache");
    dispatch_semaphore_t done=dispatch_semaphore_create(0);__block int first=0,second=0;
    MTSignal *shared=[MTRGDoHResolver queryHostname:@"coalesce.example" type:1 endpoint:@"https://resolver.example" useCache:true];
    id<MTDisposable> a=[shared startWithNext:^(__unused id next){first++;}];
    id<MTDisposable> b=[shared startWithNext:^(__unused id next){second++;dispatch_semaphore_signal(done);}];
    [a dispose];NSCAssert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC))==0,@"Coalesced waiter");[b dispose];
    NSCAssert(first==0 && second==1 && count(@"coalesce.example",1)==1,@"Coalescing and independent cancellation");
    result([MTRGDoHResolver queryHostname:@"race.example" type:1 endpoint:nil useCache:true],false);NSCAssert(count(@"race.example",1)==2,@"Built-in second provider races after 800ms");
    id wire=result([MTRGDoHResolver queryHostname:@"wire.example" type:1 endpoint:@"https://wire.resolver.example" useCache:true],false);NSCAssert([wire[@"addresses"] isEqual:(@[@"192.0.2.9"])],@"Legacy RFC8484 endpoint");
    result([MTRGDoHResolver queryHostname:@"bad.example" type:1 endpoint:@"https://invalid.resolver.example" useCache:true],true);
    NSCAssert([[MTRGDoHResolver lastFailureForEndpoint:@"https://invalid.resolver.example"] isEqual:@"response"],@"Custom response error is visible");
    result([MTRGDoHResolver queryHostname:@"redirect.example" type:1 endpoint:@"https://redirect.resolver.example" useCache:true],true);
    id txt=result([MTRGDoHResolver queryHostname:@"apv3.stel.com" type:16 endpoint:@"https://resolver.example" useCache:true],false);
    NSCAssert([txt[@"records"] count]==1 && [txt[@"receivedUptime"] doubleValue]>0 && txt[@"headers"]!=nil,@"Backup TXT includes cache-age metadata");
    NSCAssert([MTRGDoHResolver normalizedEndpoint:@"https://resolver.example?token=x"]==nil && [MTRGDoHResolver normalizedEndpoint:@"http://resolver.example"]==nil,@"HTTPS endpoint validation");
    method_exchangeImplementations(original,replacement);
    puts("DNS policy: five modes, strict no-fallback/literal filtering, native DNS bypass, JSON A/AAAA/TXT, cache, coalescing/cancellation, 800ms provider race, wire compatibility, endpoint validation and error reporting passed.");
} return 0; }
