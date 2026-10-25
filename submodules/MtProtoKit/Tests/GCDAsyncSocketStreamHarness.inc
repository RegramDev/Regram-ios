// MARK: Regram — compile the production socket; observe CF ownership at its API boundary.
#import <Foundation/Foundation.h>
#import <CFNetwork/CFNetwork.h>
#import "GCDAsyncSocket.h"
#include <stdatomic.h>

static void require(bool condition, const char *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

static Boolean checkedReadClient(CFReadStreamRef, CFOptionFlags, CFReadStreamClientCallBack, CFStreamClientContext *);
static Boolean checkedWriteClient(CFWriteStreamRef, CFOptionFlags, CFWriteStreamClientCallBack, CFStreamClientContext *);
static void checkedReadClose(CFReadStreamRef);
static void checkedWriteClose(CFWriteStreamRef);
static void checkedRelease(CFTypeRef);
static void checkedCreatePair(CFAllocatorRef, CFSocketNativeHandle, CFReadStreamRef *, CFWriteStreamRef *);

#define CFReadStreamSetClient checkedReadClient
#define CFWriteStreamSetClient checkedWriteClient
#define CFReadStreamClose checkedReadClose
#define CFWriteStreamClose checkedWriteClose
#define CFRelease checkedRelease
#define CFStreamCreatePairWithSocket checkedCreatePair
#include RG_SOCKET_SOURCE
#undef CFReadStreamSetClient
#undef CFWriteStreamSetClient
#undef CFReadStreamClose
#undef CFWriteStreamClose
#undef CFRelease
#undef CFStreamCreatePairWithSocket

// Usage accounting is outside this fixture; any attempt to touch it fails.
@implementation MTNetworkUsageManager
- (instancetype)initWithInfo:(MTNetworkUsageCalculationInfo *)info { abort(); }
- (void)addIncomingBytes:(NSUInteger)bytes interface:(MTNetworkUsageManagerInterface)interface { abort(); }
- (void)addOutgoingBytes:(NSUInteger)bytes interface:(MTNetworkUsageManagerInterface)interface { abort(); }
- (void)resetKeys:(NSArray *)keys setKeys:(NSDictionary *)values completion:(void (^)())completion { abort(); }
- (MTSignal *)currentStatsForKeys:(NSArray *)keys { abort(); }
@end

@interface RGSocketFixture : GCDAsyncSocket
- (void)installRead:(CFReadStreamRef)read write:(CFWriteStreamRef)write;
- (void)prepareCreationWithFD:(int)fd;
- (bool)streamsDetached;
@end
@implementation RGSocketFixture
- (void)installRead:(CFReadStreamRef)read write:(CFWriteStreamRef)write {
    readStream = read;
    writeStream = write;
}
- (void)prepareCreationWithFD:(int)fd {
    socket4FD = fd;
    flags = kConnected;
}
- (bool)streamsDetached { return readStream == NULL && writeStream == NULL; }
@end

typedef struct {
    __unsafe_unretained RGSocketFixture *owner;
    CFReadStreamRef read;
    CFWriteStreamRef write;
    bool readClosed, writeClosed, readReleased, writeReleased;
    bool readClientCleared, writeClientCleared, failCreation;
} StreamPair;
static _Thread_local StreamPair *observedPair;
static atomic_uint socketStreamPairs;

static Boolean checkedReadClient(CFReadStreamRef stream, CFOptionFlags events, CFReadStreamClientCallBack callback, CFStreamClientContext *context) {
    if (observedPair && stream == observedPair->read)
        observedPair->readClientCleared = events == kCFStreamEventNone && callback == NULL;
    return CFReadStreamSetClient(stream, events, callback, context);
}
static Boolean checkedWriteClient(CFWriteStreamRef stream, CFOptionFlags events, CFWriteStreamClientCallBack callback, CFStreamClientContext *context) {
    if (observedPair && stream == observedPair->write)
        observedPair->writeClientCleared = events == kCFStreamEventNone && callback == NULL;
    return CFWriteStreamSetClient(stream, events, callback, context);
}
static void checkedReadClose(CFReadStreamRef stream) {
    if (observedPair && stream == observedPair->read) {
        require(!observedPair->readClosed, "read stream closed twice");
        observedPair->readClosed = true;
    }
    CFReadStreamClose(stream);
}
static void checkedWriteClose(CFWriteStreamRef stream) {
    if (observedPair && stream == observedPair->write) {
        require(!observedPair->writeClosed, "write stream closed twice");
        observedPair->writeClosed = true;
    }
    CFWriteStreamClose(stream);
}
static void checkedRelease(CFTypeRef value) {
    StreamPair *pair = observedPair;
    if (pair && (value == pair->read || value == pair->write)) {
        require((!pair->read || pair->readClosed) && (!pair->write || pair->writeClosed),
                "releasing a stream while its sibling is still open can re-enter CFSocketInvalidate");
        require([pair->owner streamsDetached], "socket still owns streams during their release");
        require((!pair->read || pair->readClientCleared) && (!pair->write || pair->writeClientCleared),
                "stream clients still registered during release");
        if (value == pair->read) {
            require(!pair->readReleased, "read stream released twice");
            pair->readReleased = true;
        } else {
            require(!pair->writeReleased, "write stream released twice");
            pair->writeReleased = true;
        }
    }
    CFRelease(value);
}
static void checkedCreatePair(CFAllocatorRef allocator, CFSocketNativeHandle fd, CFReadStreamRef *read, CFWriteStreamRef *write) {
    if (observedPair && observedPair->failCreation) {
        *read = observedPair->read;
        *write = observedPair->write;
    } else {
        atomic_fetch_add(&socketStreamPairs, 1);
        CFStreamCreatePairWithSocket(allocator, fd, read, write);
    }
}

static void checkOwnership(bool hasRead, bool hasWrite, bool creationFailure, bool withError) {
    RGSocketFixture *fixture = [[RGSocketFixture alloc] init];
    __block StreamPair pair = { .owner = fixture, .failCreation = creationFailure };
    if (hasRead) pair.read = CFReadStreamCreateWithBytesNoCopy(NULL, (const UInt8 *)"r", 1, kCFAllocatorNull);
    if (hasWrite) pair.write = CFWriteStreamCreateWithAllocatedBuffers(NULL, NULL);
    int fd = creationFailure ? socket(AF_INET, SOCK_STREAM, 0) : -1;
    require(!creationFailure || fd >= 0, "create native socket for failed stream creation");
    [fixture performBlock:^{
        observedPair = &pair;
        if (creationFailure) {
            [fixture prepareCreationWithFD:fd];
            require(![fixture createReadAndWriteStream], "partial pair creation must fail");
        } else {
            [fixture installRead:pair.read write:pair.write];
        }
        NSError *error = withError ? [NSError errorWithDomain:NSPOSIXErrorDomain code:ECONNRESET userInfo:nil] : nil;
        [fixture closeWithError:error];
        [fixture closeWithError:error];
        require([fixture streamsDetached], "repeated cleanup must leave no streams");
        observedPair = NULL;
    }];
    require(!hasRead || pair.readReleased, "read stream leaked");
    require(!hasWrite || pair.writeReleased, "write stream leaked");
    if (creationFailure) require(fcntl(fd, F_GETFD) == -1 && errno == EBADF, "native socket not closed");
}

static const char payload[] = "regram-cfstream-loopback";
typedef NS_ENUM(int, Mode) { Echo, RemoteClose, ImmediateClose, ReadTimeout };
@interface RGLoopbackObserver : NSObject <GCDAsyncSocketDelegate>
@property Mode mode;
@property bool received;
@property int disconnects;
@property dispatch_semaphore_t finished;
@end
@implementation RGLoopbackObserver
- (void)socket:(GCDAsyncSocket *)socket didConnectToHost:(NSString *)host port:(uint16_t)port {
    if (self.mode == ImmediateClose) {
        [socket disconnect];
        [socket disconnect];
    } else {
        [socket readDataToLength:sizeof(payload) withTimeout:self.mode == ReadTimeout ? 0.05 : 5 tag:0];
        [socket writeData:[NSData dataWithBytes:payload length:sizeof(payload)] withTimeout:5 tag:0];
        char mode = self.mode;
        [socket writeData:[NSData dataWithBytes:&mode length:1] withTimeout:5 tag:1];
    }
}
- (void)socket:(GCDAsyncSocket *)socket didReadData:(NSData *)data withTag:(long)tag networkType:(int32_t)type {
    require([data isEqualToData:[NSData dataWithBytes:payload length:sizeof(payload)]], "echo data changed");
    self.received = true;
    if (self.mode == Echo) [socket disconnect];
}
- (void)socketDidDisconnect:(GCDAsyncSocket *)socket withError:(NSError *)error {
    self.disconnects++;
    if (self.mode == ReadTimeout)
        require([error.domain isEqualToString:GCDAsyncSocketErrorDomain] && error.code == GCDAsyncSocketReadTimeoutError,
                "read deadline must use the normal socket timeout path");
    dispatch_semaphore_signal(self.finished);
}
@end

static int makeListener(bool ipv6, uint16_t *port) {
    int fd = socket(ipv6 ? AF_INET6 : AF_INET, SOCK_STREAM, 0);
    require(fd >= 0, "create loopback listener");
    if (ipv6) {
        struct sockaddr_in6 address = { .sin6_len = sizeof(address), .sin6_family = AF_INET6, .sin6_addr = IN6ADDR_LOOPBACK_INIT };
        require(bind(fd, (struct sockaddr *)&address, sizeof(address)) == 0, "bind IPv6 listener");
        socklen_t length = sizeof(address);
        require(getsockname(fd, (struct sockaddr *)&address, &length) == 0, "IPv6 listener address");
        *port = ntohs(address.sin6_port);
    } else {
        struct sockaddr_in address = { .sin_len = sizeof(address), .sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK) };
        require(bind(fd, (struct sockaddr *)&address, sizeof(address)) == 0, "bind IPv4 listener");
        socklen_t length = sizeof(address);
        require(getsockname(fd, (struct sockaddr *)&address, &length) == 0, "IPv4 listener address");
        *port = ntohs(address.sin_port);
    }
    require(listen(fd, 128) == 0, "listen on loopback");
    return fd;
}

static void checkLoopback(bool ipv6) {
    const int count = 96;
    uint16_t port;
    int listener = makeListener(ipv6, &port);
    dispatch_group_t servers = dispatch_group_create();
    dispatch_group_async(servers, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        for (int i = 0; i < count; i++) {
            int peer = accept(listener, NULL, NULL);
            require(peer >= 0, "accept loopback peer");
            dispatch_group_async(servers, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
                struct timeval timeout = { .tv_sec = 10 };
                setsockopt(peer, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
                int noSignal = 1;
                setsockopt(peer, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
                char buffer[sizeof(payload)];
                ssize_t length = recv(peer, buffer, sizeof(buffer), MSG_WAITALL);
                // The first byte selects the peer behavior independently of accept order.
                if (length == sizeof(payload)) {
                    char mode;
                    require(recv(peer, &mode, 1, MSG_WAITALL) == 1, "receive peer mode");
                    if (mode != ReadTimeout)
                        require(send(peer, buffer, sizeof(buffer), 0) == sizeof(buffer), "send echo");
                    if (mode != RemoteClose) recv(peer, buffer, sizeof(buffer), 0);
                }
                close(peer);
            });
        }
        close(listener);
    });
    NSMutableArray *sockets = [NSMutableArray array];
    NSMutableArray *observers = [NSMutableArray array];
    NSMutableArray *queues = [NSMutableArray array];
    for (int i = 0; i < count; i++) {
        RGLoopbackObserver *observer = [RGLoopbackObserver new];
        observer.mode = i % 4;
        observer.finished = dispatch_semaphore_create(0);
        dispatch_queue_t queue = dispatch_queue_create("regram.cfstream.loopback", DISPATCH_QUEUE_SERIAL);
        GCDAsyncSocket *socket = [[GCDAsyncSocket alloc] initWithDelegate:observer delegateQueue:queue];
        NSError *error;
        require([socket connectToHost:ipv6 ? @"::1" : @"127.0.0.1" onPort:port withTimeout:10 error:&error], "start loopback connection");
        [sockets addObject:socket];
        [observers addObject:observer];
        [queues addObject:queue];
    }
    for (int i = 0; i < count; i++) {
        RGLoopbackObserver *observer = observers[i];
        require(dispatch_semaphore_wait(observer.finished, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC)) == 0, "loopback disconnect deadline");
        [sockets[i] performBlock:^{}];
        dispatch_sync(queues[i], ^{});
        require(observer.disconnects == 1, "disconnect callback must run exactly once");
        require(observer.received == (observer.mode == Echo || observer.mode == RemoteClose), "loopback read outcome");
    }
    require(dispatch_group_wait(servers, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC)) == 0, "server cleanup deadline");
    require(atomic_load(&socketStreamPairs) == 0, "plain TCP must not create legacy observer CFStreams");
}

int main(void) { @autoreleasepool {
    setbuf(stdout, NULL);
    checkOwnership(true, true, false, false);
    checkOwnership(true, true, false, true);
    checkOwnership(true, false, true, false);
    checkOwnership(false, true, true, true);
    checkOwnership(false, false, true, false);
    dispatch_apply(128, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^(size_t i) {
        @autoreleasepool { checkOwnership(true, true, false, i % 2 != 0); }
    });
    puts("PASS: 133 ownership cases (paired lifetime, partial creation, repeat/error cleanup, concurrent sockets)");
    checkLoopback(false);
    checkLoopback(true);
    puts("PASS: 192 IPv4/IPv6 loopback connections (echo, remote close, delegate cancellation, read timeout)");
} return 0; }
