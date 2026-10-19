"""Run the production message screenshot composer in an isolated iOS simulator fixture."""
from pathlib import Path
import argparse,json,os,plistlib,subprocess,time
root=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser();parser.add_argument('--simulator',required=True);parser.add_argument('--output',default='build-input/message-screenshot-checks');args=parser.parse_args()
work=root/args.output;work.mkdir(parents=True,exist_ok=True)
env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode-27.0.app/Contents/Developer')
uid=args.simulator
s=(root/'Regram/RGProUI/Sources/RGMessageScreenshot.swift').read_text().replace('import Display', 'private enum Font { static func semibold(_ size: CGFloat) -> UIFont { .systemFont(ofSize: size, weight: .semibold) } }')
capture=(root/'submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift').read_text()
a=capture.index('    public func rgMessageScreenshotBody(');b=capture.index('    override public func makeContentSnapshot()',a)
adapter='\nclass ASDisplayNode {\n let view:UIView\n init(_ view:UIView=UIView()){self.view=view}\n var isHidden:Bool{get{view.isHidden}set{view.isHidden=newValue}}\n var alpha:CGFloat{view.alpha}\n}\nclass Source {let contentNode:ASDisplayNode;var contentRect:CGRect;init(_ view:UIView){contentNode=ASDisplayNode(view);contentRect=view.bounds}}\nclass Container {var backgroundWallpaperNode:ASDisplayNode?;var backgroundNode:ASDisplayNode?;var selectionBackgroundNode:ASDisplayNode?}\nclass Capture {\n let source:Source;let backgroundWallpaperNode=ASDisplayNode();let backgroundNode=ASDisplayNode();let shadowNode=ASDisplayNode()\n var nameAvatarNode:ASDisplayNode?;var rankBadgeNode:ASDisplayNode?;var rankBackgroundNode:ASDisplayNode?;var credibilityIconView:UIView?;var boostBadgeNode:ASDisplayNode?;var boostIconNode:UIImageView?;var nameNode:ASDisplayNode?;var contentContainers:[Container]=[]\n init(){let view=UIView(frame:CGRect(x:0,y:0,width:180,height:76));source=Source(view)\n for node in [backgroundWallpaperNode,backgroundNode,shadowNode]{node.view.frame=view.bounds;node.view.backgroundColor = .magenta;view.addSubview(node.view)}\n let text=UILabel(frame:CGRect(x:8,y:34,width:164,height:30));text.text="早上好";text.textColor = .blue;view.addSubview(text)\n let name=UILabel(frame:CGRect(x:8,y:4,width:164,height:26));name.text="示例群员";name.textColor = .green;view.addSubview(name);nameNode=ASDisplayNode(name)\n }\n func getMessageContextSourceNode(stableId:UInt32)->Source?{source}\n'
(work/'Production.swift').write_text(s+adapter+capture[a:b]+'\n}\n')
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
  func pixel(_ image:UIImage,x:CGFloat,y:CGFloat)->(UInt8,UInt8,UInt8,UInt8){
   var bytes=[UInt8](repeating:0,count:4)
   let context=CGContext(data:&bytes,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue)!
   context.translateBy(x:-x*image.scale,y:-(image.size.height-y)*image.scale);context.draw(image.cgImage!,in:CGRect(x:0,y:0,width:image.cgImage!.width,height:image.cgImage!.height));return(bytes[0],bytes[1],bytes[2],bytes[3])
  }
  func redCount(_ image:UIImage)->Int {var n=0;for y in 12..<38 {for x in 60..<Int(image.size.width)-12 {let p=pixel(image,x:CGFloat(x),y:CGFloat(y));if p.0>120 && p.1<50 && p.2<50{n+=1}}};return n}
  let capture=Capture();let original=capture.rgMessageScreenshotBody(stableId:1)!
  results["native_name_row_removed"]=original.size.height==50
  results["bubble_background_excluded"]=pixel(original,x:1,y:1).3==0
  results["chat_background_visibility_restored"] = !capture.backgroundWallpaperNode.isHidden && !capture.backgroundNode.isHidden && !capture.shadowNode.isHidden
  let avatar=UIGraphicsImageRenderer(size:CGSize(width:76,height:76)).image{c in UIColor.red.setFill();c.fill(CGRect(x:0,y:0,width:76,height:76))}
  let present=rgMessageScreenshot(body:original,senderName:"示例群员",avatar:avatar,backgroundColor:.white,textColor:.red)
  results["uniform_sender_header"]=redCount(present)>20 && present.size.height==100
  results["avatar_retained"]=pixel(present,x:31,y:31).0>240 && pixel(present,x:31,y:31).1<10
  let detached=UIView();detached.addSubview(capture.nameNode!.view)
  for view in capture.source.contentNode.view.subviews {if let label=view as? UILabel,label.text=="早上好" {label.frame.origin.y=8}}
  capture.source.contentRect.size.height=50
  let hidden=capture.rgMessageScreenshotBody(stableId:1)!
  let absent=rgMessageScreenshot(body:hidden,senderName:"示例群员",avatar:avatar,backgroundColor:.white,textColor:.red)
  results["omitted_sender_added_with_same_layout"]=redCount(absent)>20 && absent.size==present.size
  results["body_positions_identical"]=present.pngData()==absent.pngData()
  capture.source.contentRect = .zero
  results["invalid_capture_safe"]=capture.rgMessageScreenshotBody(stableId:1)==nil
  let dark=rgMessageScreenshot(body:hidden,senderName:"示例群员",avatar:nil,backgroundColor:.black,textColor:.white)
  results["dark_mode_and_initial"]=pixel(dark,x:15,y:15).3==255 && dark.size.height==100
  let outputFolder=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
  try! present.pngData()!.write(to:outputFolder.appendingPathComponent("preview.png"));try! absent.pngData()!.write(to:outputFolder.appendingPathComponent("missing-name.png"))
  let output=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("results.json")
  try! JSONSerialization.data(withJSONObject:results,options:[.sortedKeys,.prettyPrinted]).write(to:output)
  print("Screenshot fixture finished")
 }
}
''')
app=work/'ScreenshotChecks.app';app.mkdir(exist_ok=True)
(app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'ScreenshotChecks','CFBundleIdentifier':'test.regram.screenshotchecks','CFBundleName':'ScreenshotChecks','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','CFBundlePackageType':'APPL','CFBundleSupportedPlatforms':['iPhoneSimulator'],'MinimumOSVersion':'15.0','UIDeviceFamily':[1],'LSRequiresIPhoneOS':True,'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait']}))
sdk=subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True,env=env).strip()
subprocess.run(['xcrun','--sdk','iphonesimulator','swiftc','-swift-version','5','-target','arm64-apple-ios15.0-simulator','-sdk',sdk,str(work/'Production.swift'),str(work/'App.swift'),'-o',str(app/'ScreenshotChecks')],env=env,check=True,timeout=90)
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
missing=container/'Documents/missing-name.png'
if missing.exists():(work/'missing-name.png').write_bytes(missing.read_bytes())
report=json.loads(result.read_text());(work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False))
assert all(report.values()),'Production screenshot drawing regression'
