#!/usr/bin/env python3
"""
Minimal REFERENCE update server for the AstraClient updater (modules/updater/updater.lua).
For local testing of the full update loop -- NOT a production server.

It does two things:
  1. POST <any path>            -> returns the manifest JSON (update.json) verbatim.
                                   The client posts {version, build, os, platform, args};
                                   we ignore the body and return the manifest.
  2. GET  <url path>/<file>     -> serves the release files so the client can download
                                   manifest["url"] + "<file path>".

Setup:
  1. Package data.zip + build the exe.
  2. python gen_update_manifest.py data.zip --url http://127.0.0.1:8088/files/ \
         --binary AstraClient_dx_x64.exe -o update.json
  3. Put the files to serve under a folder (default ./release) at the SAME relative paths
     the manifest keys use (e.g. ./release/init.lua, ./release/modules/...). For a
     data.zip-based manifest, unzip data.zip into ./release so the paths line up.
  4. python update_server_reference.py --manifest update.json --root ./release --port 8088
  5. In config.lua: Services.updater = "http://127.0.0.1:8088/api/update"
     (and run a data.zip build so isLoadedFromArchive is true -> updater activates).

The production backend just has to honor the same contract (see docs/DISTRIBUICAO_E_UPDATER.md).
"""
import argparse
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, unquote

MANIFEST_PATH = "update.json"
ROOT_DIR = "release"


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body=b"", ctype="application/octet-stream"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_POST(self):
        # Drain the request body (the client sends a small JSON) and return the manifest.
        length = int(self.headers.get("Content-Length", 0) or 0)
        if length:
            self.rfile.read(length)
        try:
            with open(MANIFEST_PATH, "rb") as f:
                body = f.read()
        except OSError as e:
            self._send(500, json.dumps({"error": f"manifest unreadable: {e}"}).encode(), "application/json")
            return
        self._send(200, body, "application/json")

    def do_GET(self):
        # Serve files from ROOT_DIR. The manifest keys start with "/", and url is e.g.
        # ".../files/", so the client requests ".../files//init.lua" -> normalize.
        path = unquote(urlsplit(self.path).path)
        # strip any leading url prefix up to the last "files/" if present
        marker = "files/"
        if marker in path:
            path = path.split(marker, 1)[1]
        rel = path.lstrip("/")
        full = os.path.normpath(os.path.join(ROOT_DIR, rel))
        if not full.startswith(os.path.abspath(ROOT_DIR)) and not os.path.abspath(full).startswith(os.path.abspath(ROOT_DIR)):
            self._send(403)
            return
        if not os.path.isfile(full):
            self._send(404, f"not found: {rel}".encode())
            return
        with open(full, "rb") as f:
            self._send(200, f.read())

    def log_message(self, fmt, *args):
        print("[update-server]", self.address_string(), fmt % args)


def main():
    global MANIFEST_PATH, ROOT_DIR
    ap = argparse.ArgumentParser(description="Reference update server for local testing.")
    ap.add_argument("--manifest", default="update.json", help="manifest JSON to return on POST")
    ap.add_argument("--root", default="release", help="folder with the files to serve on GET")
    ap.add_argument("--port", type=int, default=8088)
    args = ap.parse_args()
    MANIFEST_PATH = args.manifest
    ROOT_DIR = os.path.abspath(args.root)
    print(f"manifest={MANIFEST_PATH}  root={ROOT_DIR}  http://127.0.0.1:{args.port}")
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
