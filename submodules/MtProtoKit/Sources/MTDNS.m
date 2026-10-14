#import "MTRGDNSMessage.h" // MARK: Regram
#import <MtProtoKit/MTAtomic.h>
#import "MTDNS.h"

#import <arpa/inet.h>
#include <netinet/tcp.h>
#import <fcntl.h>
#import <ifaddrs.h>
#import <netdb.h>
#import <netinet/in.h>
#import <net/if.h>

#import <MtProtoKit/MTQueue.h>
#import <MtProtoKit/MTSignal.h>
#import <MtProtoKit/MTBag.h>
#import <MtProtoKit/MTEncryption.h>
#import <MtProtoKit/MTRequestMessageService.h>
#import <MtProtoKit/MTRequest.h>
#import <MtProtoKit/MTContext.h>
#import <MtProtoKit/MTApiEnvironment.h>
#import <MtProtoKit/MTDatacenterAddress.h>
#import <MtProtoKit/MTDatacenterAddressSet.h>
#import <MtProtoKit/MTProto.h>
#import <MtProtoKit/MTSerialization.h>
#import <MtProtoKit/MTLogging.h>

#import <netinet/in.h>
#import <arpa/inet.h>

@interface MTDNSHostContext : NSObject {
    MTBag *_subscribers;
    id<MTDisposable> _disposable;
}

@end

@implementation MTDNSHostContext

- (instancetype)initWithHost:(NSString *)host disposable:(id<MTDisposable>)disposable {
    self = [super init];
    if (self != nil) {
        _subscribers = [[MTBag alloc] init];
        _disposable = disposable;
    }
    return self;
}

- (void)dealloc {
    [_disposable dispose];
}

- (NSInteger)addSubscriber:(void (^)(NSString *))completion {
    return [_subscribers addItem:[completion copy]];
}

- (void)removeSubscriber:(NSInteger)index {
    [_subscribers removeItem:index];
}

- (bool)isEmpty {
    return [_subscribers isEmpty];
}

- (void)complete:(NSString *)result {
    for (void (^completion)(NSString *) in [_subscribers copyItems]) {
        completion(result);
    }
}

@end

@interface MTDNSContext : NSObject {
    NSMutableDictionary<NSString *, MTDNSHostContext *> *_contexts;
}

@end

@implementation MTDNSContext

+ (MTQueue *)sharedQueue {
    static MTQueue *queue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = [[MTQueue alloc] init];
    });
    return queue;
}

+ (MTSignal *)shared {
    return [[[MTSignal alloc] initWithGenerator:^id<MTDisposable>(MTSubscriber *subscriber) {
        static MTDNSContext *instance = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            instance = [[MTDNSContext alloc] init];
        });
        [subscriber putNext:instance];
        [subscriber putCompletion];
        return nil;
    }] startOn:[self sharedQueue]];
}

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _contexts = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (id<MTDisposable>)subscribe:(NSString *)host port:(int32_t)port completion:(void (^)(NSString *))completion {
    NSString *key = [NSString stringWithFormat:@"%@:%d", host, port];
    
    MTMetaDisposable *disposable = nil;
    if (_contexts[key] == nil) {
        disposable = [[MTMetaDisposable alloc] init];
        _contexts[key] = [[MTDNSHostContext alloc] initWithHost:host disposable:disposable];
    }
    MTDNSHostContext *context = _contexts[key];
    
    NSInteger index = [context addSubscriber:^(NSString *result) {
        if (completion) {
            completion(result);
        }
    }];
    
    if (disposable != nil) {
        __weak MTDNSContext *weakSelf = self;
        [disposable setDisposable:[[[self performLookup:host port:port] deliverOn:[MTDNSContext sharedQueue]] startWithNextStrict:^(NSString *result) {
            __strong MTDNSContext *strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            if (strongSelf->_contexts[key] != nil) {
                [strongSelf->_contexts[key] complete:result];
                [strongSelf->_contexts removeObjectForKey:key];
            }
        } file:__FILE_NAME__ line:__LINE__]];
    }
    
    __weak MTDNSContext *weakSelf = self;
    __weak MTDNSHostContext *weakContext = context;
    return [[MTBlockDisposable alloc] initWithBlock:^{
        [[MTDNSContext sharedQueue] dispatchOnQueue:^{
            __strong MTDNSContext *strongSelf = weakSelf;
            __strong MTDNSHostContext *strongContext = weakContext;
            if (strongSelf == nil || strongContext == nil) {
                return;
            }
            if (strongSelf->_contexts[key] != nil && strongSelf->_contexts[key] == strongContext) {
                [strongSelf->_contexts[key] removeSubscriber:index];
                if ([strongSelf->_contexts[key] isEmpty]) {
                    [strongSelf->_contexts removeObjectForKey:key];
                }
            }
        }];
    }];
}

- (MTSignal *)performLookup:(NSString *)host port:(int32_t)port {
    MTSignal *lookupOnce = [[MTSignal alloc] initWithGenerator:^id<MTDisposable>(MTSubscriber *subscriber) {
        MTMetaDisposable *disposable = [[MTMetaDisposable alloc] init];
        [[MTQueue concurrentDefaultQueue] dispatchOnQueue:^{
            struct addrinfo hints, *res, *res0;
            
            memset(&hints, 0, sizeof(hints));
            hints.ai_family   = PF_UNSPEC;
            hints.ai_socktype = SOCK_STREAM;
            hints.ai_protocol = IPPROTO_TCP;
            
            NSString *portStr = [NSString stringWithFormat:@"%d", port];
            if (MTLogEnabled()) {
                MTLog(@"[MTDNS lookup %@:%@]", host, portStr);
            }
            int gai_error = getaddrinfo([host UTF8String], [portStr UTF8String], &hints, &res0);
            
            NSString *address4 = nil;
            NSString *address6 = nil;
            
            if (gai_error == 0) {
                for(res = res0; res; res = res->ai_next) {
                    if ((address4 == nil) && (res->ai_family == AF_INET)) {
                        struct sockaddr_in *addr_in = (struct sockaddr_in *)res->ai_addr;
                        char *s = malloc(INET_ADDRSTRLEN);
                        inet_ntop(AF_INET, &(addr_in->sin_addr), s, INET_ADDRSTRLEN);
                        address4 = [NSString stringWithUTF8String:s];
                        free(s);
                    } else if ((address6 == nil) && (res->ai_family == AF_INET6)) {
                        struct sockaddr_in6 *addr_in6 = (struct sockaddr_in6 *)res->ai_addr;
                        char *s = malloc(INET6_ADDRSTRLEN);
                        inet_ntop(AF_INET6, &(addr_in6->sin6_addr), s, INET6_ADDRSTRLEN);
                        address6 = [NSString stringWithUTF8String:s];
                        free(s);
                    }
                }
                freeaddrinfo(res0);
            }
            
            if (address4 != nil) {
                if (MTLogEnabled()) {
                    MTLog(@"[MTDNS lookup %@:%@ success ipv4]", host, portStr);
                }
                [subscriber putNext:address4];
                [subscriber putCompletion];
            } else if (address6 != nil) {
                if (MTLogEnabled()) {
                    MTLog(@"[MTDNS lookup %@:%@ success ipv6]", host, portStr);
                }
                [subscriber putNext:address6];
                [subscriber putCompletion];
            } else {
                if (MTLogEnabled()) {
                    MTLog(@"[MTDNS lookup %@:%@ error %d]", host, portStr, gai_error);
                }
                [subscriber putError:nil];
            }
        }];
        return disposable;
    }];
    return [[[lookupOnce catch:^MTSignal *(__unused id error) {
        return [[MTSignal complete] delay:2.0 onQueue:[MTDNSContext sharedQueue]];
    }] restart] take:1];
}

@end

@implementation MTDNS

+ (MTSignal *)resolveHostnameNative:(NSString *)hostname port:(int32_t)port {
    return [[MTDNSContext shared] mapToSignal:^MTSignal *(MTDNSContext *context) {
        return [[MTSignal alloc] initWithGenerator:^id<MTDisposable>(MTSubscriber *subscriber) {
            return [context subscribe:hostname port:port completion:^(NSString *result) {
                [subscriber putNext:result];
                [subscriber putCompletion];
            }];
        }];
    }];
}

+ (MTSignal *)resolveHostnameUniversal:(NSString *)hostname port:(int32_t)port {
    // This used to race the native lookup against an HTTPS query to
    // https://google.com/resolve, Google's DNS-over-HTTPS reached through a spoofed Host
    // header. That endpoint answers 404 today (verified 2026-09), the status code was
    // never checked, and only successes were cached - so every connection through a
    // hostname proxy paid one dead HTTPS round trip, and an unreachable proxy turned that
    // into hundreds per push in the notification extension (bugs.telegram.org/c/64534).
    // The native lookup below coalesces concurrent callers and retries every 2 s until
    // it succeeds; the 10 s bound keeps the old fallback of eventually handing the socket
    // the bare hostname, so an unresolvable name still fails within the transport's 20 s
    // watchdog rather than stalling it. `take:1` closes a narrow window: `single:` emits
    // its next and its completion as two steps, and a native answer landing in between
    // would reach MTTcpConnection as a second address and make it call connectToHost:
    // again on a socket that is already connecting.
    return [[[self resolveHostnameNative:hostname port:port] timeout:10.0 onQueue:[MTQueue concurrentDefaultQueue] orSignal:[MTSignal single:hostname]] take:1];
}


// MARK: Regram — HTTPS wire-format lookup, bounded TTL cache, cancellation and no silent DNS downgrade.
+ (MTSignal *)resolveHostname:(NSString *)hostname port:(int32_t)port dohEndpoint:(NSString *)endpoint preference:(NSInteger)preference {
    struct in_addr v4; struct in6_addr v6;
    if (inet_pton(AF_INET, hostname.UTF8String, &v4) == 1 || inet_pton(AF_INET6, hostname.UTF8String, &v6) == 1) return [MTSignal single:hostname];
    if (endpoint.length == 0 && preference != 6) return [self resolveHostnameUniversal:hostname port:port];
    if (endpoint.length == 0) {
        MTSignal *native = [[MTSignal alloc] initWithGenerator:^id<MTDisposable>(MTSubscriber *subscriber) {
            MTAtomic *cancelled = [[MTAtomic alloc] initWithValue:@false];
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                struct addrinfo hints = {0}, *result = NULL; hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM;
                NSString *chosen = nil;
                if (getaddrinfo(hostname.UTF8String, NULL, &hints, &result) == 0) {
                    for (struct addrinfo *a = result; a != NULL; a = a->ai_next) {
                        char ip[INET6_ADDRSTRLEN]; void *address = a->ai_family == AF_INET6 ? (void *)&((struct sockaddr_in6 *)a->ai_addr)->sin6_addr : a->ai_family == AF_INET ? (void *)&((struct sockaddr_in *)a->ai_addr)->sin_addr : NULL;
                        if (address && inet_ntop(a->ai_family, address, ip, sizeof(ip))) { if (!chosen || a->ai_family == AF_INET6) chosen = [NSString stringWithUTF8String:ip]; if (a->ai_family == AF_INET6) break; }
                    }
                    freeaddrinfo(result);
                }
                if (![[cancelled value] boolValue]) { if (chosen) { [subscriber putNext:chosen]; [subscriber putCompletion]; } else [subscriber putError:nil]; }
            });
            return [[MTBlockDisposable alloc] initWithBlock:^{ [cancelled swap:@true]; }];
        }];
        return [native timeout:10.0 onQueue:[MTQueue concurrentDefaultQueue] orSignal:[MTSignal fail:nil]];
    }
    NSURLComponents *components = [NSURLComponents componentsWithString:endpoint];
    if (![components.scheme.lowercaseString isEqualToString:@"https"] || !components.host.length || components.user || components.password || components.fragment) return [MTSignal fail:nil];
    static NSURLSession *session; static NSCache *cache; static dispatch_once_t once;
    dispatch_once(&once, ^{ NSURLSessionConfiguration *c = NSURLSessionConfiguration.ephemeralSessionConfiguration; c.URLCache = nil; c.HTTPCookieStorage = nil; c.timeoutIntervalForRequest = 6; c.timeoutIntervalForResource = 8; session = [NSURLSession sessionWithConfiguration:c]; cache = [[NSCache alloc] init]; cache.countLimit = 128; });
    NSString *key = [NSString stringWithFormat:@"%@|%@|%ld", endpoint, hostname.lowercaseString, (long)preference];
    NSDictionary *cached = [cache objectForKey:key];
    if ([cached[@"expires"] doubleValue] > NSDate.date.timeIntervalSince1970) return [MTSignal single:cached[@"address"]];
    MTSignal *(^query)(uint16_t) = ^MTSignal *(uint16_t type) {
        return [[MTSignal alloc] initWithGenerator:^id<MTDisposable>(MTSubscriber *subscriber) {
            NSData *body = [MTRGDNSMessage queryForHost:hostname type:type]; if (!body) { [subscriber putError:nil]; return nil; }
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:components.URL]; request.HTTPMethod = @"POST"; request.HTTPBody = body;
            [request setValue:@"application/dns-message" forHTTPHeaderField:@"Content-Type"]; [request setValue:@"application/dns-message" forHTTPHeaderField:@"Accept"];
            NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
                NSDictionary *answer = !error && http.statusCode == 200 && [http.MIMEType.lowercaseString isEqualToString:@"application/dns-message"] ? [MTRGDNSMessage addressFromResponse:data host:hostname type:type] : nil;
                if (!answer) { [subscriber putError:nil]; return; }
                double ttl = MIN(3600, [answer[@"ttl"] doubleValue]); if (ttl > 0) [cache setObject:@{@"address": answer[@"address"], @"expires": @(NSDate.date.timeIntervalSince1970 + ttl)} forKey:key];
                [subscriber putNext:answer[@"address"]]; [subscriber putCompletion];
            }];
            [task resume]; return [[MTBlockDisposable alloc] initWithBlock:^{ [task cancel]; }];
        }];
    };
    uint16_t first = preference == 6 ? 28 : 1;
    return [[query(first) catch:^MTSignal *(__unused id error) { return query(first == 28 ? 1 : 28); }] take:1];
}

@end
