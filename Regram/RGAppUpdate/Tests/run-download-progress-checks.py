#!/usr/bin/env python3
"""Exercise the production download delegate against a local, throttled HTTP server."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[3]
SOURCES = ROOT / 'Regram/RGAppUpdate'
SIZE = 3 * 1024 * 1024


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        self.send_response(503 if self.path == '/error' else 302 if self.path == '/redirect' else 200)
        if self.path == '/redirect':
            self.send_header('Location', '/file')
        if self.path != '/unknown-size':
            self.send_header('Content-Length', str(16 if self.path == '/error' else 0 if self.path == '/redirect' else SIZE))
        self.end_headers()
        try:
            if self.path == '/error':
                self.wfile.write(b'R' * 16)
            elif self.path != '/redirect':
                for _ in range(SIZE // 65536):
                    self.wfile.write(b'R' * 65536)
                    self.wfile.flush()
                    time.sleep(0.02)
        except (BrokenPipeError, ConnectionResetError):
            pass


server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    with tempfile.TemporaryDirectory(prefix='regram-download-checks-') as temporary:
        binary = Path(temporary) / 'download-checks'
        subprocess.run(['xcrun', 'swiftc', '-warnings-as-errors', '-parse-as-library',
                        str(SOURCES / 'Sources/RGUpdateRelease.swift'),
                        str(SOURCES / 'Sources/RGUpdateDownload.swift'),
                        str(SOURCES / 'Tests/DownloadProgressTests.swift'), '-o', str(binary)], check=True)
        subprocess.run([str(binary), f'http://127.0.0.1:{server.server_port}', temporary], check=True, timeout=45)
finally:
    server.shutdown()
    server.server_close()
