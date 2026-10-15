#!/usr/bin/env python3
"""Serve o build Godot por HTTP; sem dependências além do Python 3."""

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class GodotHandler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "text/javascript; charset=utf-8",
    }

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8060)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--directory", type=Path, default=Path(__file__).resolve().parents[1] / "build" / "web")
    args = parser.parse_args()
    directory = args.directory.resolve()
    if not (directory / "index.html").is_file():
        parser.error(f"Build não encontrado em {directory}. Exporte para build/web/index.html primeiro.")
    handler = partial(GodotHandler, directory=str(directory))
    with ThreadingHTTPServer((args.host, args.port), handler) as server:
        print(f"Porto Lume: http://localhost:{args.port}", flush=True)
        print(f"No iPhone, use http://IP-LOCAL-DO-COMPUTADOR:{args.port} na mesma rede Wi-Fi.", flush=True)
        print("Ctrl+C para encerrar.", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()

