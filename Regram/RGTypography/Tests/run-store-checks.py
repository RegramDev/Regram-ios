#!/usr/bin/env python3
"""Exercise production font storage on macOS with local HTTP fixtures and the real ZipArchive.
Only sandbox-root, bundle lookup and settings notification adapters are replaced.
Run with DEVELOPER_DIR set to the Xcode used for your app build. No simulator is used.
"""
from pathlib import Path
import concurrent.futures,hashlib,http.server,json,plistlib,subprocess,threading,time,tempfile,zipfile
root=Path(__file__).resolve().parents[3]
temporary=tempfile.TemporaryDirectory(prefix='regram-font-store-tests-')
work=Path(temporary.name);task=work

clang=subprocess.check_output(['xcrun','--find','clang'],text=True).strip()
swift=subprocess.check_output(['xcrun','--find','swiftc'],text=True).strip()
sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
catalog=json.loads((root/'Regram/RGTypography/RGFontCatalog.json').read_text())
files=catalog['files']
archive=work/'Inter-fixture.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
 for f in files:
  if f.get('archive_member'):z.write(root/'Regram/RGTypography/Fonts'/f['file'],f['archive_member'])
archive_hash=hashlib.sha256(archive.read_bytes()).hexdigest()
objects=[]
def compile_c(p):
 obj=work/(p.stem+'.o');flags=['-isysroot',sdk,'-I'+str(root/'third-party/ZipArchive/PublicHeaders')]+['-D'+v for v in ['HAVE_ZLIB','HAVE_INTTYPES_H','HAVE_PKCRYPT','HAVE_STDINT_H','HAVE_WZAES']]
 if p.suffix=='.m':flags+=['-fobjc-arc']
 r=subprocess.run([clang]+flags+['-c',str(p),'-o',str(obj)],capture_output=True)
 if r.returncode:raise RuntimeError(r.stderr.decode())
 return obj
sources=list((root/'third-party/ZipArchive/Sources').glob('*.m'))+list((root/'third-party/ZipArchive/Sources/minizip').glob('*.c'))
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:objects=list(pool.map(compile_c,sources))
(work/'module.modulemap').write_text('module ZipArchive { header "'+str(root/'third-party/ZipArchive/PublicHeaders/ZipArchive/ZipArchive.h')+'" export * }')
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*a):pass
 def do_GET(self):
  if self.path=='/slow':time.sleep(3)
  if self.path=='/inter':p=archive
  elif self.path=='/missing':self.send_error(404);return
  else:p=root/'Regram/RGTypography/Fonts'/self.path.split('/')[-1] if self.path!='/slow' else root/'Regram/RGTypography/Fonts/JetBrainsMono-Regular.ttf'
  data=p.read_bytes();self.send_response(200);self.send_header('Content-Length',str(len(data)));self.end_headers()
  try:self.wfile.write(data)
  except (BrokenPipeError, ConnectionResetError):pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);threading.Thread(target=server.serve_forever,daemon=True).start()
base='http://127.0.0.1:'+str(server.server_port)
selected=[]
for f in files:
 if f['file'].startswith(('JetBrainsMono-','Inter-','GoogleSansCode-')):
  f=dict(f);f['source']=base+('/inter' if f.get('archive_member') else '/'+f['file']);
  if f.get('archive_member'):f['archive_sha256']=archive_hash
  selected.append(f)
original=selected[0]
for prefix,path,hash in [('Bad','/'+original['file'],'0'*64),('Missing','/missing',original['sha256']),('Slow','/slow',original['sha256'])]:
 f=dict(original,file=prefix+'-Regular.ttf',source=base+path,sha256=hash);selected.append(f)
bundle=work/'Fixtures.bundle';bundle.mkdir(exist_ok=True);(bundle/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'app.regram.font-store-tests','CFBundlePackageType':'BNDL'}));(bundle/'RGFontCatalog.json').write_text(json.dumps({'files':selected,'families':[f for f in catalog.get('families',[]) if f['id']=='GoogleSansCode']}))
s=(root/'Regram/RGTypography/Sources/RGFontStore.swift').read_text().replace('import AppBundle\n','').replace('import RGSimpleSettings\n','')
a=s.index('        let base = FileManager.default.urls');b=s.index('    nonisolated private static let catalog',a)
s=s[:a]+'        return URL(fileURLWithPath: '+json.dumps(str(work/'Cache'))+')\n    }\n'+s[b:]
(work/'Store.swift').write_text(s)
(work/'Tests.swift').write_text('''import Foundation
func getAppBundle() -> Bundle { Bundle(path: BUNDLE)! }
final class RGSimpleSettings { static let shared = RGSimpleSettings(); var fontAssetsRevision = 0; var fontImportedLatin = ""; var fontImportedChinese = ""; var fontFamily = "system"; var fontChineseFamily = "system" }
@main @MainActor enum StoreChecks {
 static func expect(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
 static func download(_ prefix: String) async -> Result<Void, Error> { await withCheckedContinuation { c in RGFontStore.shared.download(prefix: prefix) { c.resume(returning: $0) } } }
 static func importFile(_ url: URL) async -> Result<RGImportedFont, Error> { await withCheckedContinuation { c in RGFontStore.shared.importFont(url: url) { c.resume(returning: $0) } } }
 static func main() async throws {
  let store = RGFontStore.shared
  expect(!store.isDownloaded(prefix: "JetBrainsMono"), "Cold installation has no downloaded fonts")
  guard case .success = await download("JetBrainsMono") else { fatalError("Direct font download failed") }
  expect(store.isDownloaded(prefix: "JetBrainsMono"), "Complete family must be published")
  expect(store.progress == 1 && store.downloading == nil, "Completed download must reset operation state")
  guard case .failure = await download("Bad") else { fatalError("Corrupt download must fail") }
  expect(RGFontStore.cachedURL(filename: "Bad-Regular.ttf") == nil, "Corrupt fonts must never be published")
  guard case .failure = await download("Missing") else { fatalError("404 must fail") }
  guard case .success = await download("Inter") else { fatalError("Pinned archive extraction failed") }
  expect(store.isDownloaded(prefix: "Inter"), "All archive members must be validated")
  guard case .success = await download("GoogleSansCode"), let family = RGFontStore.additionalFamilies.first else { fatalError("Additional catalog family failed") }
  guard let roman = RGFontStore.importedURL(id: family.selectionId), let italic = RGFontStore.importedURL(id: family.selectionId, italic: true) else { fatalError("Selection ID must resolve downloaded faces") }
  expect(roman != italic, "Real italic face must remain separate from the upright font")
  expect(roman.lastPathComponent == family.regular && italic.lastPathComponent == family.italic, "Catalog metadata must select the correct face")
  var cancelledCallback = false
  store.download(prefix: "Slow") { _ in cancelledCallback = true }
  try await Task.sleep(nanoseconds: 100_000_000)
  store.cancel()
  try await Task.sleep(nanoseconds: 200_000_000)
  expect(store.downloading == nil && !store.isDownloaded(prefix: "Slow") && !cancelledCallback, "Cancellation must retain no partial cache or apply callback")
  guard case let .success(font) = await importFile(URL(fileURLWithPath: LATIN)) else { fatalError("Valid imported font must load") }
  expect(font.latin && !font.chinese && RGFontStore.importedURL(id: font.id) != nil, "Imported script coverage must be detected")
  guard case .success = await importFile(URL(fileURLWithPath: LATIN)) else { fatalError("Repeated import must succeed") }
  expect(store.imported.count == 1, "Duplicate imports must not duplicate library entries")
  guard case let .success(chinese) = await importFile(URL(fileURLWithPath: CHINESE)) else { fatalError("Chinese import failed") }
  expect(chinese.chinese, "CJK font must be available in Chinese choices")
  guard let url = RGFontStore.importedURL(id: chinese.id), let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], !descriptors.isEmpty else { fatalError("Copied font must remain parseable") }
  let invalid = URL(fileURLWithPath: INVALID)
  try Data("invalid font".utf8).write(to: invalid)
  guard case .failure = await importFile(invalid) else { fatalError("Invalid font must fail") }
  expect(store.imported.count == 2, "Invalid import must not modify font library")
  // Exercise the copied-file handoff used by the native import picker. System fonts stay local:
  // no Apple font data is added to the repository or to the application bundle.
  for source in [URL(fileURLWithPath: FONT_OTF_PATH), URL(fileURLWithPath: FONT_TTC_PATH)] {
   let copied = invalid.deletingLastPathComponent().appendingPathComponent(source.lastPathComponent)
   try FileManager.default.copyItem(at: source, to: copied)
   guard case let .success(imported) = await importFile(copied) else { fatalError("OTF/TTC copied-file import failed") }
   expect(imported.latin, "OTF/TTC first face must retain Latin coverage")
   try FileManager.default.removeItem(at: copied)
   guard let retained = RGFontStore.importedURL(id: imported.id), let faces = CTFontManagerCreateFontDescriptorsFromURL(retained as CFURL) as? [CTFontDescriptor], !faces.isEmpty else { fatalError("Font must survive picker-copy cleanup") }
   expect(faces.count == (CTFontManagerCreateFontDescriptorsFromURL(source as CFURL) as? [CTFontDescriptor])?.count, "TTC collection faces must survive storage")
  }
  let oversized = invalid.deletingLastPathComponent().appendingPathComponent("oversized.ttf")
  expect(FileManager.default.createFile(atPath: oversized.path, contents: Data()), "Size-limit fixture must be created")
  let handle = try FileHandle(forWritingTo: oversized)
  try handle.truncate(atOffset: 64 * 1024 * 1024 + 1)
  try handle.close()
  guard case let .failure(error) = await importFile(oversized), case RGFontStoreError.tooLarge = error else { fatalError("Oversized fonts must fail before parsing") }
  let collection = store.imported.filter { RGFontSelection(id: $0.id)?.faceIndex ?? 0 > 0 }
  expect(!collection.isEmpty, "TTC must expose multiple individually selectable faces")
  let face = collection[0]
  guard let selection = RGFontSelection(id: face.id), let retained = RGFontStore.importedURL(id: face.id) else { fatalError("Collection face must resolve shared file") }
  guard let retainedFaces = CTFontManagerCreateFontDescriptorsFromURL(retained as CFURL) as? [CTFontDescriptor] else { fatalError("Retained collection must expose its faces") }
  for entry in store.imported.filter({ RGFontSelection(id: $0.id)?.fileId == selection.fileId }) {
   guard let index = RGFontSelection(id: entry.id)?.faceIndex, retainedFaces.indices.contains(index) else { fatalError("Stored face index must resolve a real descriptor") }
   expect((CTFontDescriptorCopyAttribute(retainedFaces[index], kCTFontDisplayNameAttribute) as? String) == entry.title, "Data and retained-file descriptors must keep the same face ordering")
  }
  let countBefore = store.imported.count
  try store.rename(id: face.id, title: "  My TTC face  ")
  expect(store.imported.first(where: { $0.id == face.id })?.title == "My TTC face", "Rename must trim and update metadata")
  RGSimpleSettings.shared.fontImportedLatin = face.id
  try store.remove(id: face.id)
  expect(store.imported.count == countBefore - 1 && FileManager.default.fileExists(atPath: retained.path), "Removing one face must retain the shared TTC for other faces")
  expect(RGSimpleSettings.shared.fontImportedLatin.isEmpty, "Removing selected face must reset selection")
  for font in store.imported.filter({ RGFontSelection(id: $0.id)?.fileId == selection.fileId }) { try store.remove(id: font.id) }
  expect(!FileManager.default.fileExists(atPath: retained.path), "Removing final face must reclaim collection bytes")
  expect(store.storageBytes(downloads: false) > 0 && store.storageBytes(downloads: true) > 0, "Storage totals must include retained files")
  try store.clearDownloads()
  expect(store.storageBytes(downloads: true) == 0 && !store.isDownloaded(prefix: "Inter"), "Clear downloads must reclaim cloud fonts")
  expect(!store.imported.isEmpty && store.storageBytes(downloads: false) > 0, "Clear downloads must preserve user imports")
  for font in store.imported { try store.remove(id: font.id) }
  expect(store.imported.isEmpty && store.storageBytes(downloads: false) == 0, "Removing all imports must reclaim every file")
  print("Font store checks passed: downloads, integrity, cancellation, TTF/OTF/TTC, every collection face, duplicates, rename, selection reset, shared-file deletion and storage reclamation")
 }
}
'''.replace('import Foundation','import Foundation\nimport CoreText',1).replace('BUNDLE',json.dumps(str(bundle))).replace('LATIN',json.dumps(str(root/'Regram/RGTypography/Fonts/JetBrainsMono-Regular.ttf'))).replace('CHINESE',json.dumps(str(root/'Regram/RGTypography/Fonts/IBMPlexSansSC-Regular.ttf'))).replace('INVALID',json.dumps(str(work/'invalid.ttf'))).replace('FONT_OTF_PATH',json.dumps('/System/Library/Fonts/Supplemental/STIXGeneral.otf')).replace('FONT_TTC_PATH',json.dumps('/System/Library/Fonts/Helvetica.ttc')))
args=[swift,'-swift-version','5','-sdk',sdk,'-Xcc','-fmodule-map-file='+str(work/'module.modulemap'),'-Xcc','-I'+str(root/'third-party/ZipArchive/PublicHeaders'),str(root/'Regram/RGSimpleSettings/Sources/FontSettings.swift'),str(work/'Store.swift'),str(work/'Tests.swift')]+[str(o) for o in objects]+['-lz','-liconv','-framework','Foundation','-o',str(work/'tests')]
with (task/'store-checks-build.log').open('w') as log:result=subprocess.run(args,stdout=log,stderr=subprocess.STDOUT)
if result.returncode:
 print((task/'store-checks-build.log').read_text());raise RuntimeError('Store harness compile failed')
try:
 result=subprocess.run([str(work/'tests')],capture_output=True,timeout=60)
 (task/'store-checks.log').write_bytes(result.stdout+result.stderr)
 print(result.stdout.decode())
 if result.returncode:print(result.stderr.decode());raise RuntimeError('Store runtime checks failed')
finally:
 server.shutdown()
 server.server_close()
 temporary.cleanup()
