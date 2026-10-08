#!/usr/bin/env python3
"""
Deliberately minimal — stdlib only, no dependencies — so deployment
mechanics (start, stop, health-check, rollback) can be tested against a
real running process and real HTTP responses, without needing to install
anything. This stands in for "the application" in a deployment pipeline
demo; the pipeline is the point, not this app.

Reads its own version from VERSION (a file written into this release's
directory at deploy time — see scripts/deploy.sh). If a file named
BROKEN exists alongside it, /health deliberately returns 500 — this is
how the test suite (scripts/run_test_suite.sh) exercises the rollback
path for real, rather than only testing the happy path.
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def read_version() -> str:
    version_file = os.path.join(SCRIPT_DIR, "VERSION")
    if os.path.exists(version_file):
        with open(version_file) as f:
            return f.read().strip()
    return "unknown"


def is_broken() -> bool:
    return os.path.exists(os.path.join(SCRIPT_DIR, "BROKEN"))


class HealthHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # keep test-suite output readable; deploy.sh captures what it needs separately

    def do_GET(self):
        if self.path != "/health":
            self.send_response(404)
            self.end_headers()
            return

        if is_broken():
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "error", "version": read_version()}).encode())
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"status": "ok", "version": read_version()}).encode())


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    server = HTTPServer(("127.0.0.1", port), HealthHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
