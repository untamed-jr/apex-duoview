Committed LiveTiming fixtures, trimmed from the owner's raw timing data in `spike/beta3-fixtures/` (git-ignored, never committed) by `spike/trim_fixtures.py` (Python 3, standard library). Rerun it to rebuild everything below except `Position.z.line.txt` and `Position.z.expected.json` (Task 1's hand-picked line); it also prints, as `check:<name> = <value>`, every fixture value the tests assert, decoded independently in Python. The tests cite those names.

Source: F1's archive for the 2026 São Paulo Grand Prix, `2026/2026-11-08_São_Paulo_Grand_Prix/`. Stream offsets are the archive's own (counted from the stream's start); lines are LF-terminated, with the archive's BOM kept at the start of each file.

**`sp26-race/`** — the Race (session 11412). Window **00:51:44.576–01:05:44.576**: from 2 min before lights out to 12 min after. Lights out is 00:53:44.576 (SessionStatus `Started`; race control's "RACE START" follows at 00:53:44.858; the stream start is 2026-11-08 16:09:39.389 UTC, so lights out is 17:03:23.965 UTC).

**`sp26-quali/`** — Qualifying (session 11408). Window **00:13:20.736–00:25:20.736**: Q1's first 12 minutes (SessionStatus `Started` to +12 min). It includes Q1's red flag at 00:15:44, which lasted past the window. There is no LapCount (F1 publishes it for races only).

Per topic, in both:
- `DriverList.json`, `SessionInfo.json`, `WeatherData.json`, `Heartbeat.jsonStream`: whole.
- `Position.z.jsonStream`: the window only.
- `TimingData.jsonStream`: the archive's first line (the full initial state), then **one synthesized line** — the F1 delta merge of every other line before the window, stamped at the offset of the last of them — then the window. That line is the only one not copied verbatim from the archive; the script checks that the state at the window's start matches the full file's (`check:trimmedStateAtWindowStartEqualsRaw`).
- Every other topic (TimingAppData, SessionStatus, RaceControlMessages, TrackStatus, TeamRadio, LapCount, ExtrapolatedClock, WeatherData): every line up to the window's end.
- `sp26-quali/CarData.z.slice.jsonStream`: about 150 KB of CarData.z from Q1's start (00:13:20–00:15:55), cut mid-line at the end as a byte-range read is. The race's CarData head ends at 00:31, before its window, so the race has none.

Also: `Index-2026.json` (the season index with only the Mexico City and São Paulo meetings) and `circuit-14-2026.json` (MultiViewer's Interlagos circuit, whole).

**Long slices** (whole sessions, for the radio checks; no Position, CarData or weather):
- `sp26-race-long/` — the race's whole TeamRadio, TrackStatus, LapCount, SessionStatus, RaceControlMessages, DriverList, SessionInfo and Heartbeat. TimingData is reduced to `NumberOfLaps`, `Position`, `InPit`, `PitOut`, `Retired` and `Stopped` per car (every line that still says something, about 104 KB; deltas, so the merge is unchanged for those keys). 30 radio clips from 8 drivers.
- `sp26-quali-long/` — qualifying's whole TeamRadio, TrackStatus, SessionStatus, RaceControlMessages, ExtrapolatedClock, DriverList, SessionInfo and Heartbeat. 36 clips from 15 drivers. No TimingData, so no qualifying part.
The script scans both for tokens, signed URLs and account data and prints `check:secretScan:` lines (all must read 0 hits). Rebuild with `python3 spike/trim_fixtures.py <absolute path to the raw folder>`.

Total: 3.12 MB (the script refuses anything over 3.3 MB).
