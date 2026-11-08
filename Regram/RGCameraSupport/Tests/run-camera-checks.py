#!/usr/bin/env python3
"""Compile the actual exception boundary and configuration lifecycle against account-free camera adapters."""
from pathlib import Path
import argparse
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()

objc = r'''
#import <RGCameraSupport/RGCameraSupport.h>
@interface Format: NSObject
@property NSArray<NSValue *> *supportedMaxPhotoDimensions;
@end
@implementation Format
@end
@interface Device: NSObject
@property Format *activeFormat;
@end
@implementation Device
@end
@interface Input: NSObject
@property Device *device;
@end
@implementation Input
- (BOOL)isKindOfClass:(Class)c { return c == AVCaptureDeviceInput.class || [super isKindOfClass:c]; }
@end
@interface Port: NSObject
@property AVMediaType mediaType;
@property Input *input;
@end
@implementation Port
@end
@interface Connection: NSObject
@property NSArray<Port *> *inputPorts;
@end
@implementation Connection
@end
@interface Output: NSObject
@property Connection *connection;
@property (nonatomic) CMVideoDimensions maxPhotoDimensions;
@property BOOL reject;
@property int writes;
@end
@implementation Output
- (AVCaptureConnection *)connectionWithMediaType:(AVMediaType)type { return (id)self.connection; }
- (void)setMaxPhotoDimensions:(CMVideoDimensions)value {
    self.writes += 1;
    if (self.reject) { [NSException raise:NSInvalidArgumentException format:@"capture graph not ready"]; }
    _maxPhotoDimensions=value;
}
@end
int main() { @autoreleasepool {
    Output *o=[Output new]; CMVideoDimensions d={4032,3024}, invalid={0,0};
    NSCAssert(!RGSetCameraPhotoDimensions((id)o,invalid), @"zero size rejected");
    NSCAssert(!RGSetCameraPhotoDimensions((id)o,d) && o.writes==0, @"detached output untouched");
    Format *f=[Format new]; f.supportedMaxPhotoDimensions=@[[NSValue value:&d withObjCType:@encode(CMVideoDimensions)]];
    Device *device=[Device new]; device.activeFormat=f;
    Input *input=[Input new]; input.device=device;
    Port *port=[Port new]; port.mediaType=AVMediaTypeVideo; port.input=input;
    Connection *connection=[Connection new]; connection.inputPorts=@[port]; o.connection=connection;
    CMVideoDimensions unsupported={9999,9999};
    NSCAssert(!RGSetCameraPhotoDimensions((id)o,unsupported) && o.writes==0, @"unsupported size untouched");
    o.reject=YES;
    NSCAssert(!RGSetCameraPhotoDimensions((id)o,d) && o.writes==1, @"Objective-C exception is contained");
    o.reject=NO;
    NSCAssert(RGSetCameraPhotoDimensions((id)o,d) && o.writes==2, @"valid size applied");
    NSCAssert(RGSetCameraPhotoDimensions((id)o,d) && o.writes==2, @"no redundant pipeline rebuild");
    f.supportedMaxPhotoDimensions=@[];
    NSCAssert(!RGSetCameraPhotoDimensions((id)o,d) && o.writes==2, @"new format revalidated");
    puts("Camera exception boundary: 7 checks passed");
} return 0; }
'''
path = 'submodules/Camera/CameraLegacy/Sources/LegacyCamera.swift'
source = subprocess.check_output(['git','show','85edf2a613:'+path],cwd=ROOT,text=True) if args.baseline else (ROOT/path).read_text()
start = source.index('    private func configure(_ f: () -> Void) {')
end = source.index('        // A configuration',start)
lifecycle = source[start:end]+'    }\n'
swift = r'''
import Foundation
final class Session {
 var committed=false
 func beginConfiguration() { committed=false }
 func commitConfiguration() { committed=true }
}
final class CameraSession { let session=Session() }
final class Output {
 var calls=0
 func configurePhotoDimensions(session: CameraSession, device: Int) {
  precondition(session.session.committed,"dimensions configured before commit")
  calls += 1
 }
}
final class Context { let output=Output(); let device=0 }
final class Camera {
 let session=CameraSession()
 var mainDeviceContext: Context?=Context()
 var additionalDeviceContext: Context?=Context()
'''+lifecycle+r'''
 func exercise() {
  configure { precondition(!session.session.committed) }
  precondition(mainDeviceContext!.output.calls==1 && additionalDeviceContext!.output.calls==1,"both connected cameras configured after commit")
  configure {}
  precondition(mainDeviceContext!.output.calls==2,"mode and camera switches reconfigure dimensions")
  additionalDeviceContext=nil; mainDeviceContext=nil; configure {}
 }
}
Camera().exercise()
print("Camera lifecycle: initialization, main/secondary outputs, reconfiguration and missing inputs passed")
'''
with tempfile.TemporaryDirectory(prefix='regram-camera-') as temp:
    out=Path(temp)
    (out/'checks.m').write_text(objc)
    subprocess.run(['xcrun','clang','-fobjc-arc','-fmodules','-Werror','-I'+str(ROOT/'Regram/RGCameraSupport/Public'),str(ROOT/'Regram/RGCameraSupport/Sources/RGCameraSupport.m'),str(out/'checks.m'),'-framework','AVFoundation','-framework','Foundation','-o',str(out/'objc-checks')],check=True)
    subprocess.run([str(out/'objc-checks')],check=True)
    (out/'main.swift').write_text(swift)
    subprocess.run(['xcrun','swiftc','-warnings-as-errors',str(out/'main.swift'),'-o',str(out/'swift-checks')],check=True)
    subprocess.run([str(out/'swift-checks')],check=True)
