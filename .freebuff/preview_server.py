"""Live game-view server for the Freebuff Preview tab.

Serves a single page that shows the newest screenshot from
.fennara/state/captures/ and refreshes automatically while a Fennara
desktop session saves new frames.

Usage:  python .freebuff/preview_server.py [port]   (default 8765)
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAPTURES = os.path.join(ROOT, ".fennara", "state", "captures")
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765

PAGE = """<!doctype html>
<html><head><meta charset="utf-8">
<title>Shadow Avenger - live game view</title>
<style>
  body { margin:0; background:#0b0d1a; color:#cfd3ea; font:14px system-ui,sans-serif;
         display:flex; flex-direction:column; height:100vh; }
  header { padding:8px 14px; display:flex; gap:12px; align-items:baseline; }
  header b { color:#ffd76a; }
  #st { font-size:12px; opacity:.75; }
  img { flex:1; min-height:0; object-fit:contain; background:#000; }
</style></head>
<body>
<header><b>Shadow Avenger</b><span>live desktop session</span><span id="st">connecting...</span></header>
<img id="shot" alt="game capture">
<script>
  let current = "";
  async function tick() {
    try {
      const r = await fetch("/latest", {cache: "no-store"});
      const j = await r.json();
      document.getElementById("st").textContent =
        j.file ? (j.file + "  -  " + new Date(j.mtime).toLocaleTimeString()) : "no captures yet";
      if (j.file && j.file !== current) {
        current = j.file;
        document.getElementById("shot").src = "/img?cb=" + Date.now();
      }
    } catch (e) {
      document.getElementById("st").textContent = "server offline";
    }
  }
  setInterval(tick, 2000);
  tick();
</script></body></html>"""


def newest_capture():
    try:
        files = [f for f in os.listdir(CAPTURES) if f.lower().endswith(".png")]
    except OSError:
        return None
    if not files:
        return None
    return max(files, key=lambda f: os.path.getmtime(os.path.join(CAPTURES, f)))


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="text/plain"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/latest"):
            f = newest_capture()
            mtime = os.path.getmtime(os.path.join(CAPTURES, f)) * 1000 if f else 0
            self._send(200, json.dumps({"file": f or "", "mtime": mtime}).encode(),
                       "application/json")
        elif self.path.startswith("/img"):
            f = newest_capture()
            if not f:
                self._send(404, b"no captures")
                return
            with open(os.path.join(CAPTURES, f), "rb") as fh:
                self._send(200, fh.read(), "image/png")
        else:
            self._send(200, PAGE.encode(), "text/html; charset=utf-8")

    def log_message(self, *a):  # keep the log quiet
        pass


if __name__ == "__main__":
    print("live view on http://127.0.0.1:%d (captures: %s)" % (PORT, CAPTURES), flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
