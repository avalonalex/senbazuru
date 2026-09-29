"""Static server rooted at the scratchpad plus POST /save?name=X.png, which
writes the request body into experiments/X1-render/three/out/. Local only."""
import http.server, os, sys, urllib.parse
ROOT = sys.argv[1]; OUT = os.path.join(ROOT, 'experiments/X1-render/three/out')
os.makedirs(OUT, exist_ok=True)
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k): super().__init__(*a, directory=ROOT, **k)
    def do_POST(self):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        name = os.path.basename(q.get('name', ['out.png'])[0])
        data = self.rfile.read(int(self.headers['Content-Length']))
        open(os.path.join(OUT, name), 'wb').write(data)
        self.send_response(200); self.end_headers(); self.wfile.write(b'ok')
http.server.ThreadingHTTPServer(('127.0.0.1', int(sys.argv[2])), H).serve_forever()
