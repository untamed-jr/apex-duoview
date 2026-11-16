#!/usr/bin/env python3
"""
timing_recorder.py - THROWAWAY SPIKE. Not part of the app.

What it is
    Records a whole live F1 session's raw live-timing messages to a file on your Mac, so app
    developers can replay it later as test data. It connects to F1's live timing the way the
    Android app does (LiveFeed.kt): POST negotiate, then a SignalR Core JSON WebSocket at
    livetiming.formula1.com/signalrcore, handshake, Subscribe to the same 13 topics, and keeps
    every message it receives. The WebSocket client is built in here (standard library only).

    It only READS public timing data with your F1 TV sign-in. No video, no licence requests.

How to run (on the Mac, with your own F1 TV subscription; Python 3.9+, standard library only)
    1. Sign in at https://account.formula1.com in a browser and copy the value of the
       `login-session` cookie (a bare subscription token also works), exactly as for
       stream_check.py.
    2. Start it a few minutes before the session and leave the window open:
           pbpaste | python3 timing_recorder.py
       (or just  python3 timing_recorder.py  and paste at the hidden prompt, if the cookie is short
       enough for the terminal.) Press Ctrl+C when the session is over.
    3. The recording is  timing_<YYYYmmdd-HHMM>.jsonl  next to this script (local time of the Mac
       at start). One JSON line per received message:  {"t": "<UTC time with ms>", "msg": <message>}.
       It contains NO sign-in details, but it is large (tens to hundreds of MB for a race), so
       do not paste it into chat; put it somewhere the developers can fetch it.

    Lines of the form {"t": ..., "recorder": "reconnect", ...} are written by this tool when the
    connection dropped and came back, so a gap in the data is visible. They have no "msg" key.

Replay data from a finished session (the same files the Android app reads for replays):
        pbpaste | python3 timing_recorder.py --archive 2026/2026-11-08_São_Paulo_Grand_Prix/2026-11-08_Race/
    downloads that session's static archive topics into a folder  archive_<session>/  next to this
    script. Also needs the sign-in (the archive wants the same token as a Bearer header).

Fixtures for the iOS app's beta.3 (owner check T-A; one run, about 10 minutes):
    1. Copy the login-session cookie exactly as in step 1 above (sign in at account.formula1.com,
       copy the cookie's value so it is on the clipboard).
    2. In Terminal, run these two lines:
           cd ~/apexview-duo && git pull
           pbpaste | python3 spike/timing_recorder.py --fixtures
    3. It fetches, for the São Paulo Grand Prix 2026: the year's Index.json; the Race and
       Qualifying archive files (and Sprint / Sprint Qualifying if the weekend had them), with
       WeatherData where F1 has it; for each session a check of the car-data file
       (CarData.z.jsonStream) that records its size and whether F1 serves it in byte ranges and
       keeps only its first 1 MB; and the Interlagos circuit file from MultiViewer (sent without
       your sign-in). It prints one ok / failed line per step and then the path and size of
       ONE file:
           ~/apexview-duo/spike/beta3-fixtures.zip
    4. Upload that zip (only that file) for the developers. It holds public timing data only:
       the script checks the finished zip for your sign-in and deletes it if it were ever there.
       If a step says failed, upload the zip anyway; fixtures-summary.json inside says what happened.
       If no zip is made, the message says why (usually: sign in again and copy a fresh cookie).

Circuit file only (no sign-in needed):
        python3 timing_recorder.py --circuit 14 2026
    saves MultiViewer's circuit file as  circuit-14-2026.json  next to this script (14 is Interlagos).
"""

import argparse
import base64
import getpass
import hashlib
import http.client
import json
import os
import re
import shutil
import socket
import ssl
import struct
import sys
import time
import unicodedata
import urllib.parse
import zipfile
from datetime import datetime, timezone

# --- Mirrors of LiveFeed.kt / LiveTiming.kt --------------------------------------------------

HUB = "https://livetiming.formula1.com/signalrcore"
ARCHIVE_BASE = "https://livetiming.formula1.com/static/"
# LiveTiming.kt fetchCircuit(): MultiViewer's public circuit data, fetched WITHOUT the F1 token.
CIRCUITS_BASE = "https://api.multiviewer.app/api/v1/circuits/"
RS = "\x1e"
HANDSHAKE = '{"protocol":"json","version":1}'
TOPICS = [
    "Heartbeat", "Position.z", "CarData.z", "TimingData", "DriverList", "SessionInfo", "SessionStatus",
    "RaceControlMessages", "TeamRadio", "TimingAppData", "TrackStatus", "LapCount", "ExtrapolatedClock",
]
# The Android app's WebView user agent ("; wv" removed); a representative value, as in stream_check.py.
ANDROID_UA = ("Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/AP2A.240805.005) AppleWebKit/537.36 "
              "(KHTML, like Gecko) Version/4.0 Chrome/140.0.7339.207 Mobile Safari/537.36")

PING_INTERVAL_S = 15        # LiveFeed.kt: OkHttp pingInterval(15 s)
IDLE_LIMIT_S = 60           # no frame at all for this long: the connection is dead
STATUS_INTERVAL_S = 30
MAX_RECONNECTS = 5
HEALTHY_AFTER_S = 120       # a connection that lasted this long resets the reconnect count

# Archive files the Android app reads for a replay (LiveTiming.kt load()/loadSpeeds()), one per live topic.
ARCHIVE_FILES = [
    "SessionInfo.json", "DriverList.json", "Heartbeat.jsonStream", "Position.z.jsonStream",
    "CarData.z.jsonStream", "TimingData.jsonStream", "TimingAppData.jsonStream",
    "SessionStatus.jsonStream", "RaceControlMessages.jsonStream", "TrackStatus.jsonStream",
    "TeamRadio.jsonStream", "LapCount.jsonStream", "ExtrapolatedClock.jsonStream",
]

# --- Sign-in (same as stream_check.py / LoginCookie.readToken()) -----------------------------

SECRETS = []  # exact strings never to print or write


def add_secret(value):
    if value and len(value) >= 6 and value not in SECRETS:
        SECRETS.append(value)
        enc = urllib.parse.quote(value, safe="")
        if enc != value:
            SECRETS.append(enc)


def scrub(text):
    text = str(text)
    for s in SECRETS:
        text = text.replace(s, "<masked>")
    return re.sub(r"eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]*", "<masked-jwt>", text)


def say(line=""):
    print(scrub(line), flush=True)


def decode_signin(raw):
    """Returns (subscription_token, kind). Cookie (JSON, raw or URL-encoded) or a bare token."""
    value = raw.strip().strip('"').strip("'").strip()
    if value.lower().startswith("login-session="):
        value = value.split("=", 1)[1].strip()
    candidates = [value]
    decoded = value
    for _ in range(2):
        nxt = urllib.parse.unquote(decoded)
        if nxt == decoded:
            break
        decoded = nxt
        candidates.append(decoded)
    looks_like_cookie = any(c.lstrip().startswith("{") for c in candidates)
    for kind, c in zip(["cookie (raw JSON)", "cookie (URL-encoded JSON)", "cookie (double URL-encoded JSON)"],
                       candidates):
        try:
            obj = json.loads(c)
        except ValueError:
            continue
        data = obj.get("data") if isinstance(obj, dict) else None
        token = data.get("subscriptionToken") if isinstance(data, dict) else None
        if isinstance(token, str) and token:
            return token, kind
    if looks_like_cookie:
        raise ValueError("That looks like the login-session cookie but has no data.subscriptionToken. "
                         "Sign in again at account.formula1.com and copy the cookie afresh.")
    if not value or re.search(r"\s", value):
        raise ValueError("That doesn't look like a login-session cookie or a subscription token.")
    return value, "bare subscription token"


def read_signin(command="pbpaste | python3 timing_recorder.py"):
    if not sys.stdin.isatty():
        raw = sys.stdin.read()
    else:
        print("Paste your F1 TV login-session cookie value (or a bare subscription token).")
        print("Input is hidden and is not stored or printed.")
        print("(If the terminal beeps or flashes, the value is too long to paste: press Ctrl+C,")
        print(" copy the cookie, and run:  %s)" % command)
        raw = getpass.getpass("login-session / token: ")
    token, kind = decode_signin(raw)
    add_secret(token)
    add_secret(raw.strip())
    return token, kind


# --- HTTP (http.client: exact headers, no redirects, no cookies jar) -------------------------

class FatalError(Exception):
    """Not worth retrying (refused login, bad path)."""


def https_request(method, url, headers):
    """Returns (connection, response); the caller reads the body and closes the connection."""
    p = urllib.parse.urlsplit(url)
    ctx = ssl.create_default_context()
    if p.scheme == "https":
        conn = http.client.HTTPSConnection(p.hostname, p.port or 443, timeout=20, context=ctx)
    else:  # plain http: only used against a local test server
        conn = http.client.HTTPConnection(p.hostname, p.port or 80, timeout=20)
    target = p.path + ("?" + p.query if p.query else "")
    try:
        conn.request(method, target, headers=headers)
        return conn, conn.getresponse()
    except ssl.SSLError as e:
        conn.close()
        if "CERTIFICATE_VERIFY_FAILED" in str(e):
            raise ConnectionError("TLS certificate check failed. If this is a python.org Python, run "
                                  "'Install Certificates.command' from its Applications folder, or use /usr/bin/python3.")
        raise ConnectionError("TLS error: %s" % e)
    except (OSError, http.client.HTTPException) as e:
        conn.close()
        raise ConnectionError("Network error: %s" % e)


def negotiate(token, ua):
    """POST $HUB/negotiate?negotiateVersion=1 as LiveFeed.negotiate(): Bearer header, no body.
    Returns (connection token, Cookie header value or None). The connection token is never printed."""
    conn, resp = https_request("POST", HUB + "/negotiate?negotiateVersion=1",
                               {"Authorization": "Bearer " + token, "User-Agent": ua})
    try:
        body = resp.read().decode("utf-8", errors="replace")
        if resp.status in (401, 403):
            raise FatalError("F1's live timing refused the login (HTTP %d). Sign in again and copy a fresh cookie." % resp.status)
        if not 200 <= resp.status < 300:
            raise ConnectionError("negotiate HTTP %d" % resp.status)
        try:
            j = json.loads(body)
        except ValueError:
            raise ConnectionError("negotiate returned something that isn't JSON")
        ident = (j.get("connectionToken") or j.get("connectionId") or "") if isinstance(j, dict) else ""
        if not ident:
            raise ConnectionError("no connection token in the negotiate response")
        add_secret(ident)
        cookies = "; ".join(v.split(";", 1)[0] for k, v in resp.getheaders() if k.lower() == "set-cookie")
        return ident, (cookies or None)
    finally:
        conn.close()


# --- Minimal RFC 6455 WebSocket client ------------------------------------------------------

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
OP_CONT, OP_TEXT, OP_BINARY, OP_CLOSE, OP_PING, OP_PONG = 0x0, 0x1, 0x2, 0x8, 0x9, 0xA


def apply_mask(payload, key):
    n = len(payload)
    if n == 0:
        return b""
    stream = (key * (n // 4 + 1))[:n]
    return (int.from_bytes(payload, "big") ^ int.from_bytes(stream, "big")).to_bytes(n, "big")


def encode_frame(opcode, payload=b"", fin=True, mask=True, key=None):
    """One WebSocket frame. Client frames must be masked (mask=True)."""
    n = len(payload)
    head = bytearray([(0x80 if fin else 0) | opcode])
    mbit = 0x80 if mask else 0
    if n < 126:
        head.append(mbit | n)
    elif n < 65536:
        head.append(mbit | 126)
        head += struct.pack("!H", n)
    else:
        head.append(mbit | 127)
        head += struct.pack("!Q", n)
    if mask:
        key = key if key is not None else os.urandom(4)
        return bytes(head) + key + apply_mask(payload, key)
    return bytes(head) + payload


def decode_frame(buf):
    """Parses one frame from the start of bytes `buf`. Returns None if incomplete, else
    (fin, opcode, payload, consumed). Unmasks payloads that arrive masked."""
    if len(buf) < 2:
        return None
    b0, b1 = buf[0], buf[1]
    fin, opcode = bool(b0 & 0x80), b0 & 0x0F
    masked, n, pos = bool(b1 & 0x80), b1 & 0x7F, 2
    if n == 126:
        if len(buf) < 4:
            return None
        n, pos = struct.unpack("!H", buf[2:4])[0], 4
    elif n == 127:
        if len(buf) < 10:
            return None
        n, pos = struct.unpack("!Q", buf[2:10])[0], 10
    key = b""
    if masked:
        if len(buf) < pos + 4:
            return None
        key, pos = buf[pos:pos + 4], pos + 4
    if len(buf) < pos + n:
        return None
    payload = bytes(buf[pos:pos + n])
    if masked:
        payload = apply_mask(payload, key)
    return fin, opcode, payload, pos + n


def split_records(buffer):
    """SignalR: records end with 0x1E. Returns (complete records, the unfinished remainder)."""
    parts = buffer.split(RS)
    return [p for p in parts[:-1] if p.strip()], parts[-1]


class WSError(Exception):
    pass


class WSConnection:
    """Client side of one WebSocket. recv_message() answers pings itself and reassembles
    fragmented messages; it raises socket.timeout when nothing arrived within the socket timeout
    (the connection stays usable)."""

    def __init__(self, sock):
        self.sock = sock
        self.buf = b""
        self.frag_op = None
        self.frag = []
        self.closed = False

    @classmethod
    def connect(cls, url, headers, timeout=15):
        p = urllib.parse.urlsplit(url)
        secure = p.scheme in ("wss", "https")
        port = p.port or (443 if secure else 80)
        try:
            sock = socket.create_connection((p.hostname, port), timeout)
            if secure:
                sock = ssl.create_default_context().wrap_socket(sock, server_hostname=p.hostname)
        except ssl.SSLError as e:
            if "CERTIFICATE_VERIFY_FAILED" in str(e):
                raise ConnectionError("TLS certificate check failed. If this is a python.org Python, run "
                                      "'Install Certificates.command' from its Applications folder, or use /usr/bin/python3.")
            raise ConnectionError("TLS error: %s" % e)
        except OSError as e:
            raise ConnectionError("Network error: %s" % e)
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        host = p.hostname if (p.port is None) else "%s:%d" % (p.hostname, p.port)
        lines = ["GET %s HTTP/1.1" % (p.path + ("?" + p.query if p.query else "")),
                 "Host: " + host, "Upgrade: websocket", "Connection: Upgrade",
                 "Sec-WebSocket-Key: " + key, "Sec-WebSocket-Version: 13"]
        lines += ["%s: %s" % (k, v) for k, v in headers.items()]
        try:
            sock.sendall(("\r\n".join(lines) + "\r\n\r\n").encode("utf-8"))
            data = b""
            while b"\r\n\r\n" not in data:
                chunk = sock.recv(4096)
                if not chunk:
                    raise WSError("connection closed during the WebSocket handshake")
                data += chunk
                if len(data) > 65536:
                    raise WSError("handshake response too large")
        except (OSError, WSError) as e:
            sock.close()
            raise ConnectionError("WebSocket handshake failed: %s" % e)
        head, rest = data.split(b"\r\n\r\n", 1)
        head_lines = head.decode("iso-8859-1").split("\r\n")
        status = head_lines[0].split(" ", 2)
        code = int(status[1]) if len(status) > 1 and status[1].isdigit() else 0
        hdrs = {}
        for l in head_lines[1:]:
            if ":" in l:
                k, v = l.split(":", 1)
                hdrs[k.strip().lower()] = v.strip()
        if code in (401, 403):
            sock.close()
            raise FatalError("F1's live timing refused the WebSocket (HTTP %d)." % code)
        if code != 101:
            sock.close()
            raise ConnectionError("WebSocket upgrade refused (HTTP %s)" % (code or "?"))
        accept = base64.b64encode(hashlib.sha1((key + WS_GUID).encode("ascii")).digest()).decode("ascii")
        if hdrs.get("sec-websocket-accept") != accept:
            sock.close()
            raise ConnectionError("WebSocket handshake: bad Sec-WebSocket-Accept")
        conn = cls(sock)
        conn.buf = rest
        return conn

    def set_timeout(self, seconds):
        self.sock.settimeout(seconds)

    def _send(self, opcode, payload=b""):
        self.sock.sendall(encode_frame(opcode, payload, mask=True))

    def send_text(self, text):
        self._send(OP_TEXT, text.encode("utf-8"))

    def ping(self):
        self._send(OP_PING, b"apexduoview")

    def close(self, code=1000):
        if not self.closed:
            self.closed = True
            try:
                self._send(OP_CLOSE, struct.pack("!H", code))
            except OSError:
                pass
        try:
            self.sock.close()
        except OSError:
            pass

    def recv_message(self):
        """Returns ('text', str), ('binary', bytes), ('close', code, reason), ('ping',) or ('pong',)."""
        while True:
            frame = decode_frame(self.buf)
            if frame is None:
                chunk = self.sock.recv(65536)  # socket.timeout propagates; buf is untouched
                if not chunk:
                    raise ConnectionError("connection closed by the server (no close frame)")
                self.buf += chunk
                continue
            fin, op, payload, used = frame
            self.buf = self.buf[used:]
            if op == OP_PING:
                self._send(OP_PONG, payload)
                return ("ping",)
            if op == OP_PONG:
                return ("pong",)
            if op == OP_CLOSE:
                code = struct.unpack("!H", payload[:2])[0] if len(payload) >= 2 else 1005
                reason = payload[2:].decode("utf-8", errors="replace")
                if not self.closed:
                    self.closed = True
                    try:
                        self._send(OP_CLOSE, payload[:2])
                    except OSError:
                        pass
                return ("close", code, reason)
            if op in (OP_TEXT, OP_BINARY):
                if self.frag_op is not None:
                    raise WSError("new data frame inside a fragmented message")
                self.frag_op, self.frag = op, [payload]
            elif op == OP_CONT:
                if self.frag_op is None:
                    raise WSError("continuation frame without a start")
                self.frag.append(payload)
            else:
                raise WSError("unknown opcode %d" % op)
            if fin:
                data, kind = b"".join(self.frag), self.frag_op
                self.frag_op, self.frag = None, []
                if kind == OP_TEXT:
                    return ("text", data.decode("utf-8", errors="replace"))
                return ("binary", data)


# --- Recorder -------------------------------------------------------------------------------

def utc_iso_ms():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def human_size(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return ("%d %s" % (n, unit)) if unit == "B" else ("%.1f %s" % (n, unit))
        n /= 1024.0


def new_output_path(directory):
    base = "timing_" + datetime.now().strftime("%Y%m%d-%H%M")
    path, k = os.path.join(directory, base + ".jsonl"), 2
    while os.path.exists(path):
        path = os.path.join(directory, "%s-%d.jsonl" % (base, k))
        k += 1
    return path


class Recorder:
    def __init__(self, token, path, ua=ANDROID_UA):
        self.token, self.path, self.ua = token, path, ua
        self.f = open(path, "a", encoding="utf-8", newline="\n")
        self.count = 0
        self.topics = {}
        self.reconnects = 0
        self.last_status = time.time()
        self.started = time.time()

    def write_line(self, obj):
        line = json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
        for s in SECRETS:  # belt and braces: a secret must never reach the file
            if s in line:
                line = line.replace(s, "<masked>")
        self.f.write(line + "\n")
        self.f.flush()

    def write_message(self, msg):
        self.write_line({"t": utc_iso_ms(), "msg": msg})
        self.count += 1

    def note_topics(self, msg):
        if not isinstance(msg, dict):
            return
        if msg.get("type") == 1 and msg.get("target") == "feed":
            args = msg.get("arguments")
            if isinstance(args, list) and args and isinstance(args[0], str):
                self.topics[args[0]] = self.topics.get(args[0], 0) + 1
        elif msg.get("type") == 3 and isinstance(msg.get("result"), dict):
            for k in msg["result"]:
                self.topics[k] = self.topics.get(k, 0) + 1

    def status(self, force=False):
        now = time.time()
        if not force and now - self.last_status < STATUS_INTERVAL_S:
            return
        self.last_status = now
        try:
            size = os.path.getsize(self.path)
        except OSError:
            size = 0
        say("[%s] messages=%d  topics=%d (%s)  file=%s  reconnects=%d" % (
            datetime.now().strftime("%H:%M:%S"), self.count, len(self.topics),
            ", ".join(sorted(self.topics)) or "none yet", human_size(size), self.reconnects))

    def handle_record(self, raw, ws, state):
        """One SignalR record. Returns nothing; raises ConnectionError to drop the connection."""
        try:
            msg = json.loads(raw)
        except ValueError:
            self.write_line({"t": utc_iso_ms(), "msg_unparsed": raw})
            self.count += 1
            return
        self.write_message(msg)
        self.note_topics(msg)
        if not isinstance(msg, dict):
            return
        mtype = msg.get("type", -1)
        if mtype == -1:
            # The handshake reply is an empty object: now ask for the topics (LiveFeed.kt).
            if msg.get("error"):
                raise ConnectionError("handshake refused: %s" % msg.get("error"))
            if not state["subscribed"]:
                state["subscribed"] = True
                ws.send_text(json.dumps({"type": 1, "invocationId": "0", "target": "Subscribe",
                                         "arguments": [TOPICS]}, separators=(",", ":")) + RS)
        elif mtype == 3:
            if msg.get("error"):
                raise ConnectionError("subscribe failed: %s" % msg.get("error"))
            if isinstance(msg.get("result"), dict):
                state["got_state"] = True
                say("Subscribed; initial state received for %d topic(s): %s" % (
                    len(msg["result"]), ", ".join(msg["result"])))
        elif mtype == 6:
            ws.send_text('{"type":6}' + RS)
        elif mtype == 7:
            raise ConnectionError("server asked to close: %s" % (msg.get("error") or "no reason given"))

    def run_connection(self):
        """One connection until it drops. Returns seconds it was up. Raises on failure."""
        ident, cookie = negotiate(self.token, self.ua)
        query = "id=%s&access_token=%s" % (urllib.parse.quote(ident, safe="%+/=:"), urllib.parse.quote(self.token, safe="%+/=:."))
        url = "%s?%s" % (hub_ws_url(), query)
        headers = {"Authorization": "Bearer " + self.token, "User-Agent": self.ua}
        if cookie:
            headers["Cookie"] = cookie
        ws = WSConnection.connect(url, headers)
        began = time.time()
        state = {"subscribed": False, "got_state": False}
        try:
            ws.set_timeout(1.0)
            ws.send_text(HANDSHAKE + RS)
            say("Connected; handshake sent.")
            pending = ""
            last_rx = last_ping = time.time()
            while True:
                now = time.time()
                self.status()
                if now - last_ping >= PING_INTERVAL_S:
                    ws.ping()
                    last_ping = now
                if now - last_rx > IDLE_LIMIT_S:
                    raise ConnectionError("no data for %d s" % IDLE_LIMIT_S)
                try:
                    item = ws.recv_message()
                except socket.timeout:
                    continue
                last_rx = time.time()
                if item[0] == "close":
                    raise ConnectionError("server closed the connection (code %s%s)" % (
                        item[1], (": " + item[2]) if item[2] else ""))
                if item[0] != "text":
                    continue
                records, pending = split_records(pending + item[1])
                for rec in records:
                    self.handle_record(rec, ws, state)
        except ConnectionError:
            raise
        except OSError as e:
            raise ConnectionError("connection lost: %s" % e)
        finally:
            up = time.time() - began
            self.last_up = up
            ws.close()

    def run(self):
        """Until Ctrl+C or too many consecutive failures."""
        consecutive = 0
        say("Recording to %s" % self.path)
        say("Press Ctrl+C when the session is over.")
        try:
            while True:
                self.last_up = 0.0
                try:
                    self.run_connection()
                except FatalError as e:
                    say("Stopping: %s" % e)
                    return
                except (ConnectionError, WSError) as e:
                    say("Connection ended: %s" % e)
                except KeyboardInterrupt:
                    raise
                except Exception as e:  # keep a long recording alive through odd failures
                    say("Connection ended unexpectedly: %s: %s" % (type(e).__name__, e))
                if self.last_up >= HEALTHY_AFTER_S:
                    consecutive = 0
                consecutive += 1
                if consecutive > MAX_RECONNECTS:
                    say("Giving up after %d reconnect attempts in a row." % MAX_RECONNECTS)
                    return
                delay = min(2 ** consecutive, 30)
                self.reconnects += 1
                say("Reconnect %d of %d in %d s ..." % (consecutive, MAX_RECONNECTS, delay))
                self.write_line({"t": utc_iso_ms(), "recorder": "reconnect", "attempt": consecutive})
                end = time.time() + delay
                while time.time() < end:
                    time.sleep(0.25)
        except KeyboardInterrupt:
            say("")
            say("Stopped by Ctrl+C.")
        finally:
            self.f.close()


def hub_ws_url():
    p = urllib.parse.urlsplit(HUB)
    return urllib.parse.urlunsplit(("wss" if p.scheme == "https" else "ws", p.netloc, p.path, "", ""))


# --- Archive download -----------------------------------------------------------------------

def normalise_archive_path(arg):
    """'2026/2026-11-08_São_Paulo_Grand_Prix/2026-11-08_Race/' (also accepts a full /static/ URL)."""
    p = arg.strip()
    if "/static/" in p:
        p = p.split("/static/", 1)[1]
    p = urllib.parse.unquote(p).strip("/")
    if not p or ".." in p.split("/") or "\\" in p:
        raise ValueError("That doesn't look like an archive path like 2026/2026-11-08_São_Paulo_Grand_Prix/2026-11-08_Race/")
    return p + "/"


def archive_folder_name(path):
    parts = [x for x in path.strip("/").split("/") if x]
    return "archive_" + re.sub(r"[^\w.-]+", "_", "_".join(parts[-2:]))


def archive_url(url_path):
    return ARCHIVE_BASE + urllib.parse.quote(url_path, safe="/")


def download_one(token, url_path, dest, ua, refused_fatal=True):
    """Streams one archive file to dest. Returns (status, bytes). Status 'ok', 'missing' or an error text.
    With refused_fatal=False a 401/403 is returned as 'refused (HTTP 403)' instead of stopping the run
    (the archive answers 403 for files it hasn't published)."""
    url = archive_url(url_path)
    conn, resp = https_request("GET", url, {"Authorization": "Bearer " + token, "User-Agent": ua})
    try:
        if resp.status in (401, 403):
            if not refused_fatal:
                return "refused (HTTP %d)" % resp.status, 0
            raise FatalError("F1's timing archive refused the login (HTTP %d). Sign in again and copy a fresh cookie." % resp.status)
        if resp.status == 404:
            return "missing", 0
        if resp.status != 200:
            return "HTTP %d" % resp.status, 0
        tmp, total = dest + ".part", 0
        with open(tmp, "wb") as f:
            while True:
                chunk = resp.read(1 << 20)
                if not chunk:
                    break
                f.write(chunk)
                total += len(chunk)
        os.replace(tmp, dest)
        return "ok", total
    except (OSError, http.client.HTTPException) as e:
        return "error: %s" % e, 0
    finally:
        conn.close()


def download_archive(token, arg, directory, ua=ANDROID_UA):
    path = normalise_archive_path(arg)
    folder = os.path.join(directory, archive_folder_name(path))
    os.makedirs(folder, exist_ok=True)
    say("Archive path: %s" % path)
    say("Saving into:  %s" % folder)
    got = missing = failed = 0
    total = 0
    jobs = [(path + name, name) for name in ARCHIVE_FILES]
    year = path.split("/", 1)[0]
    if re.fullmatch(r"\d{4}", year):  # the Android app finds sessions through the year's index
        jobs.append((year + "/Index.json", "Index_%s.json" % year))
    for url_path, name in jobs:
        status, size = download_one(token, url_path, os.path.join(folder, name), ua)
        if status == "ok":
            got += 1
            total += size
            say("  %-34s %s" % (name, human_size(size)))
        elif status == "missing":
            missing += 1
            say("  %-34s not in the archive (404)" % name)
        else:
            failed += 1
            say("  %-34s FAILED: %s" % (name, status))
    say("")
    say("Done: %d file(s), %s; %d not in the archive; %d failed." % (got, human_size(total), missing, failed))
    if got == 0:
        say("Nothing was downloaded. Check the path (copy it from the archive index) and that you are signed in.")
    say("The folder holds public timing data and no sign-in details, but it is large: no need to paste it into chat.")
    return 0 if got else 1


# --- Fixtures for the iOS app's beta.3 (owner check T-A) ------------------------------------

FIXTURES_NAME = "beta3-fixtures"         # the work folder and the zip next to this script
FIXTURES_YEAR = 2026
# The weekend's sessions to fetch, in this order; each with the names F1 has used for it.
FIXTURES_SESSIONS = [
    ("Race", ["race"]),
    ("Qualifying", ["qualifying"]),
    ("Sprint", ["sprint"]),
    ("Sprint Qualifying", ["sprint qualifying", "sprint shootout"]),
]
# Used only if the index can't be read or doesn't list the session (the index can lag).
GUESSED_SESSION_PATHS = {
    "Race": "2026/2026-11-08_São_Paulo_Grand_Prix/2026-11-08_Race/",
    "Qualifying": "2026/2026-11-08_São_Paulo_Grand_Prix/2026-11-07_Qualifying/",
}
CARDATA_FILE = "CarData.z.jsonStream"
CARDATA_HEAD_FILE = "CarData.z.head.jsonStream"
CARDATA_HEAD_BYTES = 1 << 20             # 1 MiB
FIXTURE_FILES = [n for n in ARCHIVE_FILES if n != CARDATA_FILE]  # CarData is probed, not downloaded
OPTIONAL_FILES = ["WeatherData.jsonStream", "WeatherData.json"]
DEFAULT_CIRCUIT_KEY = 14                 # Interlagos
PROBE_HEADERS = ["Content-Length", "Content-Range", "Accept-Ranges", "Content-Type", "Content-Encoding",
                 "Last-Modified", "ETag"]


def fold(text):
    """Lower case without accents, for matching names: 'São Paulo' and 'Sao Paulo' both give 'sao paulo'."""
    text = unicodedata.normalize("NFKD", str(text or ""))
    text = "".join(c for c in text if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", text.casefold()).strip()


def parse_json_bytes(data):
    """F1's archive JSON starts with a byte-order mark; strip it (utf-8-sig) before parsing."""
    return json.loads(data.decode("utf-8-sig"))


def find_meeting(index):
    """The São Paulo meeting in a year's Index.json. Returns (meeting, how it matched) or (None, reason)."""
    meetings = index.get("Meetings") if isinstance(index, dict) else None
    if not isinstance(meetings, list):
        return None, "the index has no Meetings list"
    meetings = [m for m in meetings if isinstance(m, dict) and "test" not in fold(m.get("Name"))]

    def names(m):
        country = m.get("Country") if isinstance(m.get("Country"), dict) else {}
        return [fold(m.get("Name")), fold(m.get("OfficialName")), fold(m.get("Location")), fold(country.get("Name"))]

    tiers = [
        ("name contains São Paulo", lambda m: any("sao paulo" in n for n in names(m)[:2])),
        ("location is São Paulo", lambda m: "sao paulo" in names(m)[2]),
        ("Brazil", lambda m: any(("brazil" in n or "brasil" in n) for n in names(m))),
    ]
    for how, test in tiers:
        found = [m for m in meetings if test(m)]
        if found:
            with_race = [m for m in found if any(fold(s.get("Name")) == "race" for s in m.get("Sessions") or []
                                                 if isinstance(s, dict))]
            return (with_race or found)[0], how
    return None, "no meeting named São Paulo / Sao Paulo / Brazil in the index"


def pick_sessions(meeting):
    """[(label, session dict)] for Race, Qualifying and, on a sprint weekend, Sprint and Sprint
    Qualifying. Names must match exactly, so 'Sprint Qualifying' never counts as 'Qualifying'."""
    sessions = [s for s in (meeting.get("Sessions") or []) if isinstance(s, dict)] if meeting else []
    picked = []
    for label, aliases in FIXTURES_SESSIONS:
        for s in sessions:
            if fold(s.get("Name")) in aliases:
                picked.append((label, s))
                break
    return picked


def session_folder(path):
    """'2026/2026-11-08_São_Paulo_Grand_Prix/2026-11-08_Race/' -> '2026-11-08_Race'."""
    last = [x for x in path.strip("/").split("/") if x][-1]
    return re.sub(r"[^\w.-]+", "_", last)


def fetch_bytes(url, headers, max_redirects=0):
    """GET a small file. Returns (status, {lower-case header: value}, body). Follows up to
    max_redirects redirects (only used for MultiViewer, which gets no sign-in)."""
    for _ in range(max_redirects + 1):
        conn, resp = https_request("GET", url, headers)
        try:
            body = resp.read()
            hdrs = {k.lower(): v for k, v in resp.getheaders()}
        except (OSError, http.client.HTTPException) as e:
            raise ConnectionError("Network error: %s" % e)
        finally:
            conn.close()
        if resp.status in (301, 302, 303, 307, 308) and hdrs.get("location"):
            nxt = urllib.parse.urljoin(url, hdrs["location"])
            if urllib.parse.urlsplit(nxt).scheme not in ("https", urllib.parse.urlsplit(url).scheme):
                return resp.status, hdrs, body
            url = nxt
            continue
        return resp.status, hdrs, body
    return resp.status, hdrs, body


def clean_reason(text, folder=None):
    """An error text safe for the zip: no sign-in, no path on this Mac (it holds the user name)."""
    text = str(text)
    for d in [folder, os.path.dirname(os.path.abspath(__file__)), os.path.expanduser("~")]:
        if not d or len(d) < 2:
            continue
        text = text.replace(d, "<folder>")
    return scrub(text)


def fetch_circuit(key, year, directory, ua=ANDROID_UA):
    """Saves MultiViewer's circuits/{key}/{year} as circuit-{key}-{year}.json in directory.
    NO Authorization header: MultiViewer is a third party. Returns (ok, detail, file name)."""
    name = "circuit-%s-%s.json" % (key, year)
    url = CIRCUITS_BASE + "%s/%s" % (key, year)
    try:
        status, hdrs, body = fetch_bytes(url, {"User-Agent": ua, "Accept": "application/json"}, max_redirects=3)
    except ConnectionError as e:
        return False, clean_reason(e), name
    if status != 200:
        return False, "HTTP %d" % status, name
    try:
        j = parse_json_bytes(body)
    except ValueError:
        return False, "the answer isn't JSON (%s)" % human_size(len(body)), name
    with open(os.path.join(directory, name), "wb") as f:
        f.write(body)
    facts = []
    if isinstance(j, dict):
        if isinstance(j.get("x"), list):
            facts.append("%d outline points" % len(j["x"]))
        for k, label in (("corners", "corners"), ("marshalSectors", "marshal sectors")):
            if isinstance(j.get(k), list):
                facts.append("%d %s" % (len(j[k]), label))
        if j.get("circuitName"):
            facts.append(str(j["circuitName"]))
    return True, "%s%s" % (human_size(len(body)), ("; " + ", ".join(facts)) if facts else ""), name


def probe_cardata(token, session_path, folder, ua=ANDROID_UA):
    """Size and byte-range support of the session's CarData.z.jsonStream, WITHOUT downloading it:
    a HEAD, then a GET for the first 1 MiB with a Range header (also proves whether ranges really
    work: 206 = yes, 200 = the server ignored the Range). Saves those first bytes, cut to whole
    lines, as CarData.z.head.jsonStream. Writes cardata-probe.json. Returns (ok, one-line detail)."""
    url = archive_url(session_path + CARDATA_FILE)
    probe = {"file": CARDATA_FILE, "session_path": session_path, "probed_at_utc": utc_iso_ms()}

    def facts(resp):
        d = {"status": resp.status}
        for h in PROBE_HEADERS:
            v = resp.getheader(h)
            if v is not None:
                d[h] = v
        return d

    # 1. HEAD
    try:
        conn, resp = https_request("HEAD", url, {"Authorization": "Bearer " + token, "User-Agent": ua})
        try:
            probe["head"] = facts(resp)
        finally:
            conn.close()
    except ConnectionError as e:
        probe["head"] = {"error": clean_reason(e, folder)}

    # 2. Ranged GET for the first 1 MiB; never reads more than that, even if the Range is ignored.
    saved = 0
    try:
        conn, resp = https_request("GET", url, {"Authorization": "Bearer " + token, "User-Agent": ua,
                                                "Range": "bytes=0-%d" % (CARDATA_HEAD_BYTES - 1)})
        try:
            probe["range_get"] = g = facts(resp)
            g["range_sent"] = "bytes=0-%d" % (CARDATA_HEAD_BYTES - 1)
            if resp.status in (200, 206):
                chunks, got = [], 0
                while got < CARDATA_HEAD_BYTES:
                    chunk = resp.read(min(65536, CARDATA_HEAD_BYTES - got))
                    if not chunk:
                        break
                    chunks.append(chunk)
                    got += len(chunk)
                data = b"".join(chunks)
                g["bytes_read"] = got
                cut = data.rfind(b"\n")
                if got >= CARDATA_HEAD_BYTES and cut >= 0:
                    data = data[:cut + 1]  # whole lines only
                with open(os.path.join(folder, CARDATA_HEAD_FILE), "wb") as f:
                    f.write(data)
                saved = len(data)
                g["bytes_saved_as_" + CARDATA_HEAD_FILE] = saved
                g["lines_saved"] = data.count(b"\n")
        except (OSError, http.client.HTTPException) as e:
            probe["range_get"] = {"error": clean_reason(e, folder)}
        finally:
            conn.close()  # closes mid-body when the server sent the whole file
    except ConnectionError as e:
        probe["range_get"] = {"error": clean_reason(e, folder)}

    # 3. Conclusions
    head, rng = probe.get("head", {}), probe.get("range_get", {})
    total = None
    m = re.search(r"/(\d+)\s*$", rng.get("Content-Range", ""))
    if m:
        total = int(m.group(1))
    elif head.get("status") == 200 and str(head.get("Content-Length", "")).isdigit():
        total = int(head["Content-Length"])
    elif rng.get("status") == 200 and str(rng.get("Content-Length", "")).isdigit():
        total = int(rng["Content-Length"])
    if rng.get("status") == 206:
        ranges = "yes"
    elif rng.get("status") == 200:
        ranges = "no (the server ignored the Range and sent the whole file)"
    elif "status" in rng:
        ranges = "unknown (ranged GET answered HTTP %d)" % rng["status"]
    else:
        ranges = "unknown (ranged GET failed)"
    probe["total_bytes"] = total
    probe["byte_ranges_work"] = ranges
    probe["accept_ranges_header"] = rng.get("Accept-Ranges", head.get("Accept-Ranges"))
    with open(os.path.join(folder, "cardata-probe.json"), "w", encoding="utf-8") as f:
        f.write(scrub(json.dumps(probe, indent=2, ensure_ascii=False)) + "\n")

    ok = rng.get("status") in (200, 206) and saved > 0
    if ok:
        detail = "%s in total; byte ranges: %s; first %s saved" % (
            human_size(total) if total is not None else "size unknown", ranges, human_size(saved))
    else:
        bits = []
        for label, d in (("HEAD", head), ("ranged GET", rng)):
            bits.append("%s %s" % (label, ("HTTP %d" % d["status"]) if "status" in d else d.get("error", "?")))
        detail = "; ".join(bits)
    return ok, detail


def download_session(token, label, session_path, folder, ua=ANDROID_UA):
    """The archive files --archive downloads (minus CarData) plus WeatherData if present.
    Nothing here stops the run. Returns (status, detail, {file: result}, SessionInfo or None)."""
    os.makedirs(folder, exist_ok=True)
    results, got, total = {}, 0, 0
    missing, refused, failed, optional_absent = [], [], [], []
    for name in FIXTURE_FILES + OPTIONAL_FILES:
        try:
            status, size = download_one(token, session_path + name, os.path.join(folder, name), ua,
                                        refused_fatal=False)
        except ConnectionError as e:
            status, size = clean_reason(e, folder), 0
        status = clean_reason(status, folder)
        results[name] = {"status": status, "bytes": size}
        if status == "ok":
            got += 1
            total += size
            say("    %-30s %s" % (name, human_size(size)))
            continue
        if name in OPTIONAL_FILES:
            optional_absent.append("%s (%s)" % (name, "404" if status == "missing" else status))
            say("    %-30s not available: %s (optional, fine)" % (name, "404" if status == "missing" else status))
        elif status == "missing":
            missing.append(name)
            say("    %-30s not in the archive (404)" % name)
        elif status.startswith("refused"):
            refused.append(name)
            say("    %-30s %s" % (name, status))
        else:
            failed.append(name)
            say("    %-30s FAILED: %s" % (name, status))
    info = None
    if results["SessionInfo.json"]["status"] == "ok":
        try:
            with open(os.path.join(folder, "SessionInfo.json"), "rb") as f:
                info = parse_json_bytes(f.read())
        except (OSError, ValueError):
            info = None
    detail = "%d files, %s" % (got, human_size(total))
    if missing:
        detail += "; not in the archive: %s" % ", ".join(missing)
    if refused:
        detail += "; refused: %s" % ", ".join(refused)
    if failed:
        detail += "; failed: %s" % ", ".join(failed)
    if optional_absent:
        detail += "; optional not available: %s" % ", ".join(optional_absent)
    if got == 0:
        status = "failed"
    elif refused or failed or info is None:
        status = "partial"
    else:
        status = "ok"
    return status, detail, results, info


def circuit_key_from(info):
    try:
        key = info["Meeting"]["Circuit"]["Key"]
    except (KeyError, TypeError):
        return None
    return key if isinstance(key, int) or (isinstance(key, str) and key.isdigit()) else None


def zip_has_secret(zip_path, token):
    """True if any member name or member content holds the sign-in in any form we know of."""
    needles = sorted({s.encode("utf-8") for s in SECRETS + [token] if s}, key=len, reverse=True)
    if not needles:
        return False
    overlap = len(needles[0]) - 1
    with zipfile.ZipFile(zip_path) as z:
        for info in z.infolist():
            name = info.filename.encode("utf-8")
            if any(n in name for n in needles):
                return True
            tail = b""
            with z.open(info) as f:
                while True:
                    chunk = f.read(1 << 20)
                    if not chunk:
                        break
                    buf = tail + chunk
                    if any(n in buf for n in needles):
                        return True
                    tail = buf[-overlap:] if overlap else b""
    return False


def run_fixtures(token, directory, ua=ANDROID_UA):
    """One command for owner check T-A: the 2026 index, the São Paulo sessions' archive files,
    a CarData probe per session and the circuit, zipped into beta3-fixtures.zip next to this
    script. Prints one ok/partial/failed line per step. Returns the exit code."""
    work = os.path.join(directory, FIXTURES_NAME)
    zip_path = os.path.join(directory, FIXTURES_NAME + ".zip")
    for old in (zip_path, zip_path + ".part"):
        if os.path.exists(old):
            os.remove(old)
    if os.path.isdir(work):
        shutil.rmtree(work)
    os.makedirs(work)
    steps = []          # (step, status, detail)
    written = []        # files this run wrote, relative to work
    summary = {"made_by": "spike/timing_recorder.py --fixtures", "made_at_utc": utc_iso_ms(),
               "year": FIXTURES_YEAR, "meeting": None, "sessions": [], "circuit": None}

    def step(name, status, detail):
        steps.append((name, status, detail))
        say("  -> %s: %s" % (status, detail))
        say("")

    # a. The year's index.
    index_name = "Index_%d.json" % FIXTURES_YEAR
    say("Step 1: %d/Index.json (the list of the year's sessions)" % FIXTURES_YEAR)
    index = None
    try:
        status, _, body = fetch_bytes(archive_url("%d/Index.json" % FIXTURES_YEAR),
                                      {"Authorization": "Bearer " + token, "User-Agent": ua})
        if status == 200:
            with open(os.path.join(work, index_name), "wb") as f:
                f.write(body)  # saved exactly as served (BOM included); the BOM is stripped only to read it
            written.append(index_name)
            try:
                index = parse_json_bytes(body)
                step("index", "ok", "%s, %s" % (index_name, human_size(len(body))))
            except ValueError:
                step("index", "failed", "%s was saved but isn't JSON" % index_name)
        elif status in (401, 403):
            step("index", "failed", "refused (HTTP %d); the sign-in may be stale. Trying the usual paths." % status)
        else:
            step("index", "failed", "HTTP %d. Trying the usual paths." % status)
    except ConnectionError as e:
        step("index", "failed", "%s. Trying the usual paths." % clean_reason(e, work))

    # b. The meeting and its sessions.
    say("Step 2: find the São Paulo Grand Prix and its sessions")
    meeting, how = (find_meeting(index) if index is not None else (None, "no index"))
    picked = pick_sessions(meeting) if meeting else []
    sessions = []   # (label, path, source)
    for label, s in picked:
        path = s.get("Path")
        try:
            sessions.append((label, normalise_archive_path(path), "index"))
        except (ValueError, AttributeError):
            say("  %s is in the index without a usable Path" % label)
    for label, path in GUESSED_SESSION_PATHS.items():
        if not any(l == label for l, _, _ in sessions):
            sessions.append((label, path, "guessed (not in the index)"))
    if meeting:
        summary["meeting"] = {k: meeting.get(k) for k in ("Key", "Name", "OfficialName", "Location") if k in meeting}
        summary["meeting"]["matched_by"] = how
        say("  Meeting: %s (matched by %s)" % (meeting.get("Name") or meeting.get("OfficialName"), how))
    for label, path, source in sessions:
        say("  %-18s %s  [%s]" % (label, path, source))
    if meeting and picked:
        step("sessions", "ok", "%s: %s" % (meeting.get("Name") or "meeting", ", ".join(l for l, _ in picked)))
    else:
        step("sessions", "failed", "%s; using the usual paths for Race and Qualifying" % (
            how if not meeting else "the meeting lists no Race/Qualifying"))

    # c + d. Each session's files and its CarData probe.
    circuit_key, key_source = None, None
    any_session_file = False
    for label, path, source in sessions:
        folder_name = session_folder(path)
        folder = os.path.join(work, folder_name)
        say("Step 3: %s files (%s)" % (label, folder_name))
        status, detail, results, info = download_session(token, label, path, folder, ua)
        if source != "index":
            detail += " [path %s]" % source
        step("%s files" % label, status, detail)
        for name, r in results.items():
            if r["status"] == "ok":
                written.append(folder_name + "/" + name)
                any_session_file = True
        entry = {"label": label, "path": path, "folder": folder_name, "path_source": source, "files": results}
        if circuit_key is None and circuit_key_from(info) is not None:
            circuit_key, key_source = int(circuit_key_from(info)), "%s SessionInfo.json" % label
        if status == "failed" and source != "index":
            summary["sessions"].append(entry)
            continue  # a guessed path that isn't there: no probe
        say("Step 4: %s CarData probe (size and byte ranges; not the whole file)" % label)
        ok, pdetail = probe_cardata(token, path, folder, ua)
        written.append(folder_name + "/cardata-probe.json")
        if os.path.exists(os.path.join(folder, CARDATA_HEAD_FILE)):
            written.append(folder_name + "/" + CARDATA_HEAD_FILE)
        step("%s CarData probe" % label, "ok" if ok else "failed", pdetail)
        with open(os.path.join(folder, "cardata-probe.json"), encoding="utf-8") as f:
            entry["cardata_probe"] = json.load(f)
        summary["sessions"].append(entry)

    # e. The circuit (no sign-in sent).
    if circuit_key is None and meeting and isinstance(meeting.get("Circuit"), dict):
        k = meeting["Circuit"].get("Key")
        if isinstance(k, int):
            circuit_key, key_source = k, "the index"
    if circuit_key is None:
        circuit_key, key_source = DEFAULT_CIRCUIT_KEY, "fallback (Interlagos)"
    say("Step 5: circuit %d/%d from MultiViewer (key from %s; no sign-in sent)" % (circuit_key, FIXTURES_YEAR, key_source))
    ok, cdetail, cname = fetch_circuit(circuit_key, FIXTURES_YEAR, work, ua)
    if ok:
        written.append(cname)
    summary["circuit"] = {"key": circuit_key, "key_from": key_source, "year": FIXTURES_YEAR, "file": cname if ok else None}
    step("circuit", "ok" if ok else "failed", "%s: %s" % (cname, cdetail))

    if not any_session_file:
        say("Nothing was downloaded from F1's archive, so no zip was made.")
        say("Sign in again at https://account.formula1.com, copy a fresh login-session cookie, and run it again.")
        shutil.rmtree(work, ignore_errors=True)
        return 1

    # f. The zip: only files this run wrote, under beta3-fixtures/<session folder>/.
    summary["steps"] = [{"step": n, "status": s, "detail": d} for n, s, d in steps]
    with open(os.path.join(work, "fixtures-summary.json"), "w", encoding="utf-8") as f:
        f.write(clean_reason(json.dumps(summary, indent=2, ensure_ascii=False), work) + "\n")
    written.append("fixtures-summary.json")
    say("Step 6: zip")
    part = zip_path + ".part"
    with zipfile.ZipFile(part, "w", zipfile.ZIP_DEFLATED) as z:
        for rel in written:
            z.write(os.path.join(work, rel), FIXTURES_NAME + "/" + rel)
    os.replace(part, zip_path)
    step("zip", "ok", "%d files" % len(written))

    # Self-check: the sign-in must not be anywhere in the zip.
    say("Step 7: check that the zip holds no sign-in details")
    if zip_has_secret(zip_path, token):
        os.remove(zip_path)
        shutil.rmtree(work, ignore_errors=True)
        say("  -> failed: the sign-in was found inside the zip, so the zip was DELETED. Do not upload anything;")
        say("     tell the developers (this is a bug in the script).")
        return 1
    step("token check", "ok", "no sign-in details in the zip")
    shutil.rmtree(work, ignore_errors=True)  # the zip is the only thing to upload

    say("Summary")
    for n, s, d in steps:
        say("  %-8s %-26s %s" % ("[" + s + "]", n, d))
    say("")
    say("Upload this one file:  %s" % zip_path)
    say("Size: %s. It holds public timing data only (checked: no sign-in details inside)." % human_size(os.path.getsize(zip_path)))
    if any(s != "ok" for _, s, _ in steps):
        say("Some steps did not fully work; upload the zip anyway, its fixtures-summary.json says what happened.")
    return 0


def save_circuit(key, year, directory):
    """--circuit KEY YEAR: no sign-in needed."""
    if not re.fullmatch(r"\d{1,4}", key or "") or not re.fullmatch(r"\d{4}", year or ""):
        say("Error: use  --circuit KEY YEAR, e.g.  --circuit 14 2026  (14 is Interlagos)")
        return 1
    ok, detail, name = fetch_circuit(int(key), int(year), directory)
    if not ok:
        say("Circuit %s/%s: FAILED: %s" % (key, year, detail))
        return 1
    say("Saved %s (%s)" % (os.path.join(directory, name), detail))
    return 0


def set_test_base_url(base):
    """--base-url (hidden, for local tests only): send archive and circuit requests to a stub
    server on this machine. Refuses any other host, so the sign-in can't go anywhere else."""
    global ARCHIVE_BASE, CIRCUITS_BASE
    p = urllib.parse.urlsplit(base)
    if p.scheme not in ("http", "https") or p.hostname not in ("127.0.0.1", "localhost", "::1"):
        raise ValueError("--base-url is for local tests and only accepts http://127.0.0.1:<port>")
    root = base.rstrip("/")
    ARCHIVE_BASE = root + "/static/"
    CIRCUITS_BASE = root + "/api/v1/circuits/"


# --- Main -----------------------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Throwaway spike: record a live F1 session's raw live-timing messages to a .jsonl file, "
                    "or (--archive) download a finished session's static archive files, or (--fixtures) "
                    "make beta3-fixtures.zip for the iOS app, or (--circuit) save a MultiViewer circuit.",
        usage="pbpaste | python3 timing_recorder.py [--archive <year/meeting/session/> | --fixtures]\n"
              "       python3 timing_recorder.py --circuit KEY YEAR")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--archive", metavar="PATH",
                      help="instead of recording, download a finished session's archive files, e.g. "
                           "2026/2026-11-08_São_Paulo_Grand_Prix/2026-11-08_Race/")
    mode.add_argument("--fixtures", action="store_true",
                      help="download the São Paulo Grand Prix 2026 timing fixtures for the iOS app's beta.3 "
                           "and zip them into beta3-fixtures.zip next to this script")
    mode.add_argument("--circuit", nargs=2, metavar=("KEY", "YEAR"),
                      help="save MultiViewer's circuit file (no sign-in needed), e.g. --circuit 14 2026")
    parser.add_argument("--base-url", help=argparse.SUPPRESS)  # local tests only (127.0.0.1)
    args = parser.parse_args(argv)
    directory = os.path.dirname(os.path.abspath(__file__))

    if args.base_url:
        try:
            set_test_base_url(args.base_url)
        except ValueError as e:
            print("Error: %s" % e)
            return 2

    if args.circuit:
        try:
            return save_circuit(args.circuit[0], args.circuit[1], directory)
        except KeyboardInterrupt:
            say("\nStopped by Ctrl+C.")
            return 1

    try:
        token, kind = read_signin("pbpaste | python3 spike/timing_recorder.py --fixtures" if args.fixtures
                                  else "pbpaste | python3 timing_recorder.py")
    except (ValueError, EOFError, KeyboardInterrupt) as e:
        print("Error: %s" % (e if str(e) else "cancelled"))
        return 1

    if args.fixtures:
        say("Fixtures for the iOS app's beta.3 (São Paulo Grand Prix %d). Sign-in given as: %s" % (FIXTURES_YEAR, kind))
        say("This downloads a few hundred MB at most and takes a few minutes. Leave the window open.")
        say("")
        try:
            return run_fixtures(token, directory)
        except KeyboardInterrupt:
            for leftover in (os.path.join(directory, FIXTURES_NAME + ".zip.part"),):
                if os.path.exists(leftover):
                    os.remove(leftover)
            say("\nStopped by Ctrl+C; no zip was made. Run the same command again.")
            return 1
        except Exception as e:  # never show a traceback that could hold more than it should
            say("Stopped by an unexpected error: %s: %s" % (type(e).__name__, clean_reason(e)))
            say("No zip was made. Send this message (it holds no sign-in details) to the developers.")
            return 1

    if args.archive:
        try:
            return download_archive(token, args.archive, directory)
        except (ValueError, FatalError) as e:
            say("Error: %s" % e)
            return 1
        except KeyboardInterrupt:
            say("\nStopped by Ctrl+C.")
            return 1

    path = new_output_path(directory)
    say("F1 live timing recorder (throwaway spike). Sign-in given as: %s" % kind)
    rec = Recorder(token, path)
    rec.run()
    rec.status(force=True)
    say("")
    say("Recording: %s   (%d messages, %s)" % (path, rec.count, human_size(os.path.getsize(path))))
    say("It contains no sign-in details. It is large, so it need not be pasted into chat.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
