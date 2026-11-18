"""Offline checks for timing_recorder.py --radio (owner check T-A4). Run: python3 spike/test_radio_probe.py
Uses synthetic data and a local stub server only; nothing here touches F1's hosts."""
import contextlib
import http.server
import io
import json
import os
import struct
import tempfile
import threading
import unittest
import urllib.parse

import timing_recorder as tr

TOKEN = "stub-token+not/real=0123456789"  # synthetic, plain text (no JWT shape); has characters that URL-encode
SESSION = "2026/2026-11-08_São_Paulo_Grand_Prix/2026-11-08_Race/"


def mpeg_frame(layer3=True, br_idx=9, sr_idx=0, xing_frames=None):
    """An MPEG-1 Layer III stereo frame header (128 kbps / 44.1 kHz by default), padded to a whole frame."""
    hdr = bytes([0xFF, 0xFB, (br_idx << 4) | (sr_idx << 2), 0x00])
    body = bytearray(417 - 4)
    if xing_frames is not None:
        body[32:36] = b"Info"
        body[36:40] = struct.pack(">I", 1)
        body[40:44] = struct.pack(">I", xing_frames)
    return hdr + bytes(body)


def id3_tag(payload=b"\0" * 20):
    n = len(payload)
    return b"ID3\x04\x00\x00" + bytes([(n >> 21) & 127, (n >> 14) & 127, (n >> 7) & 127, n & 127]) + payload


def make_stream(paths):
    lines = ["﻿00:00:01.000" + json.dumps({"Captures": [{"Utc": "x", "RacingNumber": "12", "Path": paths[0]}]})]
    lines.append("00:10:00.000" + json.dumps({"Captures": {"2": {"Path": paths[2]}, "1": {"Path": paths[1]}}}))
    lines.append("00:11:00.000" + json.dumps({"Captures": {"3": {"Path": paths[0]}}}))  # a repeat
    return "\r\n".join(lines).encode("utf-8")


PATHS = ["TeamRadio/ANT_12_a.mp3", "TeamRadio/NOR_4_b.mp3", "TeamRadio/VER_1_c.mp3"]
CLIPS = {
    PATHS[0]: id3_tag() + mpeg_frame(xing_frames=100),            # ID3 + Info frame: 100*1152/44100 = 2.612 s
    PATHS[1]: mpeg_frame() * 40,                                  # bare sync, constant bitrate estimate
    PATHS[2]: b"not audio at all",
}


def make_handler(require_token_for_clips):
    class H(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def do_GET(self):
            path = urllib.parse.unquote(self.path)
            auth = self.headers.get("Authorization")
            base = "/static/" + SESSION
            if not path.startswith(base):
                return self.reply(404, b"")
            rel = path[len(base):]
            if rel == "TeamRadio.jsonStream":
                return self.reply(200 if auth == "Bearer " + TOKEN else 403, make_stream(PATHS))
            if rel in CLIPS:
                if require_token_for_clips and auth != "Bearer " + TOKEN:
                    return self.reply(403, b"Forbidden")
                return self.reply(200, CLIPS[rel])
            self.reply(404, b"")

        def reply(self, code, body):
            self.send_response(code)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
    return H


class Parsing(unittest.TestCase):
    def test_id3_and_info_frame(self):
        r = tr.probe_audio(CLIPS[PATHS[0]])
        self.assertEqual((r["format"], r["sample_rate"], r["bitrate_kbps"]), ("ID3", 44100, 128))
        self.assertAlmostEqual(r["duration_s"], 100 * 1152 / 44100, places=3)
        self.assertIn("Info", r["duration_how"])

    def test_bare_sync_estimates_from_bitrate(self):
        r = tr.probe_audio(CLIPS[PATHS[1]])
        self.assertEqual((r["format"], r["sample_rate"], r["bitrate_kbps"]), ("MPEG frame sync", 44100, 128))
        self.assertAlmostEqual(r["duration_s"], 40 * 417 * 8 / 128000.0, places=3)

    def test_mpeg2_22k(self):
        data = bytes([0xFF, 0xF3, 0x80 | 0x00, 0x00]) + bytes(200)  # MPEG-2 L3, 64 kbps?, 22.05 kHz
        r = tr.probe_audio(data)
        self.assertEqual((r["sample_rate"], r["bitrate_kbps"]), (22050, 64))

    def test_not_audio(self):
        self.assertEqual(tr.probe_audio(CLIPS[PATHS[2]])["format"], "unknown")
        self.assertEqual(tr.probe_audio(b"")["format"], "unknown")

    def test_clip_paths_list_dict_dedupe_order(self):
        self.assertEqual(tr.radio_clip_paths(make_stream(PATHS)), PATHS)
        self.assertEqual(tr.radio_clip_paths(make_stream(PATHS), limit=2), PATHS[:2])
        self.assertEqual(tr.radio_clip_paths(b"garbage\n{bad json"), [])


class EndToEnd(unittest.TestCase):
    def run_probe(self, require_token):
        srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), make_handler(require_token))
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        base_before = tr.ARCHIVE_BASE
        try:
            tr.set_test_base_url("http://127.0.0.1:%d" % srv.server_port)
            tr.add_secret(TOKEN)
            out = io.StringIO()
            with tempfile.TemporaryDirectory() as d, contextlib.redirect_stdout(out):
                rc = tr.run_radio(TOKEN, d)
                files = sorted(os.listdir(os.path.join(d, tr.RADIO_DIR)))
            return rc, out.getvalue(), files
        finally:
            srv.shutdown()
            srv.server_close()
            tr.ARCHIVE_BASE = base_before

    def test_open_clips(self):
        rc, out, files = self.run_probe(False)
        self.assertEqual(rc, 0)
        self.assertEqual(len([l for l in out.splitlines() if l.startswith("clip ")]), 6)
        self.assertEqual(len(files), 6)
        self.assertNotIn(TOKEN, out)
        self.assertIn("format ID3, 44100 Hz, 128 kbps, 2.6 s", out)

    def test_clips_need_token(self):
        rc, out, files = self.run_probe(True)
        self.assertEqual(rc, 0)
        self.assertIn("no token  : HTTP 403, 0 bytes", out)
        self.assertEqual(len(files), 3)  # only the with-token downloads are saved
        self.assertNotIn(TOKEN, out)


class Masking(unittest.TestCase):
    def test_added_secret_is_masked_plain_and_encoded(self):
        tr.add_secret(TOKEN)
        self.assertNotIn(TOKEN, tr.scrub("Bearer " + TOKEN))
        self.assertNotIn(urllib.parse.quote(TOKEN, safe=""), tr.scrub("?t=" + urllib.parse.quote(TOKEN, safe="")))

    def test_jwt_shape_is_masked_without_being_added(self):
        # Assembled at run time so no JWT-shaped literal sits in this public file.
        jwt = ".".join(["ey" + "J" + "a" * 12, "b" * 12, "c" * 12])
        self.assertNotIn(jwt, tr.scrub("Authorization: " + jwt))
        self.assertIn("<masked-jwt>", tr.scrub("x " + jwt))


class Failures(unittest.TestCase):
    def test_refused_port_gives_error_line_not_abort(self):
        with tempfile.TemporaryDirectory() as d:
            st, size, data = tr.radio_try("http://127.0.0.1:1/x.mp3", os.path.join(d, "x"), {"Authorization": "Bearer " + TOKEN})
        self.assertTrue(st.startswith("error: "))
        self.assertEqual((size, data), (0, b""))
        self.assertNotIn(TOKEN, st)

    def test_report_has_no_local_path(self):
        srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), make_handler(False))
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        base_before = tr.ARCHIVE_BASE
        try:
            tr.set_test_base_url("http://127.0.0.1:%d" % srv.server_port)
            out = io.StringIO()
            with tempfile.TemporaryDirectory() as d, contextlib.redirect_stdout(out):
                tr.run_radio(TOKEN, d)
            self.assertNotIn(d, out.getvalue())
            self.assertIn("spike/radio-probe/", out.getvalue())
        finally:
            srv.shutdown()
            srv.server_close()
            tr.ARCHIVE_BASE = base_before


if __name__ == "__main__":
    unittest.main()
