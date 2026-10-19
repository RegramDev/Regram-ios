// MARK: Regram — ordered proxy IP rotation with fresh handshake state and bounded replay.
#import "MTRGProxyConnection.h"
#import "MTDNS.h"
#import <MtProtoKit/MTContext.h>
#import <MtProtoKit/MTApiEnvironment.h>
#import <MtProtoKit/MTQueue.h>
#import <MtProtoKit/MTTimer.h>
#import <MtProtoKit/MTSignal.h>
#import <MtProtoKit/MTLogging.h>
#import <arpa/inet.h>

@interface MTRGProxyPacket : NSObject
@property NSArray *data;
@property (copy) void (^completion)(bool);
@property bool acknowledged;
@property bool quickAck;
@property bool expectsResponse;
@end
@implementation MTRGProxyPacket
@end

@interface MTRGProxyConnection () {
    __weak MTContext *_sourceContext;
    NSInteger _dcId;
    MTNetworkUsageCalculationInfo *_usage;
    MTSocksProxySettings *_proxy;
    NSString *_endpoint;
    NSInteger _preference;
    bool _systemDNS;
    NSString *_successKey;
    NSArray<NSString *> *_addresses;
    NSUInteger _index;
    MTTcpConnection *_child;
    MTMetaDisposable *_lookup;
    MTTimer *_attemptTimer;
    NSMutableArray<MTRGProxyPacket *> *_replay;
    NSUInteger _replayBytes;
    bool _started, _finished, _opened, _confirmed;
}
@end

@implementation MTRGProxyConnection

+ (NSCache *)successes {
    static NSCache *cache; static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; cache.countLimit = 128; });
    return cache;
}

- (instancetype)initWithContext:(MTContext *)context datacenterId:(NSInteger)dc scheme:(MTTransportScheme *)scheme interface:(NSString *)interface usageCalculationInfo:(MTNetworkUsageCalculationInfo *)usage getLogPrefix:(NSString *(^)())prefix {
    self = [super initRGWithContext:context datacenterId:dc scheme:scheme interface:interface usageCalculationInfo:usage getLogPrefix:prefix proxyOverride:nil];
    if (self) {
        _sourceContext = context; _dcId = dc; _usage = usage;
        _proxy = context.apiEnvironment.socksProxySettings;
        _endpoint = context.apiEnvironment.rgDoHEndpoint; _preference = context.apiEnvironment.rgIPVersionPreference;
        _systemDNS = context.apiEnvironment.rgUseSystemDNS;
        _successKey = [NSString stringWithFormat:@"%@|%u|%d|%@|%ld", _proxy.ip, _proxy.port, _proxy.secret != nil, _endpoint ?: (_systemDNS ? @"system" : @"builtin"), (long)_preference];
        _lookup = [[MTMetaDisposable alloc] init]; _replay = [NSMutableArray array];
    }
    return self;
}

- (void)dealloc {
    [_lookup dispose]; [_attemptTimer invalidate];
    _child.delegate = nil; [_child stop];
}

- (void)setUsageCalculationInfo:(MTNetworkUsageCalculationInfo *)usage {
    [[MTTcpConnection tcpQueue] dispatchOnQueue:^{ self->_usage = usage; [self->_child setUsageCalculationInfo:usage]; }];
}

- (void)start {
    [[MTTcpConnection tcpQueue] dispatchOnQueue:^{
        if (self->_started || self->_finished) return;
        self->_started = true;
        __weak MTRGProxyConnection *weakSelf = self;
        [self->_lookup setDisposable:[[[MTDNS resolveProxyHostname:self->_proxy.ip dohEndpoint:self->_endpoint preference:self->_preference useSystemDNS:self->_systemDNS] deliverOn:[MTTcpConnection tcpQueue]] startWithNext:^(NSArray *addresses) {
            MTRGProxyConnection *strongSelf = weakSelf;
            if (!strongSelf || strongSelf->_finished) return;
            NSMutableArray *ordered = [addresses mutableCopy];
            NSDictionary *good = [[MTRGProxyConnection successes] objectForKey:strongSelf->_successKey];
            NSString *ip = good[@"ip"];
            NSUInteger found = ip ? [ordered indexOfObject:ip] : NSNotFound;
            if (found != NSNotFound && [good[@"expires"] doubleValue] > NSDate.date.timeIntervalSince1970) {
                // Remember successes within their family, preserving an explicitly selected family preference.
                bool v6 = [ip containsString:@":"];
                NSUInteger first = strongSelf->_preference == 0 ? 0 : [ordered indexOfObjectPassingTest:^BOOL(NSString *candidate, __unused NSUInteger idx, __unused BOOL *stop) { return [candidate containsString:@":"] == v6; }];
                [ordered removeObjectAtIndex:found]; [ordered insertObject:ip atIndex:first];
            }
            strongSelf->_addresses = ordered; strongSelf->_index = 0;
            [strongSelf nextAddress];
        } error:^(__unused id error) { [weakSelf finish:true]; } completed:^{}]];
    }];
}

- (void)nextAddress {
    if (_finished || _confirmed) return;
    [_attemptTimer invalidate]; _attemptTimer = nil;
    MTTcpConnection *old = _child; _child = nil; old.delegate = nil; [old stop];
    MTContext *context = _sourceContext;
    if (!context || _index >= _addresses.count) { [self finish:true]; return; }
    NSString *ip = _addresses[_index++];
    MTSocksProxySettings *proxy = [[MTSocksProxySettings alloc] initWithIp:ip port:_proxy.port username:_proxy.username password:_proxy.password secret:_proxy.secret];
    _child = [[MTTcpConnection alloc] initRGWithContext:context datacenterId:_dcId scheme:self.scheme interface:self.interface usageCalculationInfo:_usage getLogPrefix:self.getLogPrefix proxyOverride:proxy];
    _child.delegate = self;
    if (MTLogEnabled()) MTLog(@"[Regram proxy attempt %lu/%lu IPv%d]", (unsigned long)_index, (unsigned long)_addresses.count, [ip containsString:@":"] ? 6 : 4);
    __weak MTRGProxyConnection *weakSelf = self;
    __weak MTTcpConnection *attempt = _child;
    _attemptTimer = [[MTTimer alloc] initWithTimeout:4.0 repeat:false completion:^{
        MTRGProxyConnection *strongSelf = weakSelf;
        if (strongSelf && !strongSelf->_confirmed && strongSelf->_child == attempt) [strongSelf nextAddress];
    } queue:[MTTcpConnection tcpQueue].nativeQueue];
    [_attemptTimer start];
    NSArray *pendingPackets = [_replay copy];
    MTTcpConnection *attemptedChild = _child;
    [_child start];
    for (MTRGProxyPacket *packet in pendingPackets) {
        if (_finished || _child != attemptedChild) break;
        [self sendPacket:packet];
    }
}

- (void)sendPacket:(MTRGProxyPacket *)packet {
    [_child sendDatas:packet.data completion:^(bool success) {
        if (!packet.acknowledged && success) { packet.acknowledged = true; if (packet.completion) packet.completion(true); }
    } requestQuickAck:packet.quickAck expectDataInResponse:packet.expectsResponse];
}

- (void)sendDatas:(NSArray *)data completion:(void (^)(bool))completion requestQuickAck:(bool)quickAck expectDataInResponse:(bool)expectsResponse {
    [[MTTcpConnection tcpQueue] dispatchOnQueue:^{
        if (self->_finished) { if (completion) completion(false); return; }
        if (self->_confirmed) { [self->_child sendDatas:data completion:completion requestQuickAck:quickAck expectDataInResponse:expectsResponse]; return; }
        MTRGProxyPacket *packet = [[MTRGProxyPacket alloc] init]; packet.data = [data copy]; packet.completion = completion; packet.quickAck = quickAck; packet.expectsResponse = expectsResponse;
        for (NSData *bytes in data) self->_replayBytes += bytes.length;
        [self->_replay addObject:packet];
        [self sendPacket:packet];
        // Fail an unresponsive attempt before retaining an unbounded upload window; never cache an unconfirmed IP as successful.
        if (self->_replayBytes > 8 * 1024 * 1024) [self finish:true];
    }];
}

- (void)confirm {
    if (_finished || _confirmed) return;
    _confirmed = true; [_attemptTimer invalidate]; _attemptTimer = nil;
    if (_index > 0 && _index <= _addresses.count) [[MTRGProxyConnection successes] setObject:@{@"ip": _addresses[_index - 1], @"expires": @(NSDate.date.timeIntervalSince1970 + 300)} forKey:_successKey];
    [_replay removeAllObjects]; _replayBytes = 0;
}

- (void)stop { [[MTTcpConnection tcpQueue] dispatchOnQueue:^{ [self finish:false]; }]; }
- (void)finish:(bool)error {
    if (_finished) return;
    _finished = true; [_lookup dispose]; [_attemptTimer invalidate]; _attemptTimer = nil;
    MTTcpConnection *child = _child; _child = nil; child.delegate = nil; [child stop];
    NSArray *pending = [_replay copy]; [_replay removeAllObjects]; _replayBytes = 0;
    for (MTRGProxyPacket *packet in pending) if (!packet.acknowledged) { packet.acknowledged = true; if (packet.completion) packet.completion(false); }
    if (self.connectionClosed) self.connectionClosed();
    if ([self.delegate respondsToSelector:@selector(tcpConnectionClosed:error:)]) [self.delegate tcpConnectionClosed:self error:error];
}

- (void)tcpConnectionOpened:(MTTcpConnection *)connection {
    if (_finished || connection != _child || _opened) return;
    _opened = true;
    if (self.connectionOpened) self.connectionOpened();
    if ([self.delegate respondsToSelector:@selector(tcpConnectionOpened:)]) [self.delegate tcpConnectionOpened:self];
}
- (void)tcpConnectionClosed:(MTTcpConnection *)connection error:(bool)error {
    if (_finished || connection != _child) return;
    if (_confirmed) [self finish:error]; else [self nextAddress];
}
- (void)tcpConnectionReceivedData:(MTTcpConnection *)connection networkType:(int32_t)type data:(NSData *)data {
    if (_finished || connection != _child) return;
    [self confirm];
    if (self.connectionReceivedData) self.connectionReceivedData(data);
    if ([self.delegate respondsToSelector:@selector(tcpConnectionReceivedData:networkType:data:)]) [self.delegate tcpConnectionReceivedData:self networkType:type data:data];
}
- (void)tcpConnectionReceivedQuickAck:(MTTcpConnection *)connection quickAck:(int32_t)ack {
    if (_finished || connection != _child) return;
    [self confirm];
    if ([self.delegate respondsToSelector:@selector(tcpConnectionReceivedQuickAck:quickAck:)]) [self.delegate tcpConnectionReceivedQuickAck:self quickAck:ack];
}
- (void)tcpConnectionDecodePacketProgressToken:(MTTcpConnection *)connection data:(NSData *)data token:(int64_t)token completion:(void (^)(int64_t, id))completion {
    if (_finished || connection != _child) return;
    if ([self.delegate respondsToSelector:@selector(tcpConnectionDecodePacketProgressToken:data:token:completion:)]) [self.delegate tcpConnectionDecodePacketProgressToken:self data:data token:token completion:completion];
}
- (void)tcpConnectionProgressUpdated:(MTTcpConnection *)connection packetProgressToken:(id)token packetLength:(NSUInteger)length progress:(float)progress {
    if (_finished || connection != _child) return;
    if ([self.delegate respondsToSelector:@selector(tcpConnectionProgressUpdated:packetProgressToken:packetLength:progress:)]) [self.delegate tcpConnectionProgressUpdated:self packetProgressToken:token packetLength:length progress:progress];
}
- (void)tcpConnectionDownloadActivityUpdated:(MTTcpConnection *)connection {
    if (_finished || connection != _child) return;
    if ([self.delegate respondsToSelector:@selector(tcpConnectionDownloadActivityUpdated:)]) [self.delegate tcpConnectionDownloadActivityUpdated:self];
}
@end
