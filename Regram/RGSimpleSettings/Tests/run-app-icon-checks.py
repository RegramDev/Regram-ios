#!/usr/bin/env python3
"""Run the production icon coordinator with controlled UIKit callback, getter and lifecycle timing."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[3]
with tempfile.TemporaryDirectory(prefix='regram-icon-checks-') as d:
    binary=Path(d)/'checks'
    subprocess.run(['xcrun','swiftc','-swift-version','5','-warnings-as-errors','-parse-as-library',str(root/'Regram/RGSimpleSettings/Sources/AppIconNames.swift'),str(root/'Regram/RGSimpleSettings/Sources/RGAppIconSwitchCoordinator.swift'),str(root/'Regram/RGSimpleSettings/Tests/AppIconSwitchTests.swift'),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=20)
    # Exercise the real settings completion and AppDelegate getter with external UIKit/list adapters.
    app=(root/'submodules/TelegramUI/Sources/AppDelegate.swift').read_text()
    a=app.index('        }, getAlternateIconName: {')+len('        }, getAlternateIconName: {')
    getter=app[a:app.index('        }, requestSetAlternateIconName:',a)]
    settings=(root/'submodules/SettingsUI/Sources/Themes/ThemeSettingsController.swift').read_text()
    a=settings.index('    }, selectAppIcon: { icon in')
    a=settings.index('        let apply = {',a)
    apply=settings[a:settings.index('        if !icon.isPremium',a)]
    boundary='''
import Foundation
final class RawApplication { var alternateIconName:String?; var desktopIcon:String?; var requests:[(String?,(Bool)->Void)]=[]
 func finish(_ i:Int,_ success:Bool) { if success { desktopIcon=requests[i].0 };requests[i].1(success) }
}
func makeGetter(iconSwitcher:RGAppIconSwitchCoordinator,application:RawApplication)->()->String? { return {
'''+getter+'''\n} }
struct Icon {let name:String;let isDefault:Bool}
struct Language {var languageCode="en"}
struct Strings {var primaryComponent=Language();var secondaryComponent:Language?;var Appearance_AppIcon="Icon";var Common_OK="OK"}
struct Presentation {var strings=Strings()}
final class Box {func with<T>(_ f:(Presentation)->T)->T {f(Presentation())}}
final class Bindings {let coordinator:RGAppIconSwitchCoordinator;let getAlternateIconName:()->String?
 init(_ coordinator:RGAppIconSwitchCoordinator,_ getter:@escaping ()->String?){self.coordinator=coordinator;getAlternateIconName=getter}
 func requestSetAlternateIconName(_ name:String?,_ completion:@escaping(Bool)->Void){coordinator.request(name,completion:completion)}
}
struct Shared {let applicationBindings:Bindings;let currentPresentationData=Box()}
struct Context {let sharedContext:Shared}
final class RGLocalizationManager {static let shared=RGLocalizationManager();func preferredLocale(primary:String,secondary:String?)->String {primary}}
extension String {func i18n(_ language:String)->String {self}}
struct TextAlertAction {enum Kind {case defaultAction};init(type:Kind,title:String,action:()->Void){}}
func textAlertController(context:Context,title:String,text:String,actions:[TextAlertAction])->String {text}
final class UI {
 let application=RawApplication();let coordinator:RGAppIconSwitchCoordinator;let context:Context
 var selected="RGDefault";var alerts=0
 init(){let raw=application;coordinator=RGAppIconSwitchCoordinator(current:{raw.alternateIconName},apply:{raw.requests.append(($0,$1))},changed:{},schedule:{_,_ in})
 context=Context(sharedContext:Shared(applicationBindings:Bindings(coordinator,makeGetter(iconSwitcher:coordinator,application:raw))))}
 func choose(_ name:String?) {let icon=Icon(name:name ?? "RGDefault",isDefault:name==nil);let context=self.context
 let refreshAppIcon={self.selected=context.sharedContext.applicationBindings.getAlternateIconName() ?? "RGDefault"}
 let presentControllerImpl:((String,Any?)->Void)?={_,_ in self.alerts+=1}
'''+apply+'''
 apply()
 }
}
@main enum Checks {static func main(){
 let ui=UI();ui.choose("RGBlack");ui.application.finish(0,true)
 precondition(ui.application.desktopIcon=="RGBlack" && ui.application.alternateIconName==nil)
 precondition(ui.selected=="RGBlack" && ui.alerts==0,"A successful change with a stale UIKit getter must select the new icon without an application alert")
 ui.coordinator.resume()
 precondition(ui.context.sharedContext.applicationBindings.getAlternateIconName()=="RGBlack")
 ui.choose("RGGold");ui.application.finish(1,false)
 precondition(ui.alerts==1 && ui.selected=="RGBlack","Only a genuine failed completion may present an application error")
 ui.choose(nil);ui.application.finish(2,true)
 precondition(ui.alerts==1 && ui.selected=="RGDefault","Restoring the primary icon must also complete quietly")
 print("Production icon getter and Appearance completion: delayed UIKit state selects the acknowledged icon; successful alternate/primary changes show no application alert; genuine failure shows one.")
}}
'''
    source=Path(d)/'UI.swift';source.write_text(boundary)
    ui=Path(d)/'ui'
    subprocess.run(['xcrun','swiftc','-swift-version','5','-warnings-as-errors','-parse-as-library',str(root/'Regram/RGSimpleSettings/Sources/AppIconNames.swift'),str(root/'Regram/RGSimpleSettings/Sources/RGAppIconSwitchCoordinator.swift'),str(source),'-o',str(ui)],check=True)
    subprocess.run([str(ui)],check=True,timeout=20)
