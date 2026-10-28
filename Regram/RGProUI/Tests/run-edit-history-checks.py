from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[3]
with tempfile.TemporaryDirectory(prefix='regram-photo-history-tests-') as temporary:
 work=Path(temporary)
 header=root/'submodules/MurMurHash32/PublicHeaders/MurMurHash32/MurMurHash32.h'
 (work/'module.modulemap').write_text('module MurMurHash32 { header "'+str(header)+'" export * }\n')
 subprocess.run(['xcrun','clang','-dynamiclib','-fobjc-arc','-framework','Foundation','-I',str(root/'submodules/MurMurHash32/PublicHeaders'),str(root/'submodules/MurMurHash32/Sources/MurMurHash32.m'),'-o',str(work/'libMurMurHash32.dylib')],check=True)
 production=(root/'submodules/TelegramCore/Sources/SyncCore/SyncCore_RGEditHistoryMessageAttribute.swift').read_text().replace('import Postbox\n','')
 (work/'History.swift').write_text(production)
 rich=(root/'submodules/TelegramCore/Sources/SyncCore/SyncCore_RichTextMessageAttribute.swift').read_text().split('\nextension RichTextMessageAttribute {')[0]
 rich='\n'.join(line for line in rich.splitlines() if not line.startswith(('import ', 'internal import ')))
 (work/'RichAttribute.swift').write_text(rich)
 adapters='''
import Foundation
func postboxLog(_ value:String) {}
func mdb_cmp_memn(_ a:UnsafeRawPointer,_ al:Int,_ b:UnsafeRawPointer,_ bl:Int)->Int32 {
 let result=memcmp(a,b,min(al,bl));return result != 0 ? result : (al==bl ? 0 : (al<bl ? -1 : 1))
}
public protocol MessageAttribute:PostboxCoding {}
public typealias PeerId=Int64
public typealias MediaId=Int64
public struct MessageTextEntity:PostboxCoding,Equatable {
 let value:String
 init(_ value:String){self.value=value}
 public init(decoder:PostboxDecoder){value=decoder.decodeStringForKey("e",orElse:"")}
 public func encode(_ encoder:PostboxEncoder){encoder.encodeString(value,forKey:"e")}
}
public class TelegramMediaImage:PostboxCoding {
 let imageId:Int64
 init(_ id:Int64){imageId=id}
 required public init(decoder:PostboxDecoder){imageId=decoder.decodeInt64ForKey("id",orElse:0)}
 public func encode(_ encoder:PostboxEncoder){encoder.encodeInt64(imageId,forKey:"id")}
}
public struct Message {let attributes:[MessageAttribute]}
public struct InstantPage:PostboxCoding,Equatable {
 let blocks:String
 init(_ blocks:String){self.blocks=blocks}
 public init(decoder:PostboxDecoder){blocks=decoder.decodeStringForKey("b",orElse:"")}
 public func encode(_ encoder:PostboxEncoder){encoder.encodeString(blocks,forKey:"b")}
}
'''
 (work/'Adapters.swift').write_text(adapters)
 (work/'Tests.swift').write_text('''
import Foundation
@main enum Tests {
 static func main() {
  declareEncodable(TelegramMediaImage.self,f:{TelegramMediaImage(decoder:$0)})
  declareEncodable(RGEditHistoryEntry.self,f:{RGEditHistoryEntry(decoder:$0)})
  declareEncodable(MessageTextEntity.self,f:{MessageTextEntity(decoder:$0)})
  let legacy=PostboxEncoder();legacy.encodeString("old caption",forKey:"t");legacy.encodeInt32(7,forKey:"d");legacy.encodeObjectArray([MessageTextEntity("bold")],forKey:"e")
  let old=RGEditHistoryEntry(decoder:PostboxDecoder(buffer:MemoryBuffer(data:legacy.makeData())))
  precondition(old.image == nil && old.imageData == nil && old.text == "old caption" && old.entities.count==1)
  precondition(old.richText == nil)
  let rich = RichTextMessageAttribute(instantPage:InstantPage("heading | cell"),fullInstantPage:InstantPage("full heading | full cell"))
  let richRow = RGEditHistoryEntry(text:"heading | cell",entities:[],date:9,richText:rich)
  let richEncoder=PostboxEncoder();richRow.encode(richEncoder)
  let restoredRich=RGEditHistoryEntry(decoder:PostboxDecoder(buffer:MemoryBuffer(data:richEncoder.makeData())))
  precondition(restoredRich==richRow && restoredRich.richText?.fullInstantPage==rich.fullInstantPage)
  rich.fullInstantPage=InstantPage("later cache change")
  precondition(restoredRich.richText?.fullInstantPage==InstantPage("full heading | full cell") && richRow.richText?.fullInstantPage==restoredRich.richText?.fullInstantPage)
  let bytes=Data([1,2,3,4]);let row=RGEditHistoryEntry(text:"photo caption",entities:[MessageTextEntity("italic")],date:10,image:TelegramMediaImage(11),imageData:bytes,imageHasSpoiler:true)
  let encoder=PostboxEncoder();row.encode(encoder)
  let decoded=RGEditHistoryEntry(decoder:PostboxDecoder(buffer:MemoryBuffer(data:encoder.makeData())))
  precondition(decoded==row && decoded.image?.imageId==11 && decoded.imageData==bytes && decoded.imageHasSpoiler)
  let changed=RGEditHistoryEntry(text:row.text,entities:row.entities,date:row.date,image:TelegramMediaImage(12),imageData:Data([9]))
  let history=RGEditHistoryMessageAttribute(entries:[]).withAppendedEntry(row).withAppendedEntry(changed)
  precondition(history.entries.count==2 && history.withAppendedEntry(changed).entries.count==2)
  let oversized=RGEditHistoryEntry(text:"",entities:[],date:1,image:TelegramMediaImage(13),imageData:Data(count:RGEditHistoryEntry.maximumImageBytes+1))
  precondition(oversized.imageData == nil && oversized.image != nil)
  var bounded=RGEditHistoryMessageAttribute(entries:[])
  let large=Data(count:RGEditHistoryEntry.maximumImageBytes)
  for i in 0..<55 { bounded=bounded.withAppendedEntry(RGEditHistoryEntry(text:String(i),entities:[],date:Int32(i),image:TelegramMediaImage(Int64(i)),imageData:large)) }
  precondition(bounded.entries.count==50 && bounded.entries.first?.date==0 && bounded.entries.first?.imageData==large && bounded.entries.last?.date==54)
  precondition(bounded.entries.reduce(0){$0+($1.imageData?.count ?? 0)}<=RGEditHistoryMessageAttribute.maximumImageHistoryBytes)
  let store=PostboxEncoder();bounded.encode(store)
  let reopened=RGEditHistoryMessageAttribute(decoder:PostboxDecoder(buffer:MemoryBuffer(data:store.makeData())))
  precondition(reopened.entries==bounded.entries)
  let hydrated=history.withImageData(Data([7,8]),at:0)
  precondition(hydrated.entries.count==2 && hydrated.entries[0].imageData==Data([7,8]) && hydrated.entries[0].date==row.date)
  print("Photo history checks passed with production Postbox codec: legacy records, captions, images, spoilers, restart decoding, deduplication, limits and hydration.")
 }
}
''')
 subprocess.run(['xcrun','swiftc','-swift-version','5','-I',str(work),'-L',str(work),'-lMurMurHash32','-Xlinker','-rpath','-Xlinker',str(work),str(root/'submodules/Postbox/Sources/Coding.swift'),*[str(f) for f in sorted((root/'submodules/Postbox/Sources/Utils').rglob('*.swift'))],str(work/'Adapters.swift'),str(work/'RichAttribute.swift'),str(work/'History.swift'),str(work/'Tests.swift'),'-o',str(work/'tests')],check=True)
 subprocess.run([str(work/'tests')],check=True)
