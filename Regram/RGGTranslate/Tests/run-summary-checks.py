"""Exercise production LLM requests against a local fixture server; no external endpoint or account."""
from pathlib import Path
import http.server,json,subprocess,tempfile,threading
root=Path(__file__).resolve().parents[3]
requests=[]
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_POST(self):
  body=json.loads(self.rfile.read(int(self.headers['Content-Length'])));requests.append((self.path,body,dict(self.headers)))
  if self.path=='/failure': payload={'error':{'message':'key SYNTHETIC-SECRET denied'}};status=401
  elif self.path=='/anthropic':payload={'content':[{'type':'text','text':'brief summary'}]};status=200
  else:payload={'choices':[{'message':{'content':'brief summary'}}]};status=200
  data=json.dumps(payload).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);threading.Thread(target=server.serve_forever,daemon=True).start()
try:
 with tempfile.TemporaryDirectory(prefix='regram-summary-checks-') as directory:
  work=Path(directory)
  sources=sorted((root/'submodules/SSignalKit/SwiftSignalKit/Source').glob('*.swift'))
  subprocess.run(['xcrun','swiftc','-swift-version','5','-emit-library','-emit-module','-module-name','SwiftSignalKit']+[str(p) for p in sources]+['-emit-module-path',str(work/'SwiftSignalKit.swiftmodule'),'-o',str(work/'libSwiftSignalKit.dylib')],check=True,capture_output=True)
  (work/'Adapters.swift').write_text('''import SwiftSignalKit
public enum TranslateFetchError: Error { case network }
public func getGTranslateLang(_ code: String) -> String { code }
public func rgTranslateInChunks(_ text: String, _ language: String, maxLength: Int, chunkTimeout: Double, _ f: @escaping (String, String) -> Signal<String, TranslateFetchError>) -> Signal<String, TranslateFetchError> { fatalError("Summaries must not use translation chunking") }
''')
  (work/'Tests.swift').write_text('''import Foundation
import SwiftSignalKit
@main enum Tests { static func main() {
 let base="http://127.0.0.1:" + CommandLine.arguments[1]
 func config(_ format: RGLLMAPIFormat, _ endpoint: String) -> RGLLMTranslationConfiguration { RGLLMTranslationConfiguration(format:format,baseURL:base,endpoint:endpoint,apiKey:"SYNTHETIC-SECRET",model:"independent-summary-model",prompt:"Summarize in @toLang: @text",temperature:0.3) }
 for (format,endpoint) in [(RGLLMAPIFormat.openai,"/openai"),(.anthropic,"/anthropic")] {
  let finished=DispatchSemaphore(value:0);var value=""
  let d=llmSummarize("selected first\\n---\\nselected second",language:"en",configuration:config(format,endpoint)).start(next:{value=$0},error:{fatalError($0.message)},completed:{finished.signal()})
  precondition(finished.wait(timeout:.now()+10) == .success && value=="brief summary");d.dispose()
 }
 let oversized=DispatchSemaphore(value:0)
 let bad=llmSummarize(String(repeating:"x",count:64001),language:"en",configuration:config(.openai,"/openai")).start(error:{_ in oversized.signal()})
 precondition(oversized.wait(timeout:.now()+1) == .success);bad.dispose()
 let failed=DispatchSemaphore(value:0);var message=""
 let failure=llmSummarize("selected",language:"en",configuration:config(.openai,"/failure")).start(error:{message=$0.message;failed.signal()})
 precondition(failed.wait(timeout:.now()+10) == .success && !message.contains("SYNTHETIC-SECRET") && message.contains("401"));failure.dispose()
 print("Production summaries: OpenAI/Anthropic response parsing, bounded input, separate model/prompt and redacted errors passed.")
} }
''')
  subprocess.run(['xcrun','swiftc','-swift-version','5','-I',str(work),'-L',str(work),'-lSwiftSignalKit','-Xlinker','-rpath','-Xlinker',str(work),str(root/'Regram/RGGTranslate/Sources/RGLLMTranslate.swift'),str(work/'Adapters.swift'),str(work/'Tests.swift'),'-o',str(work/'tests')],check=True)
  subprocess.run([str(work/'tests'),str(server.server_port)],check=True)
  assert len(requests)==3
  for path,body,headers in requests:
   assert body['model']=='independent-summary-model' and body['temperature']==0.3
   assert 'SYNTHETIC-SECRET' not in json.dumps(body)
   if path!='/failure':assert 'selected first' in json.dumps(body) and 'selected second' in json.dumps(body)
   if path=='/anthropic':assert headers.get('x-api-key')=='SYNTHETIC-SECRET' and body['max_tokens']==4096
  print('Fixture server verified exactly selected text, authentication format, no key in prompt/body, and no request for oversized input.')
finally:server.shutdown();server.server_close()
