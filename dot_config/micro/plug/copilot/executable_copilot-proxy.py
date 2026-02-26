#!/usr/bin/env python3
"""Bridge between micro (file-based requests) and copilot-language-server.

Transport layer only:
  - Inbound:  watch .req file → forward Content-Length frames to LSP stdin
  - Outbound: read Content-Length frames from LSP stdout → emit JSONL to our stdout
"""

import os
import select
import signal
import subprocess
import sys
import shutil
import tempfile
import threading
import time

proc = None
PARENT_PID = os.getppid()


def find_server():
    custom = os.environ.get("COPILOT_LS")
    if custom:
        return custom
    path = shutil.which("copilot-language-server")
    if path:
        return path
    sys.exit(1)


def write_all(fd, data):
    mv = memoryview(data)
    pos = 0
    while pos < len(data):
        pos += os.write(fd, mv[pos:])


def parent_alive():
    return os.getppid() == PARENT_PID


def response_reader(stdout_fd):
    """Content-Length framed stream → JSONL (one JSON body per line)."""
    buf = b""
    while True:
        ready, _, _ = select.select([stdout_fd], [], [], 2.0)
        if not ready:
            if not parent_alive():
                return
            continue
        try:
            chunk = os.read(stdout_fd, 65536)
        except OSError:
            return
        if not chunk:
            return
        buf += chunk
        while True:
            sep = buf.find(b"\r\n\r\n")
            if sep == -1:
                break
            cl = 0
            for h in buf[:sep].split(b"\r\n"):
                if h.lower().startswith(b"content-length:"):
                    cl = int(h.split(b":", 1)[1].strip())
            end = sep + 4 + cl
            if len(buf) < end:
                break
            write_all(1, buf[sep + 4 : end] + b"\n")
            buf = buf[end:]


def request_watcher(req_path, stdin_fd):
    """Poll .req file for new data and forward to LSP stdin."""
    pos = 0
    while True:
        if proc and proc.poll() is not None:
            return
        if not parent_alive():
            os.kill(os.getpid(), signal.SIGTERM)
            return
        try:
            size = os.path.getsize(req_path)
        except OSError:
            time.sleep(0.05)
            continue
        if size > pos:
            with open(req_path, "rb") as f:
                f.seek(pos)
                data = f.read()
                if data:
                    try:
                        write_all(stdin_fd, data)
                    except OSError:
                        return
                    pos += len(data)
        time.sleep(0.02)


def main():
    global proc
    server_bin = find_server()
    req_path = os.path.join(tempfile.gettempdir(), f"micro-copilot-{os.getpid()}.req")
    open(req_path, "wb").close()

    lsp_in_r, lsp_in_w = os.pipe()
    lsp_out_r, lsp_out_w = os.pipe()

    proc = subprocess.Popen(
        [server_bin, "--stdio"],
        stdin=lsp_in_r,
        stdout=lsp_out_w,
        stderr=sys.stderr,
    )
    os.close(lsp_in_r)
    os.close(lsp_out_w)

    def shutdown(*_):
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        for fd in (lsp_in_w, lsp_out_r):
            try:
                os.close(fd)
            except OSError:
                pass
        try:
            os.unlink(req_path)
        except OSError:
            pass
        os._exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    write_all(1, f"REQ:{req_path}\n".encode())

    threading.Thread(
        target=request_watcher, args=(req_path, lsp_in_w), daemon=True
    ).start()

    try:
        response_reader(lsp_out_r)
    except (BrokenPipeError, KeyboardInterrupt):
        pass
    finally:
        shutdown()


if __name__ == "__main__":
    main()
