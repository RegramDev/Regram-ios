"""Run the production UIKit tint function in an isolated iOS simulator fixture."""
from pathlib import Path
import argparse,json,os,plistlib,subprocess,time
root=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser();parser.add_argument('--simulator',required=True);parser.add_argument('--output',default='build-input/image-tint-checks');args=parser.parse_args()
work=root/args.output;work.mkdir(parents=True,exist_ok=True)
env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode-27.0.app/Contents/Developer')
uid=args.simulator
s=(root/'submodules/Display/Source/GenerateImage.swift').read_text();a=s.index('public func generateTintedImage(');b=s.index('\npublic func generateGradientTintedImage(',a)
(work/'Production.swift').write_text('import UIKit\nimport CoreImage\n'+s[a:b])
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
  func pixels(_ image:UIImage?) -> (count:Int,white:Bool,centroid:Double) {
   guard let image,let cg=image.cgImage else {return (0,false,0)}
   let w=cg.width,h=cg.height;var bytes=[UInt8](repeating:0,count:w*h*4)
   guard let context=CGContext(data:&bytes,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue) else {return (0,false,0)}
   context.draw(cg,in:CGRect(x:0,y:0,width:w,height:h));var count=0,white=true;var xTotal=0.0
   for y in 0..<h {for x in 0..<w {let i=(y*w+x)*4;if bytes[i+3]>240 {count+=1;xTotal+=Double(x);white = white && bytes[i]>240 && bytes[i+1]>240 && bytes[i+2]>240}}}
   return (count,white,count>0 ? xTotal/Double(count)/Double(w):0)
  }
  let symbol=UIImage(systemName:"bookmark");let tinted=generateTintedImage(image:symbol,color:.white)
  let symbolPixels=pixels(tinted);results["symbol_dark_mode_white"]=symbolPixels.count>10 && symbolPixels.white
  let ci=UIImage(ciImage:CIImage(color:CIColor.black).cropped(to:CGRect(x:0,y:0,width:12,height:8)))
  results["ci_input_has_no_bitmap"]=ci.cgImage == nil
  let ciPixels=pixels(generateTintedImage(image:ci,color:.white));results["ci_image_safe_and_white"]=ciPixels.count>10 && ciPixels.white
  let raster=UIGraphicsImageRenderer(size:CGSize(width:20,height:20)).image { c in UIColor.red.setFill();c.fill(CGRect(x:1,y:2,width:5,height:15)) }
  let regular=pixels(generateTintedImage(image:raster,color:.white)),flipped=pixels(generateTintedImage(image:raster,color:.white,flipHorizontally:true))
  results["bitmap_tint_preserved"]=regular.count>10 && regular.white
  results["horizontal_flip_preserved"]=regular.centroid<0.5 && flipped.centroid>0.5
  results["custom_dimensions"]=generateTintedImage(image:symbol,color:.white,customSize:CGSize(width:40,height:20))?.size == CGSize(width:40,height:20)
  results["empty_safe"]=generateTintedImage(image:UIImage(),color:.white) == nil
  results["nil_safe"]=generateTintedImage(image:nil,color:.white) == nil
  let probe = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(ci.ciImage!, from:ci.ciImage!.extent, format:.RGBA8, colorSpace:CGColorSpaceCreateDeviceRGB())
  let diagnostics:[String:Any] = ["ciWidth":Double(ci.size.width),"ciHeight":Double(ci.size.height),"renderedBitmap":probe != nil,"alpha":probe?.alphaInfo.rawValue ?? 99,"tintedPixelCount":ciPixels.count,"tintedWhite":ciPixels.white]
  let diagnosticURL=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("diagnostics.json")
  try! JSONSerialization.data(withJSONObject:diagnostics).write(to:diagnosticURL)
  let output=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("results.json")
  try! JSONSerialization.data(withJSONObject:results,options:[.sortedKeys,.prettyPrinted]).write(to:output)
  print("Tint fixture finished")
 }
}
''')
app=work/'TintChecks.app';app.mkdir(exist_ok=True)
(app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'TintChecks','CFBundleIdentifier':'test.regram.tintchecks','CFBundleName':'TintChecks','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','CFBundlePackageType':'APPL','CFBundleSupportedPlatforms':['iPhoneSimulator'],'MinimumOSVersion':'15.0','UIDeviceFamily':[1],'LSRequiresIPhoneOS':True,'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait']}))
sdk=subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True,env=env).strip()
subprocess.run(['xcrun','--sdk','iphonesimulator','swiftc','-swift-version','5','-target','arm64-apple-ios15.0-simulator','-sdk',sdk,str(work/'Production.swift'),str(work/'App.swift'),'-o',str(app/'TintChecks')],env=env,check=True,capture_output=True,timeout=90)
subprocess.run(['codesign','--force','--sign','-',str(app)],env=env,check=True,capture_output=True)
subprocess.run(['xcrun','simctl','install',uid,str(app)],env=env,check=True,capture_output=True,timeout=60)
subprocess.run(['xcrun','simctl','terminate',uid,'test.regram.tintchecks'],env=env,capture_output=True,timeout=15)
containerBefore=Path(subprocess.check_output(['xcrun','simctl','get_app_container',uid,'test.regram.tintchecks','data'],env=env,text=True,timeout=30).strip())
(containerBefore/'Documents/results.json').unlink(missing_ok=True)
subprocess.run(['xcrun','simctl','launch',uid,'test.regram.tintchecks'],env=env,check=True,capture_output=True,timeout=30)
container=Path(subprocess.check_output(['xcrun','simctl','get_app_container',uid,'test.regram.tintchecks','data'],env=env,text=True).strip());result=container/'Documents/results.json'
for _ in range(40):
 if result.exists():break
 time.sleep(.5)
if not result.exists():raise RuntimeError('Drawing fixture did not produce a report')
diagnostics=container/'Documents/diagnostics.json'
if diagnostics.exists():print('Format diagnostics:',diagnostics.read_text())
report=json.loads(result.read_text());(work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False))
assert all(report.values()),'Production tint drawing regression'
