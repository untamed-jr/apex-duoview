#!/usr/bin/env python3
"""Trim the owner's São Paulo 2026 timing archive into the committed LiveTiming fixtures.

Reads  spike/beta3-fixtures/            (git-ignored: the owner's raw archive, never committed)
Writes Packages/DuoCore/Tests/LiveTimingTests/Fixtures/sp26-race/, sp26-quali/,
       Index-2026.json and circuit-14-2026.json

Then decodes the trimmed files independently (plain Python, no Swift) and prints every value
the Swift tests assert, under a "check:" name the test comments cite.

Windows:
  race  — lights out (SessionStatus "Started") − 2 min … + 12 min
  quali — Q1's first 12 min (from the first SessionStatus "Started")

Per topic:
  DriverList.json, SessionInfo.json, WeatherData.json, Heartbeat — whole.
  Position.z — the window only.
  TimingData — the archive's first line (the full initial object), then ONE synthesized line:
    the F1 delta merge of every other line before the window, stamped at the last of those
    lines' offsets; then the window. It is the only line not copied from the archive.
  CarData.z (quali only) — CarData.z.slice.jsonStream: lines of the CarData head from Q1 start,
    about 150 KB, ending mid-line as a byte-range read does.
  Everything else — every line up to the window's end.
Lines are written with LF endings (the repo's `* text=auto` would rewrite CRLF), the archive's
BOM kept at the start of each stream file. Offsets are the archive's own.

Long slices (whole-session radio checks; no Position, CarData or weather):
  sp26-race-long  - whole TeamRadio, TrackStatus, LapCount, SessionStatus, RaceControlMessages,
                    DriverList, SessionInfo, Heartbeat; TimingData reduced to NumberOfLaps, Position,
                    InPit, PitOut, Retired and Stopped per car (every line kept that still says anything).
  sp26-quali-long - whole TeamRadio, TrackStatus, SessionStatus, RaceControlMessages,
                    ExtrapolatedClock, DriverList, SessionInfo, Heartbeat.

Python 3 standard library only. Run from anywhere: python3 spike/trim_fixtures.py [RAW_FOLDER]
"""
import base64
import json
import os
import re
import shutil
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Raw folder: the first argument, else spike/beta3-fixtures (it lives only in the main checkout).
RAW = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(ROOT, "spike", "beta3-fixtures")
OUT = os.path.join(ROOT, "Packages", "DuoCore", "Tests", "LiveTimingTests", "Fixtures")
BOM = "﻿"
BUDGET = 3_300_000
CARDATA_BYTES = 150_000
MINUTE = 60_000

PREFIX = re.compile(r"^(?:(\d+)\.)?(\d{2}):(\d{2}):(\d{2})\.(\d{3})")


# ---------- reading ----------

def read_stream(path):
    """[(offset_ms, payload_text)] for each line with a prefix."""
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if text.startswith(BOM):
        text = text[1:]
    out = []
    for raw in text.split("\n"):
        line = raw[:-1] if raw.endswith("\r") else raw
        m = PREFIX.match(line)
        if not m or len(line) <= m.end():
            continue
        days = int(m[1] or 0)
        off = (((days * 24 + int(m[2])) * 60 + int(m[3])) * 60 + int(m[4])) * 1000 + int(m[5])
        out.append((off, line[m.end():]))
    return out


def stamp(off):
    s, ms = divmod(off, 1000)
    return "%02d:%02d:%02d.%03d" % (s // 3600, s // 60 % 60, s % 60, ms)


def read_json(path):
    with open(path, encoding="utf-8-sig") as f:
        return json.load(f)


def utc_ms(iso):
    """ISO 8601 UTC to ms, by integer arithmetic; a missing Z is UTC; sub-ms digits truncate."""
    m = re.fullmatch(r"(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,7}))?Z?", iso)
    if not m:
        return None
    y, mo, d, h, mi, s = (int(m[i]) for i in range(1, 7))
    frac = (m[7] or "").ljust(3, "0")[:3]
    # days from civil (Howard Hinnant), as SignalR.utc does
    yy = y - 1 if mo <= 2 else y
    era = yy // 400
    yoe = yy - era * 400
    doy = (153 * (mo + (-3 if mo > 2 else 9)) + 2) // 5 + d - 1
    doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
    days = era * 146097 + doe - 719468
    return ((days * 24 + h) * 60 + mi) * 60_000 + s * 1000 + int(frac)


def z_decode(payload_text):
    return json.loads(zlib.decompress(base64.b64decode(json.loads(payload_text)), -15))


# ---------- F1's delta merge (mirrors TopicMerge.merge) ----------

def is_indexed(members):
    return bool(members) and all(k != "" and k.isdigit() and k.isascii() for k in members)


def deleted_keys(v):
    if isinstance(v, list):
        return [x if isinstance(x, str) else json.dumps(x) for x in v]
    if isinstance(v, str):
        return [v]
    if isinstance(v, dict):
        return list(v)
    return []


def merge(base, delta):
    if isinstance(delta, dict):
        members = dict(delta)
        members.pop("_kf", None)
        deleted = members.pop("_deleted", None)
        if isinstance(base, list):
            if not is_indexed(members):
                return base
            items = list(base)
            for k, v in members.items():
                i = int(k)
                if i > 10_000:
                    continue
                while len(items) <= i:
                    items.append(None)
                items[i] = merge(items[i], v)
            return items
        out = dict(base) if isinstance(base, dict) else {}
        for k in deleted_keys(deleted) if deleted is not None else []:
            out.pop(k, None)
        for k, v in members.items():
            out[k] = merge(out.get(k), v)
        return out
    if isinstance(delta, list):
        return [merge(None, x) for x in delta]
    return delta


def merged_until(lines, last_off):
    state = None
    for off, text in lines:
        if off > last_off:
            break
        state = merge(state, json.loads(text))
    return state


# ---------- writing ----------

def write_stream(path, lines, cut_last=None):
    body = BOM + "".join(stamp(off) + text + "\n" for off, text in lines)
    if cut_last is not None:
        body += cut_last
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(body)


def copy_file(src, dst):
    shutil.copyfile(src, dst)


def first_started(lines):
    for off, text in lines:
        if json.loads(text).get("Status") == "Started":
            return off
    sys.exit("no Started in SessionStatus")


def trim_session(folder, out_name, start_off, end_off, cardata):
    src = os.path.join(RAW, folder)
    dst = os.path.join(OUT, out_name)
    if os.path.isdir(dst):
        shutil.rmtree(dst)
    os.makedirs(dst)
    for name in ("DriverList.json", "SessionInfo.json", "WeatherData.json"):
        if os.path.exists(os.path.join(src, name)):
            copy_file(os.path.join(src, name), os.path.join(dst, name))
    for name in sorted(os.listdir(src)):
        if not name.endswith(".jsonStream") or name.startswith("CarData"):
            continue
        lines = read_stream(os.path.join(src, name))
        if name == "Heartbeat.jsonStream":
            kept = lines
        elif name == "Position.z.jsonStream":
            kept = [l for l in lines if start_off <= l[0] <= end_off]
        elif name == "TimingData.jsonStream":
            before = [l for l in lines[1:] if l[0] < start_off]
            kept = [lines[0]]
            if before:
                state = None
                for _, text in before:
                    state = merge(state, json.loads(text))
                kept.append((before[-1][0], json.dumps(state, ensure_ascii=False, separators=(",", ":"))))
            kept += [l for l in lines[1:] if start_off <= l[0] <= end_off]
        else:
            kept = [l for l in lines if l[0] <= end_off]
        write_stream(os.path.join(dst, name), kept)
    if cardata:
        lines = [l for l in read_stream(os.path.join(src, "CarData.z.head.jsonStream")) if l[0] >= start_off]
        kept, size = [], 0
        while size < CARDATA_BYTES:
            off, text = lines[len(kept)]
            kept.append((off, text))
            size += len(stamp(off) + text) + 1
        nxt = lines[len(kept)]
        partial = stamp(nxt[0]) + nxt[1][: len(nxt[1]) // 2]
        write_stream(os.path.join(dst, "CarData.z.slice.jsonStream"), kept, cut_last=partial)
    return dst


LONG_KEEP = ("NumberOfLaps", "Position", "InPit", "PitOut", "Retired", "Stopped")


def reduce_timing(text):
    """A TimingData line cut to LONG_KEEP per car; None when nothing is left."""
    cars = json.loads(text).get("Lines")
    if not isinstance(cars, dict):
        return None
    kept = {}
    for n, d in cars.items():
        if isinstance(d, dict):
            r = {k: d[k] for k in LONG_KEEP if k in d}
            if r:
                kept[n] = r
    return json.dumps({"Lines": kept}, ensure_ascii=False, separators=(",", ":")) if kept else None


def trim_long(folder, out_name, topics, reduce):
    src = os.path.join(RAW, folder)
    dst = os.path.join(OUT, out_name)
    if os.path.isdir(dst):
        shutil.rmtree(dst)
    os.makedirs(dst)
    for name in ("DriverList.json", "SessionInfo.json"):
        copy_file(os.path.join(src, name), os.path.join(dst, name))
    for topic in topics:
        write_stream(os.path.join(dst, topic + ".jsonStream"), read_stream(os.path.join(src, topic + ".jsonStream")))
    if reduce:
        kept = []
        for off, text in read_stream(os.path.join(src, "TimingData.jsonStream")):
            r = reduce_timing(text)
            if r is not None:
                kept.append((off, r))
        write_stream(os.path.join(dst, "TimingData.jsonStream"), kept)
    return dst


def trim_index():
    index = read_json(os.path.join(RAW, "Index_2026.json"))
    keep = [m for m in index["Meetings"] if m["Name"] in ("São Paulo Grand Prix", "Mexico City Grand Prix")]
    assert len(keep) == 2
    index["Meetings"] = keep
    with open(os.path.join(OUT, "Index-2026.json"), "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(index, ensure_ascii=False, separators=(",", ":")) + "\n")
    copy_file(os.path.join(RAW, "circuit-14-2026.json"), os.path.join(OUT, "circuit-14-2026.json"))


# ---------- independent checks ----------

def check(name, value):
    print(f"check:{name} = {value}")


def median_lower(values):
    v = sorted(values)
    return v[len(v) // 2]


def heartbeat_start(lines):
    starts = []
    for off, text in lines:
        u = json.loads(text).get("Utc")
        if u and utc_ms(u) is not None:
            starts.append(utc_ms(u) - off)
        if len(starts) == 50:
            break
    return median_lower(starts)


def position_start(lines):
    starts = []
    for off, text in lines[:50]:
        latest = max(utc_ms(s["Timestamp"]) for s in z_decode(text)["Position"])
        starts.append(latest - off)
    return median_lower(starts)


def position_tracks(lines):
    """Per car: [(t, x, y)], OffTrack skipped, non-increasing times dropped (as CarTrack does)."""
    tracks, off_track = {}, 0
    for _, text in lines:
        for s in z_decode(text)["Position"]:
            t = utc_ms(s["Timestamp"])
            for n, e in s["Entries"].items():
                if e.get("Status") == "OffTrack":
                    off_track += 1
                    continue
                tr = tracks.setdefault(n, [])
                if tr and t <= tr[-1][0]:
                    continue
                tr.append((t, e["X"], e["Y"]))
    return tracks, off_track


def report(race_dir, quali_dir, race_lo, quali_q1):
    print("== drivers / session info")
    drivers = read_json(os.path.join(race_dir, "DriverList.json"))
    cars = {k: v for k, v in drivers.items() if isinstance(v, dict)}
    check("driversCount", len(cars))
    check("driversAllHaveSixHexColour", all(re.fullmatch(r"[0-9A-Fa-f]{6}", v.get("TeamColour", "")) for v in cars.values()))
    d1 = cars["1"]
    check("driver1", (d1["Tla"], d1["FirstName"], d1["LastName"], d1["TeamName"], d1["TeamColour"]))
    for label, folder in (("race", race_dir), ("quali", quali_dir)):
        info = read_json(os.path.join(folder, "SessionInfo.json"))
        sign = -1 if info["GmtOffset"].startswith("-") else 1
        h, m, s = (int(x) for x in info["GmtOffset"].lstrip("+-").split(":"))
        gmt = sign * (h * 3600 + m * 60 + s)
        start = utc_ms(info["StartDate"]) - gmt * 1000
        check(f"{label}SessionInfo", (info["Key"], info["Name"], info["Type"], info["Path"], start, gmt,
                                      info["Meeting"]["Circuit"]["Key"], info["Meeting"]["Name"], int(info["StartDate"][:4])))

    print("== stream start")
    hb = read_stream(os.path.join(race_dir, "Heartbeat.jsonStream"))
    pos = read_stream(os.path.join(race_dir, "Position.z.jsonStream"))
    race_start = heartbeat_start(hb)
    race_pos_start = position_start(pos)
    check("raceHeartbeatStart", race_start)
    check("racePositionStart", race_pos_start)
    check("raceStartsDifferMs", race_pos_start - race_start)
    shifted = race_start + 33 * 3_600_000  # every beat's Utc moved 33 h later moves the median 33 h
    check("raceHeartbeatStartShifted33h", shifted)
    # |shifted − Position start| > 60 000 ms, so the Position start wins
    check("raceShiftedBy33hPicks", race_pos_start if abs(shifted - race_pos_start) > 60_000 else shifted)
    qhb = read_stream(os.path.join(quali_dir, "Heartbeat.jsonStream"))
    quali_start = heartbeat_start(qhb)
    check("qualiHeartbeatStart", quali_start)

    print("== windows")
    check("raceLightsOutOffset", race_lo)
    check("raceLightsOutUtc", race_start + race_lo)
    check("qualiQ1StartOffset", quali_q1)

    print("== positions")
    tracks, off_track = position_tracks(pos)
    check("raceWindowOffTrackEntries", off_track)
    check("raceWindowCars", len(tracks))
    target = race_start + race_lo + MINUTE
    tr = tracks["44"]
    for i in range(1, len(tr)):
        if tr[i][0] > target and (tr[i][0] - tr[i - 1][0]) % 2 == 0 and tr[i][0] - tr[i - 1][0] <= 5000:
            check("car44PairAroundLightsOutPlus1min", (tr[i - 1], tr[i]))
            break
    check("car44FirstLast", (tr[0][0], tr[-1][0]))
    check("raceMaxSampleGapMsInWindow", max(b[0] - a[0] for t in tracks.values() for a, b in zip(t, t[1:])))

    print("== timing")
    td = read_stream(os.path.join(race_dir, "TimingData.jsonStream"))
    raw_td = read_stream(os.path.join(RAW, "2026-11-08_Race", "TimingData.jsonStream"))
    ws = race_lo - 2 * MINUTE
    check("trimmedStateAtWindowStartEqualsRaw", merged_until(td, ws - 1) == merged_until(raw_td, ws - 1))
    qtd_trim = read_stream(os.path.join(quali_dir, "TimingData.jsonStream"))
    qtd_raw = read_stream(os.path.join(RAW, "2026-11-07_Qualifying", "TimingData.jsonStream"))
    check("qualiTrimmedStateAtWindowStartEqualsRaw", merged_until(qtd_trim, quali_q1 - 1) == merged_until(qtd_raw, quali_q1 - 1))
    t5 = race_lo + 5 * MINUTE
    state = merged_until(td, t5)
    laps = {n: d.get("NumberOfLaps") for n, d in state["Lines"].items()}
    check("raceMaxNumberOfLapsAtLightsOutPlus5min", max(v for v in laps.values() if v is not None))
    check("raceCarsWithLapsAtLightsOutPlus5min", sum(1 for v in laps.values() if v is not None))
    later = [off for off, text in td if off > t5 and any("NumberOfLaps" in d for d in json.loads(text).get("Lines", {}).values() if isinstance(d, dict))]
    check("firstLapCountUpdateAfterT5Offset", later[0])
    check("raceMaxNumberOfLapsJustAfterThat", max(d.get("NumberOfLaps") or 0 for d in merged_until(td, later[0])["Lines"].values()))
    # Car 44, lap 3 starts: S0 "22.676" arrives with no flag key; F1's flags are change-only, so
    # the merged PersonalFastest (true since 22.951) still holds — and 22.676 < 22.951 is a PB.
    s44 = merged_until(td, 3_435_379)["Lines"]["44"]
    check("car44AtOffset3435379", (s44["NumberOfLaps"], [(s.get("Value"), s.get("PersonalFastest"), s.get("OverallFastest")) for s in s44["Sectors"]],
                                   s44["LastLapTime"]["Value"], s44["LastLapTime"].get("PersonalFastest")))
    # Lap 1 ends with car 44's first NumberOfLaps: the keyframe and every earlier line have none.
    lap1 = [off for off, text in td if json.loads(text).get("Lines", {}).get("44", {}).get("NumberOfLaps") == 1]
    before = merged_until(td, lap1[0] - 1)["Lines"]["44"]
    check("car44Lap1CrossingOffset", (lap1[0], "NumberOfLaps" in before, json.loads(dict(td)[lap1[0]])["Lines"]["44"].get("Sectors")))
    crossing = [off for off, text in td if json.loads(text).get("Lines", {}).get("44", {}).get("NumberOfLaps") == 2]
    check("car44Lap2CrossingOffset", crossing[0])
    check("car44Lap2CrossingDelta", json.loads(dict(td)[crossing[0]])["Lines"]["44"])

    # Qualifying gaps live under Stats[SessionPart − 1], not at the line's top level.
    qtd = read_stream(os.path.join(quali_dir, "TimingData.jsonStream"))
    q10 = merged_until(qtd, quali_q1 + 10 * MINUTE)
    part = q10.get("SessionPart")
    second = [(n, d) for n, d in q10["Lines"].items() if d.get("Position") == "2"][0]
    stats = second[1]["Stats"]
    stats = stats[part - 1] if isinstance(stats, list) else stats[str(part - 1)]
    check("qualiP2AtQ1Plus10min", (part, second[0], stats["TimeDiffToFastest"], stats["TimeDifftoPositionAhead"],
                                   "TimeDiffToFastest" in second[1], "GapToLeader" in second[1]))

    print("== stints")
    tad = read_stream(os.path.join(race_dir, "TimingAppData.jsonStream"))
    t10 = race_lo + 10 * MINUTE
    st = merged_until(tad, t10)["Lines"]
    for n in ("1", "44"):
        stints = st[n]["Stints"]
        items = stints if isinstance(stints, list) else [stints[k] for k in sorted(stints, key=int)]
        check(f"stints{n}AtLightsOutPlus10min", [(s.get("Compound"), s.get("New"), s.get("StartLaps"), s.get("TotalLaps")) for s in items if s])

    print("== header")
    lc = read_stream(os.path.join(race_dir, "LapCount.jsonStream"))
    hdr = merged_until(lc, t5)
    check("raceLapCountAtLightsOutPlus5min", (hdr.get("CurrentLap"), hdr.get("TotalLaps")))
    clock = [(utc_ms(json.loads(t)["Utc"]), json.loads(t)) for _, t in read_stream(os.path.join(race_dir, "ExtrapolatedClock.jsonStream"))]
    at = race_start + t5
    mark_utc, mark = [c for c in clock if c[0] <= at][-1]
    h, m, s = (int(x) for x in mark["Remaining"].split(":"))
    rem = (h * 3600 + m * 60 + s) * 1000 - ((at - mark_utc) if mark.get("Extrapolating") else 0)
    check("raceClockRemainingSecondsAtLightsOutPlus5min", max(rem, 0) // 1000)
    w = merged_until(read_stream(os.path.join(race_dir, "WeatherData.jsonStream")), t5)
    check("raceWeatherAtLightsOutPlus5min", (w["AirTemp"], w["TrackTemp"], w["Rainfall"]))
    qclock = [(utc_ms(json.loads(t)["Utc"]), json.loads(t)) for _, t in read_stream(os.path.join(quali_dir, "ExtrapolatedClock.jsonStream"))]
    stopped = [c for c in qclock if c[1].get("Extrapolating") is False and c[1]["Remaining"] != "00:18:00"][0]
    check("qualiStoppedClockMark", (stopped[0], stopped[1]["Remaining"]))
    running = [c for c in qclock if c[1].get("Extrapolating") is True][0]
    h, m, s = (int(x) for x in running[1]["Remaining"].split(":"))
    check("qualiClockAtQ1MarkPlus10s", (running[0], ((h * 3600 + m * 60 + s) * 1000 - 10_000) // 1000))

    print("== flags (quali window)")
    rcm = read_stream(os.path.join(quali_dir, "RaceControlMessages.jsonStream"))
    msgs = []
    for off, text in rcm:
        m = json.loads(text)["Messages"]
        for x in (m if isinstance(m, list) else m.values()):
            msgs.append((utc_ms(x["Utc"]), x))
    reds = [u for u, x in msgs if x.get("Flag") == "RED"]
    greens = [u for u, x in msgs if x.get("Flag") in ("GREEN", "CHEQUERED") or (x.get("Category") == "SessionStatus" and "STARTED" in x.get("Message", ""))]
    check("qualiRedFlagUtc", reds)
    check("qualiGreensAfterRed", [g for g in greens if g > reds[0]])
    ts = read_stream(os.path.join(quali_dir, "TrackStatus.jsonStream"))
    check("qualiTrackStatus", [(quali_start + off, json.loads(t)["Status"]) for off, t in ts])

    print("== car data (quali slice)")
    with open(os.path.join(quali_dir, "CarData.z.slice.jsonStream"), encoding="utf-8") as f:
        body = f.read().lstrip(BOM)
    complete = body.split("\n")[:-1]
    check("carDataCompleteLines", len(complete))
    check("carDataLastLineEndsWithoutNewline", not body.endswith("\n"))
    samples, ch45 = {}, 0
    first = None
    for raw in complete:
        m = PREFIX.match(raw)
        for e in z_decode(raw[m.end():])["Entries"]:
            t = utc_ms(e["Utc"])
            for n, c in e["Cars"].items():
                ch = c["Channels"]
                ch45 += "45" in ch
                lst = samples.setdefault(n, [])
                if lst and t <= lst[-1][0]:
                    continue
                lst.append((t, ch.get("0", 0), ch.get("2", 0), ch.get("3", 0), ch.get("4", 0), ch.get("5", 0), ch.get("45", 0)))
                if first is None and n == "16" and ch.get("2", 0) > 0:
                    first = (t, ch)
    check("carDataCars", len(samples))
    check("carData16Count", len(samples["16"]))
    check("carData16First", samples["16"][0])
    check("carData16FirstMoving", first)
    check("carData16Last", samples["16"][-1])
    check("carDataChannel45Present", ch45)


def radio_clips(folder):
    """[(utc_ms, racing_number, path)] oldest first, first path wins (Android's addRadio)."""
    seen, out = set(), []
    for _, text in read_stream(os.path.join(folder, "TeamRadio.jsonStream")):
        caps = json.loads(text).get("Captures", [])
        if isinstance(caps, dict):
            caps = [caps[k] for k in sorted(caps, key=lambda k: (not k.isdigit(), int(k) if k.isdigit() else 0, k))]
        for c in caps:
            if c["Path"] in seen:
                continue
            seen.add(c["Path"])
            out.append((utc_ms(c["Utc"]), c["RacingNumber"], c["Path"]))
    return sorted(out, key=lambda c: c[0])  # stable: ties keep arrival order


def report_long(race_dir, quali_dir):
    print("== long slices (radio)")
    tla = {n: v["Tla"] for n, v in read_json(os.path.join(race_dir, "DriverList.json")).items() if isinstance(v, dict)}
    start = heartbeat_start(read_stream(os.path.join(race_dir, "Heartbeat.jsonStream")))
    clips = radio_clips(race_dir)
    check("longRaceClipCount", len(clips))
    counts = {}
    for _, n, _ in clips:
        counts[tla[n]] = counts.get(tla[n], 0) + 1
    check("longRaceClipsPerDriver", sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])))
    status = [(start + off, json.loads(t)["Status"]) for off, t in read_stream(os.path.join(race_dir, "SessionStatus.jsonStream"))]
    started = [u for u, s in status if s == "Started"][0]
    finished = [u for u, s in status if s == "Finished"][0]
    check("longRaceStartedUtc", started)
    check("longRaceFinishedUtc", finished)
    check("longRaceBeforeStartCount", sum(1 for c in clips if c[0] < started))
    check("longRaceAfterFlagCount", sum(1 for c in clips if c[0] > finished))
    check("longRaceAfterFlagDrivers", [tla[c[1]] for c in clips if c[0] > finished])
    td = read_stream(os.path.join(race_dir, "TimingData.jsonStream"))

    def laps_at(num, t):
        laps = None
        for off, text in td:
            if start + off > t:
                break
            d = json.loads(text)["Lines"].get(num, {})
            if "NumberOfLaps" in d:
                laps = d["NumberOfLaps"]
        return laps
    ant = [c for c in clips if tla[c[1]] == "ANT"]
    check("longRaceAntClips", [(c[0], c[2], laps_at(c[1], c[0])) for c in ant])
    # picture time of lap 23: ANT's NumberOfLaps reaches 22
    t23 = [start + off for off, text in td if json.loads(text)["Lines"].get("12", {}).get("NumberOfLaps") == 22][0]
    vis = [c for c in clips if c[0] <= t23]
    check("longRaceLap23PictureTime", t23)
    check("longRaceVisibleAtLap23", (len(vis), [c[0] for c in vis]))
    qclips = radio_clips(quali_dir)
    check("longQualiClipCount", len(qclips))
    check("longQualiDriverCount", len({c[1] for c in qclips}))
    # Tripwire for the public repo: the slices must hold no token, signed URL or account data.
    bad = re.compile(r"(authorization|bearer|subscriptiontoken|x-amz|signature=|access_token|password|e-?mail|@[a-z0-9-]+\.[a-z]{2,}|https?://[^\"\s]*\?)", re.I)
    for folder in (race_dir, quali_dir):
        for name in sorted(os.listdir(folder)):
            with open(os.path.join(folder, name), encoding="utf-8-sig") as f:
                hits = bad.findall(f.read())
            check(f"secretScan:{os.path.basename(folder)}/{name}", f"{len(hits)} hits {sorted(set(map(str, hits)))[:3]}")


def main():
    if not os.path.isdir(RAW):
        sys.exit(f"missing {RAW}: unpack the owner's beta3-fixtures.zip there first")
    os.makedirs(OUT, exist_ok=True)
    race_raw = os.path.join(RAW, "2026-11-08_Race")
    quali_raw = os.path.join(RAW, "2026-11-07_Qualifying")

    race_lo = first_started(read_stream(os.path.join(race_raw, "SessionStatus.jsonStream")))
    starts = [off for off, t in read_stream(os.path.join(race_raw, "RaceControlMessages.jsonStream")) if "RACE START" in t]
    assert starts and abs(starts[0] - race_lo) < 2000, (starts, race_lo)
    quali_q1 = first_started(read_stream(os.path.join(quali_raw, "SessionStatus.jsonStream")))

    race_dir = trim_session("2026-11-08_Race", "sp26-race", race_lo - 2 * MINUTE, race_lo + 12 * MINUTE, cardata=False)
    quali_dir = trim_session("2026-11-07_Qualifying", "sp26-quali", quali_q1, quali_q1 + 12 * MINUTE, cardata=True)
    trim_index()
    race_long = trim_long("2026-11-08_Race", "sp26-race-long",
                          ["Heartbeat", "TeamRadio", "TrackStatus", "LapCount", "SessionStatus", "RaceControlMessages"], True)
    quali_long = trim_long("2026-11-07_Qualifying", "sp26-quali-long",
                           ["Heartbeat", "TeamRadio", "TrackStatus", "SessionStatus", "RaceControlMessages", "ExtrapolatedClock"], False)

    print("== sizes")
    total = 0
    for base, _, files in os.walk(OUT):
        for name in sorted(files):
            p = os.path.join(base, name)
            size = os.path.getsize(p)
            total += size
            print(f"  {size:9d}  {os.path.relpath(p, OUT)}")
    print(f"  {total:9d}  total")
    assert total < BUDGET, f"fixtures are {total} bytes, over {BUDGET}"
    print(f"windows: race {stamp(race_lo - 2 * MINUTE)}–{stamp(race_lo + 12 * MINUTE)} (lights out {stamp(race_lo)}, "
          f"RCM RACE START {stamp(starts[0])}); quali {stamp(quali_q1)}–{stamp(quali_q1 + 12 * MINUTE)}")
    report(race_dir, quali_dir, race_lo, quali_q1)
    report_long(race_long, quali_long)


if __name__ == "__main__":
    main()
