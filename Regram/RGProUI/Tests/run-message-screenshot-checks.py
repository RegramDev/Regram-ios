"""Run the production message screenshot composer in an isolated iOS simulator fixture."""
from pathlib import Path
import argparse,json,os,plistlib,subprocess,time
root=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser();parser.add_argument('--simulator',required=True);parser.add_argument('--output',default='build-input/message-screenshot-checks');args=parser.parse_args()
work=root/args.output;work.mkdir(parents=True,exist_ok=True)
env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode-27.0.app/Contents/Developer')
uid=args.simulator
s=(root/'Regram/RGProUI/Sources/RGMessageScreenshot.swift').read_text().replace('import Display', 'private enum Font { static func semibold(_ size: CGFloat) -> UIFont { .systemFont(ofSize: size, weight: .semibold) } }')
(work/'Production.swift').write_text(s)
(work/'App.swift').write_text('''import UIKit
import CoreImage
@main final class App: UIResponder, UIApplicationDelegate {
 var window: UIWindow?
 func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
  let window=UIWindow(frame:UIScreen.main.bounds);window.rootViewController=UIViewController();window.rootViewController?.view.backgroundColor = .black;window.makeKeyAndVisible();self.window=window
  DispatchQueue.main.async { self.check() };return true
 }
 func check() {
  var results:[String:Bool]=[:]
  let body=UIGraphicsImageRenderer(size:CGSize(width:160,height:80)).image { c in UIColor.blue.setFill();c.fill(CGRect(x:0,y:0,width:160,height:80)) }
  let avatar=UIGraphicsImageRenderer(size:CGSize(width:76,height:76)).image { c in UIColor.red.setFill();c.fill(CGRect(x:0,y:0,width:76,height:76)) }
  func pixel(_ image:UIImage, x:CGFloat, y:CGFloat) -> (UInt8,UInt8,UInt8) {
   var bytes=[UInt8](repeating:0,count:4)
   let context=CGContext(data:&bytes,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue)!
   context.translateBy(x:-x*image.scale,y:-(image.size.height-y)*image.scale)
   context.draw(image.cgImage!,in:CGRect(x:0,y:0,width:image.cgImage!.width,height:image.cgImage!.height))
   return (bytes[0],bytes[1],bytes[2])
  }
  let image=rgMessageScreenshot(body:body,senderName:"Alice 示例",avatar:avatar,backgroundColor:.black,textColor:.white)
  results["header_included"]=image.size.width==260 && image.size.height==154
  let a=pixel(image,x:31,y:31);results["avatar_visible"]=a.0>240 && a.1<10 && a.2<10
  let corner=pixel(image,x:13,y:13);results["avatar_clipped_circle"]=corner.0<10 && corner.1<10 && corner.2<10
  let b=pixel(image,x:30,y:85);results["bubble_preserved"]=b.2>240 && b.0<10 && b.1<10
  var namePixels=0
  for y in 12..<50 {for x in 60..<245 {let p=pixel(image,x:CGFloat(x),y:CGFloat(y));if p.0>100 && p.1>100 && p.2>100 {namePixels+=1}}}
  results["name_visible_dark_mode"]=namePixels>20
  let fallback=rgMessageScreenshot(body:body,senderName:"Alice",avatar:nil,backgroundColor:.black,textColor:.white)
  var initialPixels=0
  for y in 18..<44 {for x in 20..<44 {let p=pixel(fallback,x:CGFloat(x),y:CGFloat(y));if p.0>100 {initialPixels+=1}}}
  results["missing_avatar_initial"]=initialPixels>10
  let long=rgMessageScreenshot(body:body,senderName:String(repeating:"示例 Long ",count:100),avatar:avatar,backgroundColor:.white,textColor:.black)
  results["long_name_bounded"]=long.size==image.size
  let combined=rgMessageScreenshotStack([image,fallback],backgroundColor:.black)!
  results["multiple_messages_in_order"]=combined.size==CGSize(width:260,height:320) && pixel(combined,x:31,y:31).0>240 && pixel(combined,x:30,y:251).2>240
  results["no_empty_or_silent_truncation"]=rgMessageScreenshotStack([],backgroundColor:.black)==nil && rgMessageScreenshotStack(Array(repeating:image,count:31),backgroundColor:.black)==nil
  try! image.pngData()!.write(to:FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("preview.png"))
  let output=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("results.json")
  try! JSONSerialization.data(withJSONObject:results,options:[.sortedKeys,.prettyPrinted]).write(to:output)
  print("Screenshot fixture finished")
 }
}
''')
app=work/'ScreenshotChecks.app';app.mkdir(exist_ok=True)
(app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'ScreenshotChecks','CFBundleIdentifier':'test.regram.screenshotchecks','CFBundleName':'ScreenshotChecks','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','CFBundlePackageType':'APPL','CFBundleSupportedPlatforms':['iPhoneSimulator'],'MinimumOSVersion':'15.0','UIDeviceFamily':[1],'LSRequiresIPhoneOS':True,'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait']}))
sdk=subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True,env=env).strip()
subprocess.run(['xcrun','--sdk','iphonesimulator','swiftc','-swift-version','5','-target','arm64-apple-ios15.0-simulator','-sdk',sdk,str(work/'Production.swift'),str(work/'App.swift'),'-o',str(app/'ScreenshotChecks')],env=env,check=True,capture_output=True,timeout=90)
subprocess.run(['codesign','--force','--sign','-',str(app)],env=env,check=True,capture_output=True)
subprocess.run(['xcrun','simctl','install',uid,str(app)],env=env,check=True,capture_output=True,timeout=60)
subprocess.run(['xcrun','simctl','terminate',uid,'test.regram.screenshotchecks'],env=env,capture_output=True,timeout=15)
containerBefore=Path(subprocess.check_output(['xcrun','simctl','get_app_container',uid,'test.regram.screenshotchecks','data'],env=env,text=True,timeout=30).strip())
(containerBefore/'Documents/results.json').unlink(missing_ok=True)
subprocess.run(['xcrun','simctl','launch',uid,'test.regram.screenshotchecks'],env=env,check=True,capture_output=True,timeout=30)
container=Path(subprocess.check_output(['xcrun','simctl','get_app_container',uid,'test.regram.screenshotchecks','data'],env=env,text=True).strip());result=container/'Documents/results.json'
for _ in range(40):
 if result.exists():break
 time.sleep(.5)
if not result.exists():raise RuntimeError('Drawing fixture did not produce a report')
preview=container/'Documents/preview.png'
if preview.exists():(work/'preview.png').write_bytes(preview.read_bytes())
report=json.loads(result.read_text());(work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False))
assert all(report.values()),'Production screenshot drawing regression'
