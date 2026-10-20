"""Reference microservice that implements the Symphony service contract.

It exposes /health, /logs and /traces (see docs/SERVICE_CONTRACT.md), calls its
configured dependencies on a timer so that real request traces exist, and
reports itself down when a dependency it needs is unavailable. It uses only the
Python standard library.
"""
import json
import os
import threading
import time
import urllib.error
import urllib.request
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NAME = os.environ.get("SERVICE_NAME", "service")
PORT = int(os.environ.get("PORT", "8000"))
TRAFFIC_INTERVAL = float(os.environ.get("TRAFFIC_INTERVAL_SECONDS", "2"))
DEPENDENCY_TIMEOUT = float(os.environ.get("DEPENDENCY_TIMEOUT_SECONDS", "1.5"))
RETENTION = int(os.environ.get("RETENTION", "100"))
ADMIN_ENABLED = os.environ.get("ADMIN_ENABLED", "true").lower() == "true"
VALID_STATES = ("healthy", "degraded", "down")


def parse_dependencies(raw: str) -> dict:
    """Parse 'id=http://host:port,id=http://host:port' into a dict."""
    found = {}
    for part in raw.split(","):
        part = part.strip()
        if not part:
            continue
        name, _, url = part.partition("=")
        if name and url:
            found[name.strip()] = url.strip().rstrip("/")
    return found


DEPENDENCIES = parse_dependencies(os.environ.get("DEPENDS_ON", ""))

lock = threading.Lock()
logs = deque(maxlen=RETENTION)
traces = deque(maxlen=RETENTION)
dependency_status: dict = {}
forced_state = None


def log(level: str, message: str) -> None:
    with lock:
        logs.append({"level": level, "message": message, "time": time.time()})


def call_dependency(target: str, base_url: str) -> int:
    """Call a dependency's /work endpoint and record the outcome as a trace."""
    try:
        with urllib.request.urlopen(base_url + "/work", timeout=DEPENDENCY_TIMEOUT) as reply:
            code = reply.getcode()
    except urllib.error.HTTPError as err:
        code = err.code
    except TimeoutError:
        code = 504
    except urllib.error.URLError as err:
        code = 504 if isinstance(err.reason, TimeoutError) else 503
    except OSError:
        code = 503
    with lock:
        traces.append({"target_id": target, "status_code": code, "time": time.time()})
        previous = dependency_status.get(target)
        dependency_status[target] = code
    if code >= 400:
        log("ERROR", f"request to {target} failed with HTTP {code}")
    elif previous is not None and previous >= 400:
        log("INFO", f"request to {target} recovered")
    return code


def current_state() -> str:
    with lock:
        if forced_state:
            return forced_state
        failed = [name for name, code in dependency_status.items() if code >= 400]
    return "down" if failed else "healthy"


def do_work() -> int:
    """Handle one unit of work; return the HTTP status this service answers with."""
    if forced_state == "down":
        return 503
    for target, url in DEPENDENCIES.items():
        call_dependency(target, url)
    return 503 if current_state() == "down" else 200


def traffic_loop() -> None:
    while True:
        try:
            do_work()
        except Exception as err:  # keep the loop alive whatever happens
            log("ERROR", f"traffic loop error: {err}")
        time.sleep(TRAFFIC_INTERVAL)


class Handler(BaseHTTPRequestHandler):
    def reply(self, code: int, body: dict) -> None:
        payload = json.dumps(body).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        try:
            self.wfile.write(payload)
        except ConnectionError:
            pass  # the caller timed out and went away

    def do_GET(self) -> None:
        path = self.path.split("?", 1)[0]
        if path == "/health":
            state = current_state()
            message = f"{NAME} is {state}"
            if state == "down" and not forced_state:
                with lock:
                    failed = sorted(n for n, c in dependency_status.items() if c >= 400)
                message = f"{NAME} cannot reach: {', '.join(failed)}"
            self.reply(503 if state == "down" else 200,
                       {"service": NAME, "state": state, "message": message})
        elif path == "/logs":
            with lock:
                entries = list(logs)
            self.reply(200, {"service": NAME, "entries": entries})
        elif path == "/traces":
            with lock:
                requests = list(traces)
            self.reply(200, {"service": NAME, "requests": requests})
        elif path == "/work":
            code = do_work()
            self.reply(code, {"service": NAME, "ok": code == 200})
        else:
            self.reply(404, {"error": "not found"})

    def do_POST(self) -> None:
        global forced_state
        path = self.path.split("?", 1)[0]
        if path != "/admin/state" or not ADMIN_ENABLED:
            self.reply(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            state = json.loads(self.rfile.read(length) or b"{}").get("state")
        except (ValueError, json.JSONDecodeError):
            state = None
        if state not in VALID_STATES:
            self.reply(400, {"error": "state must be healthy, degraded or down"})
            return
        with lock:
            forced_state = None if state == "healthy" else state
        log("WARN", f"operator set state to {state}")
        self.reply(200, {"service": NAME, "state": current_state()})

    def log_message(self, format: str, *args) -> None:  # silence per-request stderr noise
        return


if __name__ == "__main__":
    log("INFO", f"{NAME} started; dependencies: {', '.join(DEPENDENCIES) or 'none'}")
    threading.Thread(target=traffic_loop, daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
