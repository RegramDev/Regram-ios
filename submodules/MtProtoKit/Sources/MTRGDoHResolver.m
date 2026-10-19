// MARK: Regram — DNS uses its own HTTP session and never an unresolved Telegram proxy.
#import "MTRGDoHResolver.h"
#import "MTRGDNSMessage.h"
#import <MtProtoKit/MTRGDNSDiagnostics.h>
#import <MtProtoKit/MTQueue.h>
#import <MtProtoKit/MTTimer.h>
#import <MtProtoKit/MTAtomic.h>

NSNotificationName const MTRGDNSFailureChangedNotification = @"Regram.DNS.FailureChanged";
@interface MTRGDoHLookup : NSObject
@property NSString *key;
@property NSString *cacheKey;
@property NSString *host;
@property NSString *endpoint;
@property uint16_t type;
@property bool useCache;
@property NSArray<NSString *> *providers;
@property NSMutableDictionary<NSUUID *, MTSubscriber *> *subscribers;
@property NSMutableArray<NSURLSessionDataTask *> *tasks;
@property MTTimer *timer;
@property NSUInteger started;
@property NSUInteger finished;
@property NSString *failure;
@end
@implementation MTRGDoHLookup
@end

@interface MTRGDoHResolver () <NSURLSessionTaskDelegate>
@property MTQueue *queue;
@property NSURLSession *session;
@property NSCache *cache;
@property NSCache *failures;
@property NSMutableDictionary<NSString *, MTRGDoHLookup *> *inflight;
@end
@implementation MTRGDoHResolver
+ (instancetype)shared {
    static MTRGDoHResolver *resolver; static dispatch_once_t once;
    dispatch_once(&once, ^{
        resolver = [[self alloc] init];
        resolver.queue = [[MTQueue alloc] initWithName:"Regram.DoH"];
        resolver.cache = [[NSCache alloc] init]; resolver.cache.countLimit = 128;
        resolver.failures = [[NSCache alloc] init]; resolver.failures.countLimit = 128;
        resolver.inflight = [NSMutableDictionary dictionary];
        NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        config.URLCache = nil; config.HTTPCookieStorage = nil; config.URLCredentialStorage = nil;
        config.connectionProxyDictionary = @{};
        config.timeoutIntervalForRequest = 6; config.timeoutIntervalForResource = 8;
        resolver.session = [NSURLSession sessionWithConfiguration:config delegate:resolver delegateQueue:nil];
    });
    return resolver;
}
// Never forward a proxy-hostname query to a redirect target outside the selected resolver.
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    completionHandler(nil);
}
+ (NSString *)normalizedEndpoint:(NSString *)endpoint {
    NSString *value = [endpoint stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!value.length || value.length > 2048 || [value rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) return nil;
    NSURLComponents *url = [NSURLComponents componentsWithString:value];
    if (![url.scheme.lowercaseString isEqualToString:@"https"] || !url.host.length || url.user || url.password || url.query || url.fragment || (url.port && (url.port.integerValue < 1 || url.port.integerValue > 65535))) return nil;
    if (!url.path.length || [url.path isEqualToString:@"/"]) url.path = @"/dns-query";
    return url.URL.absoluteString;
}
+ (NSMutableURLRequest *)jsonRequestForHostname:(NSString *)hostname type:(uint16_t)type endpoint:(NSString *)endpoint {
    if (type != 1 && type != 16 && type != 28) return nil;
    NSString *normalized = [self normalizedEndpoint:endpoint];
    if (!normalized || ![MTRGDNSMessage queryForHost:hostname type:type == 16 ? 1 : type]) return nil;
    NSURLComponents *url = [NSURLComponents componentsWithString:normalized];
    static const char alphabet[] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    NSMutableString *padding = [NSMutableString string];
    for (uint32_t i = 0, n = 13 + arc4random_uniform(116); i < n; i++) [padding appendFormat:@"%c", alphabet[arc4random_uniform(62)]];
    url.queryItems = @[[NSURLQueryItem queryItemWithName:@"name" value:hostname], [NSURLQueryItem queryItemWithName:@"type" value:[NSString stringWithFormat:@"%u", type]], [NSURLQueryItem queryItemWithName:@"random_padding" value:padding]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url.URL];
    [request setValue:@"application/dns-json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"Regram DNS" forHTTPHeaderField:@"User-Agent"];
    return request;
}
+ (NSString *)lastFailureForEndpoint:(NSString *)endpoint {
    NSString *key = [self normalizedEndpoint:endpoint];
    return key ? [[self shared].failures objectForKey:key] : nil;
}
- (void)setFailure:(NSString *)failure endpoint:(NSString *)endpoint {
    if (!endpoint.length) return;
    NSString *previous = [self.failures objectForKey:endpoint];
    if (failure) [self.failures setObject:failure forKey:endpoint]; else [self.failures removeObjectForKey:endpoint];
    if ((previous != nil) == (failure != nil) && [(previous ?: @"") isEqualToString:(failure ?: @"")]) return;
    dispatch_async(dispatch_get_main_queue(), ^{ [NSNotificationCenter.defaultCenter postNotificationName:MTRGDNSFailureChangedNotification object:endpoint]; });
}
+ (MTSignal *)queryHostname:(NSString *)hostname type:(uint16_t)type endpoint:(NSString *)endpoint useCache:(bool)useCache {
    NSString *host = [[hostname lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"."]];
    if ((type != 1 && type != 16 && type != 28) || ![MTRGDNSMessage queryForHost:host type:type == 16 ? 1 : type]) return [MTSignal fail:nil];
    NSString *custom = endpoint.length ? [self normalizedEndpoint:endpoint] : nil;
    if (endpoint.length && !custom) return [MTSignal fail:nil];
    NSString *cacheKey = [NSString stringWithFormat:@"%@|%@|%u", custom ?: @"builtin", host, type];
    MTRGDoHResolver *resolver = [self shared];
    return [[MTSignal alloc] initWithGenerator:^id<MTDisposable>(MTSubscriber *subscriber) {
        NSUUID *token = [NSUUID UUID]; MTAtomic *cancelled = [[MTAtomic alloc] initWithValue:@false];
        NSString *key = useCache ? cacheKey : [cacheKey stringByAppendingString:token.UUIDString];
        [resolver.queue dispatchOnQueue:^{
            if ([[cancelled value] boolValue]) return;
            NSDictionary *cached = useCache ? [resolver.cache objectForKey:cacheKey] : nil;
            if ([cached[@"expires"] doubleValue] > NSProcessInfo.processInfo.systemUptime) { [subscriber putNext:cached[@"answer"]]; [subscriber putCompletion]; return; }
            MTRGDoHLookup *lookup = resolver.inflight[key];
            if (lookup) { lookup.subscribers[token] = subscriber; return; }
            if (resolver.inflight.count >= 128) { [subscriber putError:nil]; return; }
            lookup = [[MTRGDoHLookup alloc] init]; lookup.key = key; lookup.cacheKey = cacheKey; lookup.host = host; lookup.type = type; lookup.endpoint = custom; lookup.useCache = useCache;
            lookup.providers = custom ? @[custom] : @[@"https://dns.google/resolve", @"https://cloudflare-dns.com/dns-query"];
            lookup.subscribers = [NSMutableDictionary dictionaryWithObject:subscriber forKey:token]; lookup.tasks = [NSMutableArray array]; lookup.failure = @"network";
            resolver.inflight[key] = lookup;
            if (lookup.providers.count > 1) {
                __weak MTRGDoHLookup *weakLookup = lookup;
                lookup.timer = [[MTTimer alloc] initWithTimeout:0.8 repeat:false completion:^{ MTRGDoHLookup *live = weakLookup; if (live && resolver.inflight[key] == live) [resolver startProvider:live]; } queue:resolver.queue.nativeQueue];
                [lookup.timer start];
            }
            [resolver startProvider:lookup];
        }];
        return [[MTBlockDisposable alloc] initWithBlock:^{
            [cancelled swap:@true];
            [resolver.queue dispatchOnQueue:^{
                MTRGDoHLookup *lookup = resolver.inflight[key];
                [lookup.subscribers removeObjectForKey:token];
                if (lookup && lookup.subscribers.count == 0) [resolver disposeLookup:lookup];
            }];
        }];
    }];
}
- (void)disposeLookup:(MTRGDoHLookup *)lookup {
    if (self.inflight[lookup.key] != lookup) return;
    [self.inflight removeObjectForKey:lookup.key];
    [lookup.timer invalidate]; lookup.timer = nil;
    NSArray *tasks = [lookup.tasks copy]; [lookup.tasks removeAllObjects];
    for (NSURLSessionDataTask *task in tasks) [task cancel];
    [lookup.subscribers removeAllObjects];
}
- (void)finishLookup:(MTRGDoHLookup *)lookup answer:(NSDictionary *)answer {
    if (self.inflight[lookup.key] != lookup) return;
    NSArray<MTSubscriber *> *subscribers = lookup.subscribers.allValues;
    if (answer && lookup.useCache) {
        double ttl = MAX(10, MIN(300, [answer[@"ttl"] doubleValue]));
        [self.cache setObject:@{@"answer": answer, @"expires": @(NSProcessInfo.processInfo.systemUptime + ttl)} forKey:lookup.cacheKey];
    }
    [self setFailure:answer || [lookup.failure isEqualToString:@"noAddress"] ? nil : lookup.failure endpoint:lookup.endpoint];
    [self disposeLookup:lookup];
    for (MTSubscriber *subscriber in subscribers) {
        if (answer) { [subscriber putNext:answer]; [subscriber putCompletion]; } else [subscriber putError:nil];
    }
}
- (void)startProvider:(MTRGDoHLookup *)lookup {
    if (self.inflight[lookup.key] != lookup || lookup.started >= lookup.providers.count) return;
    NSString *provider = lookup.providers[lookup.started++];
    NSMutableURLRequest *request = [MTRGDoHResolver jsonRequestForHostname:lookup.host type:lookup.type endpoint:provider];
    [self performRequest:request lookup:lookup provider:provider wire:false];
}
- (void)performRequest:(NSMutableURLRequest *)request lookup:(MTRGDoHLookup *)lookup provider:(NSString *)provider wire:(bool)wire {
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [self.queue dispatchOnQueue:^{
            if (self.inflight[lookup.key] != lookup) return;
            NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
            NSURLComponents *expected = [NSURLComponents componentsWithString:provider]; NSURL *final = http.URL;
            bool sameEndpoint = [final.scheme.lowercaseString isEqualToString:@"https"] && [final.host.lowercaseString isEqualToString:expected.host.lowercaseString] && [final.path isEqualToString:expected.path] && (final.port ?: @443).integerValue == (expected.port ?: @443).integerValue;
            NSDictionary *answer = !error && http.statusCode == 200 && sameEndpoint ? (wire ? [MTRGDNSMessage addressesFromResponse:data host:lookup.host type:lookup.type] : (lookup.type == 16 ? [MTRGDNSMessage textRecordsFromJSONResponse:data host:lookup.host] : [MTRGDNSMessage addressesFromJSONResponse:data host:lookup.host type:lookup.type])) : nil;
            if ([answer[lookup.type == 16 ? @"records" : @"addresses"] count]) {
                NSMutableDictionary *metadata = [answer mutableCopy];
                metadata[@"headers"] = http.allHeaderFields ?: @{};
                metadata[@"receivedUptime"] = @(NSProcessInfo.processInfo.systemUptime);
                [self finishLookup:lookup answer:metadata]; return;
            }
            // Existing RFC 8484-only custom endpoints remain usable; never change providers or downgrade to native DNS here.
            if (!wire && lookup.type != 16 && lookup.endpoint.length && !error && sameEndpoint && !answer) {
                NSMutableURLRequest *fallback = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:provider]];
                fallback.HTTPMethod = @"POST"; fallback.HTTPBody = [MTRGDNSMessage queryForHost:lookup.host type:lookup.type];
                [fallback setValue:@"application/dns-message" forHTTPHeaderField:@"Content-Type"]; [fallback setValue:@"application/dns-message" forHTTPHeaderField:@"Accept"];
                [self performRequest:fallback lookup:lookup provider:provider wire:true]; return;
            }
            lookup.failure = error ? @"network" : answer ? @"noAddress" : @"response";
            lookup.finished++;
            if (lookup.finished >= lookup.providers.count) [self finishLookup:lookup answer:nil];
        }];
    }];
    [lookup.tasks addObject:task]; [task resume];
}
@end
