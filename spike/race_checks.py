#!/usr/bin/env python3
"""Values the Task 12 tests (pit circle, race lines, lap chart, race events, readouts) assert,
decoded from the committed São Paulo 2026 fixtures in plain Python, independently of the Swift
code. Prints `check:<name> = <value>` lines; the Swift tests cite those names.

Crossings follow TimingTimeline's rule (as tower_checks.py): a lap count going up, or a first
count for a car already known, except one raised in the same delta as PitOut.

Python 3 standard library only. Run from anywhere: python3 spike/race_checks.py
"""
import base64
import contextlib
import io
import json
import os
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
with contextlib.redirect_stdout(io.StringIO()):  # tower_checks prints its own checks on import
    from tower_checks import (FIX, PREFIX, RACE_START, RACE_LIGHTS_OUT_OFF, QUALI_START, check,  # noqa: E402
                              crossing, merge, read_stream, utc_ms)

RACE = os.path.join(FIX, "sp26-race")
QUALI = os.path.join(FIX, "sp26-quali")


def car_histories(lines):
    """Per car: [(offset, merged line, crossed)] after each delta, in stream order."""
    merged, laps, known, out = {}, {}, set(), {}
    for off, j in lines:
        for n, d in (j.get("Lines") or {}).items():
            if not isinstance(d, dict):
                continue
            crossed = False
            if "NumberOfLaps" in d:
                crossed = crossing(n, d, laps.get(n), known)
                laps[n] = int(d["NumberOfLaps"])
            known.add(n)
            merged[n] = merge(merged.get(n), d)
            out.setdefault(n, []).append((off, merged[n], crossed))
    return out


def state_at(history, off):
    s = None
    for o, m, _ in history:
        if o > off:
            break
        s = m
    return s


def pos(m):
    try:
        return int(m.get("Position"))
    except (TypeError, ValueError):
        return None


def lap_ms(text):
    if not text:
        return None
    parts = text.split(":")
    sec = float(parts[-1])
    mins = int(parts[0]) if len(parts) == 2 else 0
    return int(round((mins * 60 + sec) * 1000))


def lap_chart(hist, upto):
    """Per car: {lap: position} at each crossing at or before `upto` (the merged line after the
    whole stream line holding the crossing, as the timeline keeps one state per line)."""
    rows = {}
    for n, h in hist.items():
        for i, (o, m, crossed) in enumerate(h):
            if o > upto or not crossed:
                continue
            # The state at the end of this stream offset (later deltas of the same line merged).
            last = m
            for o2, m2, _ in h[i + 1:]:
                if o2 != o:
                    break
                last = m2
            rows.setdefault(n, {})[int(last["NumberOfLaps"])] = pos(last)
    return rows


def car_data_checks():
    """Channel 45 in the qualifying CarData slice: present in how many samples, and in how many
    taken on a straight (150 km/h or more, throttle 95 % or more)."""
    path = os.path.join(QUALI, "CarData.z.slice.jsonStream")
    samples = straight = with45 = straight45 = 0
    fastest = None
    with open(path, encoding="utf-8-sig") as f:
        text = f.read()
    for line in text.split("\n"):
        line = line.lstrip("\ufeff")
        m = PREFIX.match(line)
        if not m or len(line) <= m.end():
            continue
        try:
            obj = json.loads(zlib.decompress(base64.b64decode(json.loads(line[m.end():])), -15))
        except Exception:
            continue  # the cut-off last line
        for e in obj["Entries"]:
            for n, c in e["Cars"].items():
                ch = c["Channels"]
                if fastest is None or ch.get("2", 0) > fastest[2].get("2", 0):
                    fastest = (n, utc_ms(e["Utc"]), ch)
                samples += 1
                on_straight = ch.get("2", 0) >= 150 and ch.get("4", 0) >= 95
                straight += on_straight
                with45 += "45" in ch
                straight45 += on_straight and "45" in ch
    check("carDataSamples", samples)
    check("carDataSamplesOnStraight", straight)
    check("carDataSamplesWithChannel45", with45)
    check("carDataStraightSamplesWithChannel45", straight45)
    check("carDataFastestSample", fastest)


def main():
    car_data_checks()
    timing = read_stream(os.path.join(RACE, "TimingData.jsonStream"))
    hist = car_histories(timing)

    lights = RACE_LIGHTS_OUT_OFF
    t10 = lights + 600_000
    chart = lap_chart(hist, t10)
    columns = max(max(r) for r in chart.values())
    check("raceLapChartColumnsAtLightsOutPlus10min", columns)
    for lap in range(1, columns + 1):
        ps = [r.get(lap) for r in chart.values() if r.get(lap) is not None]
        assert len(ps) == len(set(ps)), f"lap {lap} positions repeat: {sorted(ps)}"
    check("raceLapChartPositionsDistinctPerLap", True)
    for n in ("12", "1", "44", "77"):
        r = chart.get(n, {})
        check(f"raceLapChartCar{n}AtLightsOutPlus10min", [r.get(l) for l in range(1, columns + 1)])
    whole = lap_chart(hist, 10**12)
    check("raceLapChartColumnsWholeFixture", max(max(r) for r in whole.values()))
    r = whole.get("12", {})
    check("raceLapChartCar12WholeFixture", [r.get(l) for l in range(1, max(r) + 1)])


if __name__ == "__main__":
    main()
