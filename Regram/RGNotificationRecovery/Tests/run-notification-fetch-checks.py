#!/usr/bin/env python3
"""Exercise the production fetch guard with real SwiftSignalKit and thin resource type adapters."""
from pathlib import Path
import subprocess, tempfile
root=Path(__file__).resolve().parents[3]
def block(source,marker):
 a=source.index(marker);b=source.index('{',a)+1;depth=1
 while depth:
  depth+=(source[b]=='{')-(source[b]=='}');b+=1
 return source[a:b]
source=(root/'Telegram/NotificationService/Sources/NotificationService.swift').read_text()
media=(root/'submodules/Postbox/Sources/MediaBox.swift').read_text()
fixture='''import Foundation
import SwiftSignalKit
protocol TelegramMediaResource { var size: Int64? { get } }
struct Resource: TelegramMediaResource { let size: Int64? }
public class TempBoxFile {}
public protocol MediaResourceDataFetchCopyLocalItem {}
'''+block(media,'public enum MediaResourceDataFetchResult')+'\n'+block(media,'public enum MediaResourceDataFetchError')+'\n'+block(source,'private func rgBoundedNotificationFetch(')+'''
@main enum Tests {
 static func main() {
  func exercise(_ values: [MediaResourceDataFetchResult], size: Int64?, enabled: Bool, expectedCount: Int, expectedFailure: Bool, expectedStart: Bool = true) {
   let started=Atomic(value:false),disposed=Atomic(value:false)
   let source=Signal<MediaResourceDataFetchResult,MediaResourceDataFetchError>{subscriber in
    _ = started.swap(true)
    values.forEach { subscriber.putNext($0) };subscriber.putCompletion()
    return ActionDisposable { _ = disposed.swap(true) }
   }
   var count=0,failed=false
   let d=rgBoundedNotificationFetch(source,budget:enabled ? RGNotificationResourceBudget() : nil,resource:Resource(size:size)).start(next:{_ in count += 1},error:{_ in failed=true})
   d.dispose()
   precondition(count==expectedCount && failed==expectedFailure && started.with{$0}==expectedStart)
   if expectedStart { precondition(disposed.with{$0}) }
  }
  let bytes=Data(repeating:7,count:16)
  let valid=MediaResourceDataFetchResult.dataPart(resourceOffset:0,data:bytes,range:0..<16,complete:true)
  exercise([valid],size:16,enabled:true,expectedCount:1,expectedFailure:false)
  exercise([valid],size:3*1024*1024,enabled:true,expectedCount:0,expectedFailure:true,expectedStart:false)
  exercise([.dataPart(resourceOffset:Int64.max,data:bytes,range:0..<16,complete:true)],size:32,enabled:true,expectedCount:0,expectedFailure:true)
  exercise([.dataPart(resourceOffset:0,data:bytes,range:0..<17,complete:true)],size:32,enabled:true,expectedCount:0,expectedFailure:true)
  exercise([valid,valid],size:16,enabled:true,expectedCount:1,expectedFailure:true)
  exercise([.resourceSizeUpdated(3*1024*1024)],size:nil,enabled:true,expectedCount:0,expectedFailure:true)
  exercise([valid,valid],size:16,enabled:false,expectedCount:2,expectedFailure:false)
  print("Notification fetch guard passed: admission before start, offsets, ranges, cumulative bytes, cancellation and unchanged disabled path.")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='regram-notification-fetch-') as temporary:
 work=Path(temporary)
 sources=sorted((root/'submodules/SSignalKit/SwiftSignalKit/Source').glob('*.swift'))
 subprocess.run(['xcrun','swiftc','-swift-version','5','-emit-library','-emit-module','-module-name','SwiftSignalKit']+[str(p) for p in sources]+['-emit-module-path',str(work/'SwiftSignalKit.swiftmodule'),'-o',str(work/'libSwiftSignalKit.dylib')],check=True,capture_output=True)
 path=work/'Tests.swift';path.write_text(fixture)
 subprocess.run(['xcrun','swiftc','-swift-version','5','-warnings-as-errors','-I',str(work),'-L',str(work),'-lSwiftSignalKit','-Xlinker','-rpath','-Xlinker',str(work),str(root/'Regram/RGNotificationRecovery/Sources/RGNotificationRecovery.swift'),str(path),'-o',str(work/'tests')],check=True)
 subprocess.run([str(work/'tests')],check=True)
