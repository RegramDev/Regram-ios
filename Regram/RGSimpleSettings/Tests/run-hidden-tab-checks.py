"""Exercise production settings visibility and action wiring with UI boundary adapters."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'submodules/ChatListUI/Sources/ChatListController.swift').read_text()
a = source.index('    var settingsButton: AnyComponentWithIdentity<NavigationButtonComponentEnvironment>? {')
b = source.index('\n    var proxyButton:', a)
getter = source[a:b]
a = source.index('    @objc fileprivate func settingsPressed()')
pressed = source[a:].split('\n}\n', 1)[0].replace('@objc fileprivate func', 'func')
adapters = '''
import Foundation
final class RGSimpleSettings {static let shared=RGSimpleSettings();var bottomBarSettings=Settings()}
struct Settings {var isBottomBarVisible=true}
enum Group {case root,archive}
enum Location {case chatList(Group),forum}
enum NavigationButtonComponentEnvironment {}
struct AnyComponent {let value:NavigationButtonComponent;init(_ value:NavigationButtonComponent){self.value=value}}
struct AnyComponentWithIdentity<E> {let id:String;let component:AnyComponent}
struct NavigationButtonComponent {
 enum Content {case settings(title:String)}
 let content:Content;let pressed:(String)->Void;let contextAction:((String,String?)->Void)?
}
struct Strings {let Settings_Title="Settings"}
struct DataValue {let strings=Strings()}
final class Box {func with<T>(_ f:(DataValue)->T)->T {f(DataValue())}}
final class AccountSettings {var menus=0;func tabBarItemContextActionRawUIView(sourceView:String,gesture:String?){menus+=1}}
protocol TelegramRootControllerInterface:AnyObject {var accountSettingsController:AccountSettings?{get};func openSettings(edit:Bool)}
final class Root:TelegramRootControllerInterface {let accountSettingsController:AccountSettings?=AccountSettings();var opened=0;func openSettings(edit:Bool){precondition(!edit);opened+=1}}
final class Window {let viewController:Any;init(_ root:Root){viewController=root}}
final class Shared {let currentPresentationData=Box();var mainWindow:Window?}
final class Context {let sharedContext=Shared()}
final class ChatListControllerImpl {let context:Context;init(_ context:Context){self.context=context}
'''
tests = '''
}
final class Header {
 let context:Context;let location:Location;weak var parentController:ChatListControllerImpl?
 var rgSettingsEditing=false;var rgSettingsReordering=false
 init(_ context:Context,_ parent:ChatListControllerImpl,_ location:Location){self.context=context;parentController=parent;self.location=location}
'''
end = '''
}
@main enum Tests {static func main() {
 let context=Context();let root=Root();context.sharedContext.mainWindow=Window(root)
 let parent=ChatListControllerImpl(context);let header=Header(context,parent,.chatList(.root))
 precondition(header.settingsButton==nil)
 RGSimpleSettings.shared.bottomBarSettings.isBottomBarVisible=false
 let button=header.settingsButton!;precondition(button.id=="settings")
 button.component.value.pressed("view");precondition(root.opened==1)
 button.component.value.contextAction?("view",nil);precondition(root.accountSettingsController!.menus==1)
 header.rgSettingsEditing=true;precondition(header.settingsButton==nil)
 header.rgSettingsEditing=false;header.rgSettingsReordering=true;precondition(header.settingsButton==nil)
 header.rgSettingsReordering=false;precondition(header.settingsButton != nil)
 let archive=Header(context,parent,.chatList(.archive)),forum=Header(context,parent,.forum)
 precondition(archive.settingsButton==nil && forum.settingsButton==nil)
 RGSimpleSettings.shared.bottomBarSettings.isBottomBarVisible=true;precondition(header.settingsButton==nil)
 print("Production hidden-tab settings getter updates without a network event; tap, account menu, selection, reordering, nested lists and restoration passed.")
}}
'''
with tempfile.TemporaryDirectory(prefix='regram-hidden-tab-checks-') as directory:
    path = Path(directory)
    (path / 'Tests.swift').write_text(adapters + pressed + tests + getter + end)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors',
                    str(root / 'Regram/RGSimpleSettings/Sources/RGHiddenTabBarPolicy.swift'),
                    str(path / 'Tests.swift'), '-o', str(path / 'tests')], check=True)
    subprocess.run([str(path / 'tests')], check=True)
