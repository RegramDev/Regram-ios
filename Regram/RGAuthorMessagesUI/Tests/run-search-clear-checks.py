#!/usr/bin/env python3
"""Exercise production search callbacks with an isolated adapter for SearchBarNode's public API."""
from pathlib import Path
import argparse,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser();parser.add_argument('--baseline',action='store_true');args=parser.parse_args()
source=(ROOT/'Regram/RGAuthorMessagesUI/Sources/RGAuthorMessagesController.swift').read_text()
a=source.index('        self.searchBar.textUpdated =');b=source.index('        self.presentationDisposable =',a)
setup=source[a:b]
if args.baseline:
 c=setup.index('        self.searchBar.cancel =');d=setup.index('        self.searchBar.textReturned =',c)
 setup=setup[:c]+setup[d:];setup=setup.replace('debounce: !query.isEmpty','debounce: true')
fixture=r'''
import Foundation
final class SearchBar {
 var cancel:(()->Void)?, textUpdated:((String,String?)->Void)?, textReturned:((String)->Void)?
 private var value="";var active=true
 var text:String { get{value} set{if value != newValue {value=newValue;textUpdated?(value,nil)}} }
 func deactivate(clear:Bool) {active=false;if clear {value=""}}
}
final class Controller {
 let searchBar=SearchBar();var query="";var requests:[(String,Bool)]=[];var generation=0
 init(){ SETUP }
 func loadMessages(debounce:Bool) { generation += 1;requests.append((query,debounce)) }
}
@main struct Tests {
 static func main(){
  var checks=0
  func check(_ v:Bool,_ m:String) { checks += 1; precondition(v,m) }
  let c=Controller()
  c.searchBar.text="search"
  check(c.query=="search" && c.requests.last?.1==true,"typed searches debounce")
  check(c.searchBar.cancel != nil,"glass outside close callback is connected")
  let old=c.generation;c.searchBar.cancel?()
  check(c.searchBar.text.isEmpty && c.query.isEmpty,"outside cross clears text and query")
  check(c.requests.last?.0=="" && c.requests.last?.1==false,"restore all sender messages immediately")
  check(c.generation==old+1,"clearing invalidates the previous search request")
  check(!c.searchBar.active,"outside cross dismisses keyboard")
  let after=c.requests.count;c.searchBar.cancel?()
  check(c.requests.count==after,"empty close does not create duplicate requests")
  c.searchBar.active=true;c.searchBar.text="  群消息  ";c.searchBar.cancel?()
  check(c.query.isEmpty && c.requests.last?.0=="","Chinese query clears and restores")
  c.searchBar.text="   ";let empty=c.requests.count;c.searchBar.cancel?()
  check(c.searchBar.text.isEmpty && c.requests.count==empty,"whitespace clears without a redundant query")
  c.searchBar.text="retained";c.searchBar.textReturned?("retained")
  check(c.query=="retained" && c.searchBar.text=="retained","keyboard return keeps the current search")
  print("Author search clear: \(checks) checks passed")
 }
}
'''.replace('SETUP',setup)
with tempfile.TemporaryDirectory(prefix='regram-author-clear-') as temp:
 p=Path(temp);(p/'main.swift').write_text(fixture)
 subprocess.run(['xcrun','swiftc','-parse-as-library','-warnings-as-errors',str(p/'main.swift'),'-o',str(p/'tests')],check=True)
 subprocess.run([str(p/'tests')],check=True)
