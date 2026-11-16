#!/usr/bin/env python3
"""Values the Task 8 tests (tower, driver cards, lap states, battle, map cars) assert, decoded
from the committed São Paulo 2026 fixtures in plain Python, independently of the Swift code.

Prints `check:<name> = <value>` lines; the Swift tests cite those names. Lap states are a port
of Android's LiveTiming.parseStates (app/src/main/java/app/apexview/LiveTiming.kt): a crossing
is a lap count going up from an earlier count, except (LapStates' one change) a count raised in
the same delta as leaving the pits: 2026 qualifying sends NumberOfLaps with PitOut on every run.

Python 3 standard library only. Run from anywhere: python3 spike/tower_checks.py
"""
import base64
import json
import os
import re
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIX = os.path.join(ROOT, "Packages", "DuoCore", "Tests", "LiveTimingTests", "Fixtures")
PREFIX = re.compile(r"^(\d{2}):(\d{2}):(\d{2})\.(\d{3})")

RACE_START = 1_794_154_179_389      # check:raceHeartbeatStart (trim_fixtures.py)
RACE_LIGHTS_OUT_OFF = 3_224_576     # 00:53:44.576
QUALI_START = 1_794_073_601_573     # check:qualiHeartbeatStart
QUALI_Q1_OFF = 800_736              # check:qualiQ1StartOffset


def check(name, value):
    print(f"check:{name} = {value}")


def read_stream(path):
    with open(path, encoding="utf-8-sig") as f:
        text = f.read()
    out = []
    for line in text.split("\n"):
        line = line.lstrip("﻿")
        m = PREFIX.match(line)
        if not m or len(line) <= m.end():
            continue
        off = ((int(m[1]) * 60 + int(m[2])) * 60 + int(m[3])) * 1000 + int(m[4])
        out.append((off, json.loads(line[m.end():])))
    return out


def is_indexed(members):
    return bool(members) and all(k.isdigit() and k.isascii() for k in members)


def merge(base, delta):
    """F1's delta merge, as TopicMerge.merge (no _deleted in these fixtures' TimingData)."""
    if isinstance(delta, dict):
        members = {k: v for k, v in delta.items() if k not in ("_kf", "_deleted")}
        if isinstance(base, list):
            if not is_indexed(members):
                return base
            items = list(base)
            for k, v in members.items():
                i = int(k)
                while len(items) <= i:
                    items.append(None)
                items[i] = merge(items[i], v)
            return items
        out = dict(base) if isinstance(base, dict) else {}
        for k, v in members.items():
            out[k] = merge(out.get(k), v)
        return out
    if isinstance(delta, list):
        return [merge(None, x) for x in delta]
    return delta


def cars_at(lines, off):
    """Each car's merged TimingData line at stream offset `off` (lines at or before it)."""
    cars = {}
    for o, j in lines:
        if o > off:
            break
        for n, d in (j.get("Lines") or {}).items():
            if isinstance(d, dict):
                cars[n] = merge(cars.get(n), d)
    return cars


def element(v, i):
    if isinstance(v, list):
        return v[i] if i < len(v) else None
    if isinstance(v, dict):
        return v.get(str(i))
    return None


def pace(cell):
    if not isinstance(cell, dict) or not cell.get("Value"):
        return "empty"
    if cell.get("OverallFastest") is True:
        return "overallBest"
    if cell.get("PersonalFastest") is True:
        return "personalBest"
    return "set"


def lap_states(lines, qualifying):
    """Android's parseStates, per car: [(offset, state)] at each change. Outside qualifying,
    push and cool-down are never reported: the line ends an out lap and the car is unknown."""
    current, laps, out = {}, {}, {}
    for off, j in lines:
        for n, d in (j.get("Lines") or {}).items():
            if not isinstance(d, dict):
                continue
            state = current.get(n, "unknown")
            if d.get("InPit") is True:
                state = "pit"
            left = d.get("PitOut") is True or ("InPit" in d and d.get("InPit") is False and state == "pit")
            if left:
                state = "outLap"
            if "NumberOfLaps" in d:
                c = int(d["NumberOfLaps"])
                before = laps.get(n)
                laps[n] = c
                # Not Android: a count raised as the car leaves the pits (2026 qualifying sends
                # NumberOfLaps with PitOut on every run) is no crossing.
                if not left and before is not None and c > before:
                    if qualifying:
                        state = {"outLap": "push", "coolDown": "push", "push": "coolDown"}.get(state, state)
                    elif state == "outLap":
                        state = "unknown"
            if d.get("KnockedOut") is True:
                state = "knockedOut"
            if state != current.get(n):
                current[n] = state
                out.setdefault(n, []).append((off, state))
    return out


def state_at(history, off):
    s = "unknown"
    for o, v in history:
        if o > off:
            break
        s = v
    return s


def lap_text(ms):
    return "%d:%02d.%03d" % (ms // 60000, ms // 1000 % 60, ms % 1000)


def stints_at(lines, off):
    cars = {}
    for o, j in lines:
        if o > off:
            break
        for n, d in (j.get("Lines") or {}).items():
            if isinstance(d, dict):
                cars[n] = merge(cars.get(n), d)
    tyres = {}
    for n, s in cars.items():
        st = s.get("Stints")
        items = st if isinstance(st, list) else [v for _, v in sorted(((int(k), v) for k, v in (st or {}).items()))]
        withc = [x for x in items if isinstance(x, dict) and x.get("Compound")]
        if withc:
            tyres[n] = (withc[-1]["Compound"][0], int(withc[-1].get("TotalLaps") or 0))
    return tyres


def utc_ms(iso):
    m = re.fullmatch(r"(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,7}))?Z?", iso)
    y, mo, d, h, mi, s = (int(m[i]) for i in range(1, 7))
    frac = (m[7] or "").ljust(3, "0")[:3]
    yy = y - 1 if mo <= 2 else y
    era = yy // 400
    yoe = yy - era * 400
    doy = (153 * (mo + (-3 if mo > 2 else 9)) + 2) // 5 + d - 1
    doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
    days = era * 146097 + doe - 719468
    return ((days * 24 + h) * 60 + mi) * 60_000 + s * 1000 + int(frac)


def car_samples(path, number):
    """(utc, x, y) of one car's Position samples, OffTrack skipped, as PositionSeries keeps them."""
    out = []
    with open(path, encoding="utf-8-sig") as f:
        for line in f.read().split("\n"):
            line = line.lstrip("﻿")
            m = PREFIX.match(line)
            if not m or len(line) <= m.end():
                continue
            obj = json.loads(zlib.decompress(base64.b64decode(json.loads(line[m.end():])), -15))
            for sample in obj.get("Position", []):
                e = sample.get("Entries", {}).get(number)
                if e is None or e.get("Status") == "OffTrack":
                    continue
                t = utc_ms(sample["Timestamp"])
                if out and t <= out[-1][0]:
                    continue
                out.append((t, e["X"], e["Y"]))
    return out


def order(cars):
    def key(n):
        p = cars[n].get("Position")
        return (int(p) if p not in (None, "") else 99, int(n))
    return sorted(cars, key=key)


def interval_s(text):
    t = (text or "").strip().lstrip("+")
    try:
        return float(t)
    except ValueError:
        return None


def race():
    lines = read_stream(os.path.join(FIX, "sp26-race", "TimingData.jsonStream"))
    app = read_stream(os.path.join(FIX, "sp26-race", "TimingAppData.jsonStream"))

    t = RACE_LIGHTS_OUT_OFF + 600_000
    cars = cars_at(lines, t)
    ranked = order(cars)
    check("raceTowerOrderAtLightsOutPlus10min", ",".join(ranked))
    check("raceTowerCountAtLightsOutPlus10min", len(ranked))
    tyres = stints_at(app, t)
    for n in ranked[:3]:
        c = cars[n]
        check(f"raceTowerRow{n}AtLightsOutPlus10min", (
            c.get("Position"), c.get("LastLapTime", {}).get("Value"), pace(c.get("LastLapTime")),
            c.get("GapToLeader"), (c.get("IntervalToPositionAhead") or {}).get("Value"), tyres.get(n)))
    c77 = cars["77"]
    check("raceCar77AtLightsOutPlus10min", (c77.get("Position"), c77.get("InPit"), c77.get("Retired"), c77.get("Stopped")))

    # Car 77 in the pit lane before the start (InPit at 3103961, retired at 3347533).
    pit = cars_at(lines, 3_200_000)["77"]
    check("raceCar77At3200000", (pit.get("Position"), pit.get("InPit"), pit.get("Retired"), pit.get("LastLapTime", {}).get("Value")))

    # Lap states outside qualifying: never push or cool-down.
    states = lap_states(lines, qualifying=False)
    seen = sorted({s for h in states.values() for _, s in h})
    check("raceLapStatesSeen", seen)
    check("raceLapState77At3200000", state_at(states["77"], 3_200_000))
    check("raceLapStatesAtLightsOutPlus10min", sorted((n, state_at(h, t)) for n, h in states.items() if state_at(h, t) != "unknown"))

    # A battle: adjacent pairs within 1.0 s at every line from 10 s before t to t.
    window = [o for o, _ in lines if t - 10_000 <= o <= t]
    pairs = None
    for o in window:
        cs = cars_at(lines, o)
        rk = [n for n in order(cs) if cs[n].get("Position")]
        now = set()
        for a, b in zip(rk, rk[1:]):
            iv = interval_s((cs[b].get("IntervalToPositionAhead") or {}).get("Value"))
            if iv is not None and iv <= 1.0:
                now.add((a, b))
        pairs = now if pairs is None else pairs & now
    check("raceBattlesSteadyFor10sToLightsOutPlus10min", sorted(pairs))
    for a, b in sorted(pairs):
        check(f"raceInterval{b}to{a}AtLightsOutPlus10min", cars[b]["IntervalToPositionAhead"]["Value"])

    # Car 44's lap 2 ends at 3412677 (check:car44Lap2CrossingOffset).
    c44 = cars_at(lines, 3_412_677)["44"]
    lap = c44["LastLapTime"]
    check("car44LastLapAtLap2Crossing", (lap.get("Value"), pace(lap)))

    # Sector colours mid-lap: S1 and S2 set and S3 emptied, with some purple or green.
    found = None
    for o, j in lines:
        if o < t - 120_000 or o > t:
            continue
        for n, d in (j.get("Lines") or {}).items():
            sectors = d.get("Sectors") if isinstance(d, dict) else None
            if not isinstance(sectors, dict) or "1" not in sectors:
                continue
            c = cars_at(lines, o)[n]
            ps = [pace(element(c.get("Sectors"), i)) for i in range(3)]
            if ps[2] == "empty" and ps[0] != "empty" and ps[1] != "empty" and len({ps[0], ps[1]}) == 2:
                found = (o, n, ps, [element(c.get("Sectors"), i).get("Value") for i in range(3)])
        if found:
            break
    check("raceMixedSectorsMidLap", found)
    if found:
        o, n, _, _ = found
        later = [x for x, j in lines if x > o and n in (j.get("Lines") or {})]
        check("raceMixedSectorsCarNextLineOffset", later[0] if later else None)
        laps = cars_at(lines, o)[n].get("NumberOfLaps")
        crossings = [x for x, j in lines if x <= o and isinstance((j.get("Lines") or {}).get(n), dict)
                     and "NumberOfLaps" in j["Lines"][n]]
        check("raceMixedSectorsCarLapsAndLastCountOffset", (laps, crossings[-1] if crossings else None))

    # Car 77's positions around its retirement: a map point exists then, so leaving it out
    # is the retirement's doing.
    retired = RACE_START + 3_347_533
    samples = car_samples(os.path.join(FIX, "sp26-race", "Position.z.jsonStream"), "77")
    after = [s for s in samples if retired + 60_000 - 5_000 <= s[0] <= retired + 60_000 + 5_000]
    check("raceCar77SamplesWithin5sOfRetiredPlus60s", (len(after), after[:1], after[-1:]))
    before = [s for s in samples if RACE_START + 3_200_000 - 5_000 <= s[0] <= RACE_START + 3_200_000 + 5_000]
    check("raceCar77SamplesWithin5sOf3200000", (len(before), before[:1], before[-1:]))

    drivers = json.load(open(os.path.join(FIX, "sp26-race", "DriverList.json"), encoding="utf-8-sig"))
    for n in ("12", "44"):
        check(f"driver{n}", (drivers[n]["Tla"], drivers[n]["LastName"], drivers[n]["TeamColour"]))


def quali():
    lines = read_stream(os.path.join(FIX, "sp26-quali", "TimingData.jsonStream"))
    t = QUALI_Q1_OFF + 600_000
    cars = cars_at(lines, t)
    ranked = order(cars)
    check("qualiTowerOrderAtQ1Plus10min", ",".join(ranked))
    check("qualiKnockedOutAtQ1Plus10min", [n for n in ranked if cars[n].get("KnockedOut") is True])
    check("qualiBottomSixAtQ1Plus10min", ranked[-6:])

    states = lap_states(lines, qualifying=True)
    for probe in (QUALI_Q1_OFF + 10_000, 803_106, 900_000, 930_000):
        counts = {}
        for n in cars:
            s = state_at(states.get(n, []), probe)
            counts[s] = counts.get(s, 0) + 1
        check(f"qualiLapStateCountsAt{probe}", sorted(counts.items()))
    check("qualiLapStates77", states["77"])
    check("qualiLapStates43", states["43"])


race()
quali()
