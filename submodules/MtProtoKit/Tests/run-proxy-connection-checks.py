#!/usr/bin/env python3
"""Compile the production proxy facade; replace only TCP, DNS, timer and queue I/O."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'submodules/MtProtoKit/Sources'
HEADER = r'''
#pragma once
#import <Foundation/Foundation.h>
#import "MTTcpConnection.h"
@protocol MTDisposable <NSObject>
- (void)dispose;
@end
@interface MTMetaDisposable : NSObject
- (void)setDisposable:(id<MTDisposable>)value;
- (void)dispose;
@end
@interface MTSignal : NSObject
- (MTSignal *)deliverOn:(id)queue;
- (id<MTDisposable>)startWithNext:(void (^)(id))next error:(void (^)(id))error completed:(void (^)(void))completed;
@end
@interface MTQueue : NSObject
@property(readonly) dispatch_queue_t nativeQueue;
- (void)dispatchOnQueue:(dispatch_block_t)block;
@end
@interface MTTimer : NSObject
- (id)initWithTimeout:(NSTimeInterval)timeout repeat:(bool)repeat completion:(dispatch_block_t)completion queue:(dispatch_queue_t)queue;
- (void)start;
- (void)invalidate;
- (void)fire;
@end
@interface MTSocksProxySettings : NSObject
@property NSString *ip;
@property uint16_t port;
@property NSString *username;
@property NSString *password;
@property NSData *secret;
- (id)initWithIp:(NSString *)ip port:(uint16_t)port username:(NSString *)username password:(NSString *)password secret:(NSData *)secret;
@end
@interface MTApiEnvironment : NSObject
@property MTSocksProxySettings *socksProxySettings;
@property NSString *rgDoHEndpoint;
@property NSInteger rgIPVersionPreference;
@property bool rgUseSystemDNS;
@end
@interface MTContext : NSObject
@property MTApiEnvironment *apiEnvironment;
@end
static inline bool MTLogEnabled(void) { return false; }
#define MTLog(...) ((void)0)
'''
with tempfile.TemporaryDirectory(prefix='regram-proxy-checks-') as temp:
    directory = Path(temp)
    (directory / 'MtProtoKit').mkdir()
    (directory / 'Support.h').write_text(HEADER)
    for name in ['MTContext', 'MTApiEnvironment', 'MTQueue', 'MTTimer', 'MTSignal', 'MTLogging']:
        (directory / 'MtProtoKit' / (name + '.h')).write_text('#import "Support.h"\n')
    binary = directory / 'checks'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fblocks', '-Wall', '-Werror', '-framework', 'Foundation',
                    '-I', str(directory), '-I', str(SOURCE), '-x', 'objective-c',
                    str(SOURCE / 'MTRGProxyConnection.m'), str(Path(__file__).with_name('ProxyConnectionHarness.inc')),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=15)
    dns = directory / 'dns-checks'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fblocks', '-Wall', '-Werror', '-DRG_STANDALONE_TESTS=1',
                    '-framework', 'Foundation', '-I', str(SOURCE), str(SOURCE / 'MTRGDNSMessage.m'),
                    str(Path(__file__).with_name('MTRGDNSMessageTests.m')), '-o', str(dns)], check=True)
    subprocess.run([str(dns)], check=True, timeout=15)
