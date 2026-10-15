#!/usr/bin/env python3
"""Exercise production DNS/proxy policy with real signals/timers and an isolated NSURLProtocol."""
from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parents[3]
MODULE=ROOT/'submodules/MtProtoKit'
with tempfile.TemporaryDirectory(prefix='regram-dns-policy-') as temporary:
    work=Path(temporary)
    source=(MODULE/'Sources/MTDNS.m').read_text()
    a=source.index('// MARK: Regram — DNS mode is explicit;');b=source.index('\n@end',a)
    diag=source[source.index('@implementation MTRGDNSDiagnostics'):]
    fixture=work/'Resolver.m'
    fixture.write_text('''#import <Foundation/Foundation.h>
#import <netdb.h>
#import <arpa/inet.h>
#import "MTDNS.h"
#import "MTRGDoHResolver.h"
#import "MTRGIPPolicy.h"
#import <MtProtoKit/MTRGDNSDiagnostics.h>
#import <MtProtoKit/MTAtomic.h>
#import <MtProtoKit/MTQueue.h>
@implementation MTDNS
+ (MTSignal *)resolveHostnameNative:(NSString *)host port:(int32_t)port { abort(); }
+ (MTSignal *)resolveHostnameUniversal:(NSString *)host port:(int32_t)port { abort(); }
'''+source[a:b]+'\n@end\n'+diag)
    files=[MODULE/'Sources'/(name+'.m') for name in ['MTQueue','MTTimer','MTAtomic','MTSignal','MTSubscriber','MTDisposable','MTBag','MTRGIPPolicy','MTRGDoHResolver','MTRGDNSMessage']]
    binary=work/'checks'
    subprocess.run(['xcrun','clang','-fobjc-arc','-fblocks','-Wall','-Werror','-Wno-deprecated-declarations','-framework','Foundation','-I',str(MODULE/'PublicHeaders'),'-I',str(MODULE/'Sources'),'-x','objective-c',*map(str,files),str(fixture),str(MODULE/'Tests/DNSPolicyHarness.inc'),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=30)
