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
                              crossing, element, merge, pace, read_stream, stints_at, utc_ms)

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


def line_states(lines):
    """Per car: [(offset, merged line)] after each stream line touching it (one state per line,
    as TimingTimeline keeps)."""
    merged, out = {}, {}
    for off, j in lines:
        for n, d in (j.get("Lines") or {}).items():
            if not isinstance(d, dict):
                continue
            merged[n] = merge(merged.get(n), d)
            h = out.setdefault(n, [])
            if h and h[-1][0] == off:
                h[-1] = (off, merged[n])
            else:
                h.append((off, merged[n]))
    return out


def race_lap(states, off, total):
    """The leader's lap in progress at `off`: the most laps any car has finished, plus one,
    capped at the race's length."""
    done = 0
    for h in states.values():
        m = None
        for o, x in h:
            if o > off:
                break
            m = x
        if m is not None and m.get("NumberOfLaps") is not None:
            done = max(done, int(m["NumberOfLaps"]))
    return min(done + 1, total)


def last_lap(m):
    cell = m.get("LastLapTime") or {}
    if not cell.get("Value"):
        return None, "empty"
    pace = "overallBest" if cell.get("OverallFastest") is True else "personalBest" if cell.get("PersonalFastest") is True else "set"
    return lap_ms(cell["Value"]), pace


def events(states, upto, started):
    """Pits after the start, retirements and new fastest laps up to `upto`, as (offset, kind, car)."""
    out, fastest, baseline = [], [], None
    for n, h in states.items():
        prev = None
        for o, m in h:
            if o > upto:
                break
            if prev is None:
                ms, pace = last_lap(m)
                if pace == "overallBest":
                    baseline = ms if baseline is None else min(baseline, ms)
                prev = m
                continue
            if m.get("InPit") is True and prev.get("InPit") is not True and o >= started:
                out.append((o, "pit", n))
            if m.get("Retired") is True and prev.get("Retired") is not True:
                out.append((o, "retirement", n))
            ms, pace = last_lap(m)
            pms, ppace = last_lap(prev)
            if pace == "overallBest" and (ppace != "overallBest" or pms != ms):
                fastest.append((o, n, ms))
            prev = m
    for o, n, ms in sorted(fastest, key=lambda f: (f[0], int(f[1]))):
        if baseline is None or ms < baseline:
            baseline = ms
            out.append((o, "fastestLap", n))
    return sorted(out)


def gap_ms(text):
    """F1's gap text ("+4.401") in ms; None for "LAP 7", "1L" and blanks."""
    body = (text or "").strip().lstrip("+")
    try:
        return int(round(float(body) * 1000)) if body and all(c.isdigit() or c == "." for c in body) else None
    except ValueError:
        return None


def pit_circle_checks(states, hist, t10):
    """The leader's reference lap, the circle's layout and a rejoin at `t10` (offsets)."""
    at = {n: state_at([(o, m, False) for o, m in h], t10) for n, h in states.items()}
    leader = next(n for n, m in at.items() if pos(m) == 1)
    crossings = [o for o, _, c in hist[leader] if c and o <= t10]
    windows = [b - a for a, b in zip(crossings, crossings[1:]) if 40_000 <= b - a <= 240_000]
    # Every window is green: no stops in the race window, and TrackStatus is 1 (AllClear) from
    # 00:28:19 to the fixture's end.
    green = windows[-5:]
    check("raceLeaderAtLightsOutPlus10min", leader)
    # F1 sends no time for lap 1 (LastLapTime "" at the first crossing): lights out to the line.
    first = hist[leader][[c for _, _, c in hist[leader]].index(True)]
    check("raceLeaderLap1LastLapTimeValue", repr(first[1]["LastLapTime"]["Value"]))
    check("raceLeaderLap1FromLightsOut", first[0] - RACE_LIGHTS_OUT_OFF)
    check("raceLeaderLapWindowsAtLightsOutPlus10min", windows)
    check("raceReferenceLapAtLightsOutPlus10min", sum(green) // len(green))
    check("raceTypicalLapAtLightsOutPlus10min", sorted(windows[-5:])[len(windows[-5:]) // 2])
    ref = sum(green) // len(green)
    racing = {n: m for n, m in at.items() if m.get("Retired") is not True and m.get("Stopped") is not True}
    gaps = {n: (0 if n == leader else gap_ms(m.get("GapToLeader"))) for n, m in racing.items()}
    check("raceGapsToLeaderAtLightsOutPlus10min", sorted(gaps.items(), key=lambda g: g[1]))
    lead_frac = ((t10 - crossings[-1]) / ref) % 1
    check("raceLeaderFractionAtLightsOutPlus10min", round(lead_frac, 6))
    for n in ("1", "44"):
        check(f"raceCar{n}FractionAtLightsOutPlus10min", round((lead_frac - gaps[n] / ref) % 1, 6))
    # A stop now for 44: out behind the last car whose gap is at most its own plus the loss.
    others = sorted((g, n) for n, g in gaps.items() if n != "44")
    for loss in (22_000, 5_000):
        target = gaps["44"] + loss
        ahead = [(g, n) for g, n in others if g <= target]
        check(f"raceRejoin44At{loss // 1000}sAtLightsOutPlus10min", (len(ahead) + 1, ahead[-1][1], target - ahead[-1][0]))
    with open(os.path.join(RACE, "DriverList.json"), encoding="utf-8-sig") as f:
        drivers = json.load(f)
    check("raceTlas11_16_44", [drivers[n]["Tla"] for n in ("11", "16", "44")])


def completed_laps(lines, car):
    """Car's finished laps: (lap, crossing offset, LastLapTime sent for it, its three sector paces),
    where a sector counts if its Value was set since the crossing before (a final sector sent
    with the crossing included), or is the final sector arriving within 3 s after the line while
    S1 of the new lap isn't set yet."""
    merged, laps, known, out = None, None, False, []
    since = [True, True, True]
    crossed_at = None
    for off, j in lines:
        d = (j.get("Lines") or {}).get(car)
        if not isinstance(d, dict):
            continue
        sectors = d.get("Sectors")
        cells = enumerate(sectors) if isinstance(sectors, list) else ((int(k), v) for k, v in (sectors or {}).items())
        late_final = False
        for i, cell in cells:
            if i > 2 or not isinstance(cell, dict) or not cell.get("Value"):
                continue
            if i == 2 and not since[0] and crossed_at is not None and 0 < off - crossed_at <= 3000:
                late_final = True
            else:
                since[i] = True
        merged = merge(merged, d)
        if "NumberOfLaps" in d:
            n = int(d["NumberOfLaps"])
            rose = n > laps if laps is not None else (known and n > 0)
            if rose:
                if d.get("PitOut") is not True:
                    crossed_at = off
                    paces = [pace(element(merged.get("Sectors"), i)) if since[i] else "empty" for i in range(3)]
                    out.append([n, off, None, paces])
                since = [False, False, False]
            laps = n
        known = True
        if out and out[-1][1] == crossed_at:
            if late_final:
                out[-1][3][2] = pace(element(merged.get("Sectors"), 2))
            cell = d.get("LastLapTime")
            if isinstance(cell, dict) and "Value" in cell:
                out[-1][2] = merged["LastLapTime"]["Value"]
    return out


def race_lines_checks(lines, states, hist, t10, car):
    at = {n: state_at([(o, m, False) for o, m in h], t10) for n, h in states.items()}
    me = at[car]
    p = pos(me)
    ahead = next(n for n, m in at.items() if pos(m) == p - 1)
    behind = next(n for n, m in at.items() if pos(m) == p + 1)
    check(f"raceLines{car}AtLightsOutPlus10min",
          (p, ahead, me["IntervalToPositionAhead"]["Value"], behind, at[behind]["IntervalToPositionAhead"]["Value"]))
    crossings = [o for o, _, c in hist[car] if c and o <= t10]
    then = t10 - (crossings[-1] - crossings[-4])
    was = {n: state_at([(o, m, False) for o, m in h], then) for n, h in states.items()}
    def g(states_at, n):
        return 0 if pos(states_at[n]) == 1 else gap_ms(states_at[n].get("GapToLeader"))
    check(f"raceLines{car}TrendAhead", (then, g(at, car) - g(at, ahead), g(was, car) - g(was, ahead)))
    check(f"raceLines{car}TrendBehind", (then, g(at, behind) - g(at, car), g(was, behind) - g(was, car)))
    laps = [x for x in completed_laps(lines, car) if x[1] <= t10]
    check(f"raceLines{car}LastFiveLaps", list(reversed(laps[-5:])))


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

    check("raceCar12CrossingOffsets", [o for o, _, crossed in hist["12"] if crossed])

    states = line_states(timing)
    ev = events(states, t10, lights)
    check("raceEventsAtLightsOutPlus10min", [(o, k, n, race_lap(states, o, 71)) for o, k, n in ev])
    ev = events(states, 10**12, lights)
    check("raceEventsWholeFixture", [(o, k, n, race_lap(states, o, 71)) for o, k, n in ev])

    pit_circle_checks(states, hist, t10)
    race_lines_checks(timing, states, hist, t10, "44")
    race_lines_checks(timing, states, hist, t10, "1")
    app = read_stream(os.path.join(RACE, "TimingAppData.jsonStream"))
    check("raceTyres44And1AtLightsOutPlus10min", [stints_at(app, t10).get(n) for n in ("44", "1")])
    tyres = {}
    for o, j in app:
        if o <= t10 and isinstance((j.get("Lines") or {}).get("44"), dict):
            tyres = merge(tyres, j["Lines"]["44"])
    st = tyres["Stints"]
    st = st if isinstance(st, list) else [v for _, v in sorted((int(k), v) for k, v in st.items())]
    check("raceTyre44CompoundAtLightsOutPlus10min", st[-1]["Compound"])
    check("raceCar12LastFiveLapsWholeFixture", list(reversed(completed_laps(timing, "12")[-5:])))

    # Qualifying's red flag: race control's RED FLAG (TrackFlags' red runs from it until a GREEN
    # or CHEQUERED flag, and none comes in the fixture), earlier than TrackStatus's 5.
    for off, j in read_stream(os.path.join(QUALI, "RaceControlMessages.jsonStream")):
        msgs = j.get("Messages")
        for m in (msgs if isinstance(msgs, list) else (msgs or {}).values()):
            if m.get("Flag") == "RED":
                check("qualiRedFlagUtc", utc_ms(m["Utc"]))
    status = read_stream(os.path.join(QUALI, "TrackStatus.jsonStream"))
    check("qualiTrackStatusRedUtc", [QUALI_START + o for o, j in status if j.get("Status") == "5"])


if __name__ == "__main__":
    main()
