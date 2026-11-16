# v1.0-beta.3 — Live data Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show F1's timing data next to the video, kept in step with it:
- track map, tower, flags, driver cards and pit circle;
- tap a car to open its onboard;
- Director's Desk, the book data screen, Race Engineer and Scrub Deck;
- live timing with recording.

**Architecture:**
- **Logic in DuoCore.** A new Foundation-only DuoCore target, `LiveTiming`, holds all decoding, parsing, time series and race calculations, tested on Linux against trimmed real archive fixtures.
- **App.** A `@MainActor` `TimingController` per watched session loads the archive or connects live and publishes snapshots at picture time. SwiftUI views (map `Canvas`, tower, cards, console, Scrub Deck) read those snapshots.
- **Layouts.** `LayoutEngine` gains data layouts that return data regions beside the feed tiles.

**Tech Stack:**
- Swift 6 with strict concurrency, SwiftUI and UIKit;
- AVFoundation (`AVPlayerItem.currentDate()`);
- `URLSessionWebSocketTask`;
- XcodeGen;
- Swift Testing in DuoCore (`/opt/swift/usr/bin/swift test` from `Packages/DuoCore`).

**Spec:** `docs/superpowers/specs/2026-11-16-beta3-live-data-design.md` (owner-approved 2026-11-16). Read it with this plan; it is the authority.

## Global Constraints

**Platform and language**
- iOS 27.1 deployment target.
- Swift 6 language mode with `SWIFT_STRICT_CONCURRENCY: complete`.
- App types that touch UI or AVFoundation are `@MainActor`.
- Callbacks from AVFoundation, URLSession or background work are `@Sendable` and hop to the main actor with plain values.

**DuoCore**
- Imports Foundation only; the existing conditional `import CoreGraphics` in `LayoutEngine.swift` stays.
- No third-party dependencies anywhere.

**Network and auth**
- Hosts:
  - `https://livetiming.formula1.com/signalrcore` (live);
  - `https://livetiming.formula1.com/static/` (archive);
  - `https://api.multiviewer.app/api/v1/circuits/{circuitKey}/{year}` (circuit, no auth).
- Auth: the F1 TV subscription token as `Authorization: Bearer <token>` on the hub and archive.
- **Timing refusals (401/403) never sign the user out.** They mark that piece unavailable or retry.

**Formats**
- `.z` topics are base64, then raw deflate (no zlib header), then JSON.
- Archive stream lines are `HH:MM:SS.mmm` + JSON, with the BOM stripped.

**Picture time and live timing**
- Picture time = the main feed's program date-time + offset.
  - The offset defaults to **−7 s** (`-7000` ms), is global, and nudges in ±1 s steps. Settings has "Reset to −7 s".
  - With no program date-time: session start + player position, flagged as estimated. The panel then shows "Timing estimated — nudge until the cars match".
- **No data later than picture time is ever shown,** except the Scrub Deck's opt-in "Show the whole race on the Scrub Deck" (off by default).
- Live subscribes to 14 topics: Heartbeat, Position.z, CarData.z, TimingData, DriverList, SessionInfo, SessionStatus, RaceControlMessages, TeamRadio, TimingAppData, TrackStatus, LapCount, ExtrapolatedClock, WeatherData.
  - Ping every 15 s; reconnect after 5 s.
  - One shared connection, reference-counted.

**Timing rules**
- Archive start time = the median UTC of the first 50 Heartbeat beats. If Position disagrees with it by more than 60 s, Position wins.
- Interpolation gap limit 5 s.
- Readouts grey after 5 s stale.
- Driver card lap time shows for 6 s after the line.

**Pit circle**
- Reference lap = the average of the leader's last 5 green laps, then the typical lap, then the last lap.
- Pit loss = the session median, else the stored per-circuit value, else 22 s.

**Retries, recording and the next-live check**
- Map load retries at 3 s, 10 s, 30 s and 60 s, then every 60 s.
- Live recording:
  - every topic except CarData.z and Heartbeat;
  - lines of `topic\tutcMs\t0|1\tjson`;
  - flushed every 2 s;
  - files older than 7 days deleted.
- Archive top-up retries every 2 min, up to 180 times, and stops once the archive reaches within 30 s of the join.
- The next-live check runs every 60 s, only while a live session is watched.

**Flags, tap-a-car, battle and copy**
- Flag colours: yellow `#FFD60A`, red `#FF3B30`.
- Tap-a-car ranking: pits or knocked out, then out-lap or cool-down, then flying lap. Ties go to the one placed longest ago.
  - Never replace the audible feed or a non-onboard feed.
- Battle: within 1.0 s of the car ahead or behind for two timing updates in a row. Off with no favourite driver.
- Fixed copy:
  - "Map unavailable — trying again…"
  - "Connecting to live timing…"
  - "Live timing dropped — reconnecting…"
  - "Live timing is connected, but F1 isn't sending car positions"
  - "No timing for this session"
  - "No onboard for car \(n) in this session."
  - "No free spot — change a feed in the editor."
  - "Tap a car to pick an onboard"
  - "The circle starts once the leader has finished a lap."
  - "Saved for beta.4: team radio"
  - "Show the whole race on the Scrub Deck"
  - "Speed readouts on mobile data"
  - "Tracker delay"
  - "Reset to −7 s"
  - "Switch" / "Not now"
  - Beta.1 and beta.2 copy stays as it is.

**Build, privacy, fixtures and commits**
- `Config/Version.xcconfig`: `BETA_LABEL = beta.3`. `CURRENT_PROJECT_VERSION` goes to 11, 12, 13, 14, 15 at the five owner builds (Tasks 7, 9, 11, 13, 15).
- Tokens, cookies and signed URLs are never logged, printed, put in errors or files, or committed.
- Fixtures are timing data trimmed from the owner's T-A download (`beta3-fixtures.zip`).
- Commits end with the session's attribution lines. Push to `ios` only.
- The app can't be compiled in the cloud. App tasks are written to compile first time, and each owner build checks them.

## Review Focus

1. **A 403 from the archive** for a file F1 hasn't published (WeatherData, top-up, `SessionInfo.json` probe): that piece is unavailable, the rest loads, nobody is signed out, the video plays. Test in Task 4.
2. **Picture time jumping** (seek back, pause, scrub, live edge) or missing: every query returns state at or before picture time, never later; the estimated flag is set without a program date. Tests in Tasks 6 and 12.
3. **Odd cars:**
   - a car number in timing with no DriverList entry or no onboard channel;
   - a car that retires mid-session;
   - a session with fewer than 20 cars.

   No crash; "No onboard for car N in this session."; retired cars leave the map. Tests in Tasks 3 and 8.
4. **Live reconnect mid-session:** the new snapshot replaces state (no doubled laps or stops), and the recording is appended without duplicating the snapshot's history. Tests in Tasks 2 and 14.
5. **Car data cut short** (a truncated last line, a partial range, a gap in the data): the window parser drops the broken line, and readouts grey after 5 s instead of freezing a value. Test in Task 3.

---

## Owner check before Task 3 (T-A)

Tasks 1, 2, 5 and 6 need no real data. Tasks 3 and 4 need the owner's `beta3-fixtures.zip`, from `pbpaste | python3 spike/timing_recorder.py --fixtures` (the script was updated separately).

The controller unpacks it to `Packages/DuoCore/Tests/LiveTimingTests/Fixtures/raw/`, which is git-ignored and never committed. Task 3 trims it into committed fixtures:
- `sp26-race/` and `sp26-quali/`: from 2 min before lights out to 12 min after (races), or Q1's first 12 min (qualifying), per topic file;
- `DriverList.json` and `SessionInfo.json` whole;
- `Index-2026.json`, trimmed to the São Paulo meeting plus one other;
- `circuit-14-2026.json`;
- `cardata-head.jsonStream`.

Until T-A arrives, run Tasks 1, 2, 5 and 6, in that order.

### Task 1: LiveTiming target, raw inflate, `.z` payloads, stream lines

**Files:**
- Modify: `Packages/DuoCore/Package.swift`. Add product `LiveTiming`, target `LiveTiming` (dependencies `F1TV`, `Library`), and test target `LiveTimingTests` with `resources: [.copy("Fixtures")]`. Exclude `Fixtures/raw` via `.gitignore`.
- Create:
  - `Packages/DuoCore/Sources/LiveTiming/Inflate.swift`
  - `Packages/DuoCore/Sources/LiveTiming/ZPayload.swift`
  - `Packages/DuoCore/Sources/LiveTiming/StreamLine.swift`
  - `Packages/DuoCore/Sources/LiveTiming/Time.swift`
- Test:
  - `Packages/DuoCore/Tests/LiveTimingTests/InflateTests.swift`
  - `Packages/DuoCore/Tests/LiveTimingTests/StreamLineTests.swift`
  - `Packages/DuoCore/Tests/LiveTimingTests/Fixtures/README.md` (one line: what lives here, and that `raw/` is ignored)

**Interfaces:**
- Produces:
  - `public typealias UTCms = Int64`: milliseconds since 1970 UTC, used everywhere in LiveTiming.
  - `public enum Inflate { public static func raw(_ data: Data) throws -> Data }`: RFC 1951 stored, fixed and dynamic blocks. Throws `InflateError.corrupt` on bad input and never traps.
  - `public enum ZPayload { public static func decode(_ base64: String) throws -> JSONValue }`: base64, then `Inflate.raw`, then `JSONValue.parse`.
  - `public struct StreamLine: Sendable, Equatable { public let offsetMs: Int64; public let json: JSONValue }`
  - `public static func StreamLine.parse(_ line: Substring) -> StreamLine?`: `HH:MM:SS.mmm` then JSON. If the JSON is a string, it is a `.z` payload: keep it as `.string`, and callers decode it.
  - `public static func StreamLine.parseFile(_ data: Data) -> [StreamLine]`: strips a UTF-8 BOM and skips blank or unparseable lines.

- [ ] **Step 1: Write failing tests**
  - In `InflateTests`, embed base64 vectors that you generate once with Python (`zlib.compressobj(level, zlib.DEFLATED, -15)`) for:
    - an empty input;
    - a stored block (level 0, 70 000 bytes, so it spans two stored blocks);
    - fixed Huffman (`"hello hello hello"`);
    - dynamic Huffman (a 20 KB JSON-like text);
    - a back-reference that crosses 32 KB.

    Assert byte-for-byte output. `corruptInputThrows` feeds `[0xFF, 0xFF]` and expects a throw.
  - `zPayloadDecodesJSON`: a base64 raw-deflate of `{"Position":[]}` decodes to that JSON.
  - In `StreamLineTests`:
    - `"00:01:02.345{\"a\":1}"` gives offset `62345` and `a == 1`;
    - a BOM-prefixed file of 3 lines gives 3 lines;
    - a truncated last line (`"00:00:01.000{\"a\""`) is skipped;
    - `"01:00:00.000\"eJw=\""` keeps the string payload.
- [ ] **Step 2: Run** `cd Packages/DuoCore && /opt/swift/usr/bin/swift test --filter LiveTimingTests`. Expected: they fail to compile (missing types).
- [ ] **Step 3: Implement.** The inflater is a straightforward RFC 1951 bit reader with canonical Huffman tables and a 32 KB window. Performance target: a 1 MB stream inflates in under 0.5 s on Linux debug.
- [ ] **Step 4: Run the tests.** Expected: PASS, with 0 warnings in the full `swift test` output.
- [ ] **Step 5: Commit** "LiveTiming: raw inflate, .z payloads, stream lines".

### Task 2: Topic merging and SignalR framing

**Files:**
- Create:
  - `Packages/DuoCore/Sources/LiveTiming/TopicMerge.swift`
  - `Packages/DuoCore/Sources/LiveTiming/SignalR.swift`
- Test:
  - `Packages/DuoCore/Tests/LiveTimingTests/TopicMergeTests.swift`
  - `Packages/DuoCore/Tests/LiveTimingTests/SignalRTests.swift`

**Interfaces:**
- Produces:
  - `public enum TopicMerge { public static func merge(_ base: JSONValue, _ delta: JSONValue) -> JSONValue }`:
    - objects deep-merge;
    - a delta object whose keys are all decimal strings merges into a base array by index (growing it if needed);
    - scalars and arrays in a delta replace;
    - `_kf` and `_deleted` keys follow F1's meaning: `_deleted` removes the listed keys.
  - `public enum SignalR`:
    - `public static let topics: [String]`: the 14 topics in Global Constraints order.
    - `public static func negotiateToken(_ json: JSONValue) -> String?`: `connectionToken`, else `connectionId`.
    - `public static func handshake() -> Data`: `{"protocol":"json","version":1}` + `0x1E`.
    - `public static func subscribe(invocationId: String) -> Data`: `{"type":1,"invocationId":...,"target":"Subscribe","arguments":[topics]}` + `0x1E`.
    - `public static func ping() -> Data`: `{"type":6}` + `0x1E`.
    - `public static func frames(_ data: Data) -> [JSONValue]`: split on `0x1E`; unparseable frames are dropped.
    - `public enum Message: Sendable, Equatable { case feed(topic: String, data: JSONValue, utc: UTCms), snapshot(invocationId: String, state: JSONValue), ping, close(String?), other }`
    - `public static func message(_ json: JSONValue) -> Message`:
      - type 1 with target `feed` and args `[topic, data, iso]` gives `.feed`;
      - type 3 gives `.snapshot`;
      - type 6 gives `.ping`;
      - type 7 gives `.close`.
    - `public static func utc(_ iso: String) -> UTCms?`: ISO 8601 with 0–7 fractional digits and `Z`.

- [ ] **Step 1: Write failing tests**
  - `mergeNestedObjects`: base `{"Lines":{"1":{"Position":"3"}}}` + delta `{"Lines":{"1":{"InPit":true}}}` gives both keys.
  - `mergeKeyedDeltaIntoArray`: base `{"Sectors":[{"Value":""},{"Value":""},{"Value":""}]}` + delta `{"Sectors":{"1":{"Value":"28.1"}}}` changes only index 1.
  - `deltaGrowsArray`: base `[]` + delta `{"2":{"a":1}}` gives an array of 3 with nulls at 0–1.
  - `reconnectSnapshotReplaces`: merging a fresh type 3 snapshot replaces, not doubles. Assert that `TopicState.apply(snapshot:)` (below) resets a topic's state.
  - `SignalRTests`:
    - frames split on `0x1E`, with a trailing partial frame ignored;
    - each message type decodes;
    - `utc("2026-11-08T17:00:01.1234567Z")` gives the expected ms;
    - `subscribe(invocationId:"1")` decodes back to 14 topics.
- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.** Also add `public struct TopicState: Sendable { public private(set) var topics: [String: JSONValue]; public mutating func apply(snapshot: JSONValue); public mutating func apply(topic: String, delta: JSONValue) }`. A snapshot replaces each topic it names.
- [ ] **Step 4: Run the tests.** Expected: PASS with 0 warnings.
- [ ] **Step 5: Commit** "LiveTiming: F1 topic merging and SignalR framing".

### Task 3: Topic parsers and time series (needs T-A)

**Files:**
- Create in `Packages/DuoCore/Sources/LiveTiming/`:
  - `Drivers.swift` (DriverList and SessionInfo)
  - `Positions.swift`
  - `ArchiveClock.swift`
  - `Timing.swift` (TimingData, TimingAppData, LapCount, ExtrapolatedClock, WeatherData)
  - `Flags.swift` (TrackStatus and RaceControlMessages)
  - `CarData.swift`
- Create: the trimmed fixtures under `Tests/LiveTimingTests/Fixtures/sp26-race/` and `sp26-quali/`, plus the trimming script `spike/trim_fixtures.py` (commit it; it reads `raw/` and writes the trimmed set).
- Test:
  - `DriversTests.swift`
  - `PositionsTests.swift`
  - `ArchiveClockTests.swift`
  - `TimingTests.swift`
  - `FlagsTests.swift`
  - `CarDataTests.swift`

**Interfaces:**
- Produces:
  - `public struct DriverInfo: Sendable, Equatable { number: String; tla: String; firstName: String; lastName: String; teamName: String; teamColour: String /* "RRGGBB" */ }`
  - `public enum Drivers { public static func parse(_ json: JSONValue) -> [String: DriverInfo] }`: keyed by racing number string.
  - `public struct TimingSessionInfo: Sendable, Equatable { key: Int?; name: String; type: String; path: String; start: UTCms?; gmtOffsetSeconds: Int; circuitKey: Int?; meetingName: String; year: Int? }`
  - `TimingSessionInfo.parse(_:) -> TimingSessionInfo?`
  - `public struct TrackPoint: Sendable, Equatable { public var x: Double; public var y: Double }`: archive units, 1/10 m.
  - `public struct CarTrack: Sendable { public let number: String; func at(_ t: UTCms) -> TrackPoint?; func atOrFirst(_ t: UTCms) -> TrackPoint?; var first: UTCms?; var last: UTCms? }`:
    - binary search and linear interpolation;
    - nil across gaps over 5000 ms;
    - nil after the last sample.
  - `public struct PositionSeries: Sendable { public let cars: [String: CarTrack]; public static func parse(lines: [StreamLine]) -> PositionSeries }`:
    - decodes `.z`;
    - uses each entry's own `Timestamp` (UTC), not the line offset;
    - skips Status `OffTrack`.
  - `public enum ArchiveClock { public static func streamStart(heartbeat: [StreamLine], positions: [StreamLine]) -> UTCms? }`: the median of `Utc - offset` over the first 50 beats. If the Position-derived start (`Timestamp - offset`, median of its first 50) differs by more than 60 000 ms, it returns the Position one.
  - `public enum SectorPace: Sendable { case empty, set, personalBest, overallBest }`
  - `public struct DriverTimingState: Sendable, Equatable { position: Int?; numberOfLaps: Int?; lastLapMs: Int?; lastLapPace: SectorPace; bestLapMs: Int?; gapToLeader: String; interval: String; sectors: [SectorPace]; inPit: Bool; pitOut: Bool; retired: Bool; stopped: Bool; knockedOut: Bool; lineCrossedAt: UTCms? }`
  - `public struct TimingTimeline: Sendable { public static func build(lines: [StreamLine], streamStart: UTCms) -> TimingTimeline; public func at(_ t: UTCms) -> [String: DriverTimingState]; public var updateTimes: [UTCms] }`:
    - snapshots after each merged delta (TopicMerge);
    - `at` binary-searches the last update ≤ t.
  - `public struct Stint: Sendable, Equatable { compound: String; isNew: Bool; startLaps: Int; totalLaps: Int }`
  - `public struct StintTimeline { build(lines:streamStart:); func at(_ t: UTCms) -> [String: [Stint]] }`
  - `public struct HeaderTimeline { build(lapCount:clock:weather:streamStart:); func at(_ t: UTCms) -> SessionHeader }`
  - `public struct SessionHeader: Sendable, Equatable { lap: Int?; totalLaps: Int?; clockRemaining: Int? /* seconds */; airTemp: Double?; trackTemp: Double?; raining: Bool }`
  - `public enum TrackStatusKind: Sendable { case clear, yellow, safetyCar, safetyCarInThisLap, vsc, vscEnding, red }`
  - `public struct FlagState: Sendable, Equatable { status: TrackStatusKind; yellowSectors: [Int: Int] /* sector → 1 or 2 */; caption: String?; resumesAt: UTCms? }`
  - `public struct TrackFlags { build(trackStatus:raceControl:streamStart:gmtOffsetSeconds:); func at(_ t: UTCms) -> FlagState; var spans: [FlagSpan] /* SC/VSC/red intervals for the timeline and Scrub Deck */ }`
  - `public struct CarSample: Sendable, Equatable { t: UTCms; rpm: Int; speedKmh: Int; gear: Int; throttle: Int; brake: Int; ch45: Int }`
  - `public struct CarDataWindow { public static func parse(lines: [StreamLine]) -> [String: [CarSample]]; public static func readout(_ samples: [CarSample], at t: UTCms) -> (sample: CarSample, stale: Bool)? }`:
    - `stale` when the last sample is more than 5000 ms before t;
    - nil before the first sample.

- [ ] **Step 1: Trim the fixtures** with `spike/trim_fixtures.py` (Python, standard library) and commit the trimmed set, which must be under 3 MB in total. Record in the fixture README which minutes were kept.
- [ ] **Step 2: Write failing tests.** Wherever a test asserts a value read from the fixture, decode it independently with Python in the trimming script and print it. Put the value in the test with a comment naming that check.
  - `driversHas20CarsWithColours`
  - `sessionInfoParsesPathAndCircuitKey` (circuit key 14)
  - `positionsInterpolateBetweenSamples` (the midpoint between two samples is the average)
  - `positionsNilAcrossFiveSecondGap`
  - `offTrackEntriesSkipped`
  - `streamStartIsHeartbeatMedian`
  - `streamStartPositionWinsWhenHeartbeatOffBy33Hours`: shift the heartbeat fixture by +33 h in the test.
  - `timingAtReturnsStateNotLaterThanT`: at lights-out + 5 min, no driver's `numberOfLaps` exceeds the Python-computed value.
  - `timingRetiredCarFlagged`: a synthetic delta, `Retired:true`.
  - `unknownCarNumberTolerated`: timing for car `"99"` with no DriverList entry doesn't crash, and the row keeps its number.
  - `stintsTrackCompoundAndLaps`
  - `headerLapCount`: a race lap at a known time.
  - `weatherOptionalMissingIsNil`
  - `flagsSectorYellowLevel2`, `flagsVscEnding`, `flagsRedCountdown`, `flagsRedUntilGreen`, `flagsSafetyCarInThisLap`: ported from Android's `FlagsTest`. Read the cases with `git show origin/og-android:app/src/test/java/app/apexview/FlagsTest.kt`.
  - `carDataParsesChannels`
  - `carDataTruncatedLastLineDropped`
  - `carDataReadoutStaleAfter5s`
- [ ] **Step 3: Run the tests.** Expected: FAIL.
- [ ] **Step 4: Implement.** Port Android's parsing rules. The rules live in `origin/og-android:app/src/main/java/app/apexview/LiveTiming.kt` and `DriverTiming.kt`; read them with `git show`. Keep the series compact: sorted arrays of samples, with no per-sample dictionaries.
- [ ] **Step 5: Run the tests.** Expected: PASS with 0 warnings.
- [ ] **Step 6: Commit** "LiveTiming: topic parsers, time series, flags, car data".

### Task 4: Session lookup and the archive loader (needs T-A)

**Files:**
- Modify:
  - `Packages/DuoCore/Sources/F1TV/Models.swift`: add `public var timingRef: TimingRef?` to `CatalogItem`, with a default of nil in the init.
  - `Packages/DuoCore/Sources/F1TV/Parsers.swift`: fill it from `emfAttributes`.
  - `Packages/DuoCore/Sources/F1TV/Session.swift`: add `public func bearerToken() -> String?`, which returns the subscription token; it is never logged.
- Create:
  - `Packages/DuoCore/Sources/F1TV/TimingRef.swift`
  - `Packages/DuoCore/Sources/LiveTiming/SessionLookup.swift`
  - `Packages/DuoCore/Sources/LiveTiming/TimingArchive.swift`
- Test:
  - `Tests/F1TVTests/ParsersTests.swift` (add `timingRefFromEmf`)
  - `Tests/LiveTimingTests/SessionLookupTests.swift`
  - `Tests/LiveTimingTests/TimingArchiveTests.swift`

**Interfaces:**
- Produces:
  - `public struct TimingRef: Sendable, Hashable { year: Int; meetingKey: String; sessionKey: String?; circuitKey: Int?; meetingName: String; title: String; start: Date? }`. Fields come from `emfAttributes`: `MeetingKey`, `MeetingSessionKey`, `CircuitKey`, `Meeting_Name`, `sessionStartDate`, and `year`.
  - `public struct ArchiveSession: Sendable, Equatable { key: Int; name: String; type: String; path: String; start: UTCms; gmtOffsetSeconds: Int }`
  - `public enum SessionLookup { public static func match(index: JSONValue, ref: TimingRef, watched: UTCms?) -> ArchiveSession?; public static func probePaths(ref: TimingRef, meetingFolder: String) -> [String] }`. Match order:
    1. the session key;
    2. the meeting plus the longest session name contained in the title;
    3. for a watched live moment, the weekend's session that started within the 4 h before it.
  - `public enum ArchiveFile: Sendable { case data(Data), unavailable(status: Int), failed }`
  - `public actor TimingArchive { public init(http: any HTTPClient, token: @escaping @Sendable () async -> String?, base: URL = URL(string: "https://livetiming.formula1.com/static/")!); public func index(year: Int) async -> JSONValue?; public func file(sessionPath: String, name: String) async -> ArchiveFile; public func range(sessionPath: String, name: String, bytes: ClosedRange<Int>) async -> ArchiveFile }`:
    - sends `Authorization: Bearer`;
    - a 401/403/404 gives `.unavailable`, a network error gives `.failed`;
    - never throws to the caller; never puts the token in a returned value.
  - `public struct LoadedSession: Sendable { info: TimingSessionInfo; drivers: [String: DriverInfo]; streamStart: UTCms; positions: PositionSeries; timing: TimingTimeline; stints: StintTimeline; header: HeaderTimeline; flags: TrackFlags; missing: [String] }`
  - `public static func TimingArchive.load(_ session: ArchiveSession, using archive: TimingArchive) async -> LoadedSession?`:
    - nil only if DriverList, SessionInfo or Position are missing;
    - optional topics go into `missing`.

- [ ] **Step 1: Write failing tests** (with a fake `HTTPClient`, as F1TVTests do):
  - `matchBySessionKey`
  - `matchByMeetingAndLongestName`: "Sprint Qualifying" beats "Qualifying".
  - `matchLiveByStartWindow`
  - `noMatchReturnsNil`
  - `bearerHeaderSent`
  - `forbiddenFileIsUnavailableNotError`: a 403 on WeatherData still loads the session, and `missing == ["WeatherData"]`.
  - `missingPositionGivesNil`
  - `tokenNeverInResult`: a sentinel token string doesn't appear in any `LoadedSession` field or error description.
  - `timingRefFromEmf`: from the existing `archive`/`home` fixtures, `CircuitKey` 14 for Interlagos.
- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.** Do the load's file fetches concurrently with a `TaskGroup`, and parse off the caller's actor.
- [ ] **Step 4: Run the tests.** Expected: PASS with 0 warnings.
- [ ] **Step 5: Commit** "Timing: session lookup and archive loader".

### Task 5: Circuit outline and track geometry

**Files:**
- Create:
  - `Packages/DuoCore/Sources/LiveTiming/Circuit.swift`
  - `Packages/DuoCore/Sources/LiveTiming/TrackGeometry.swift`
- Test:
  - `Tests/LiveTimingTests/CircuitTests.swift`
  - `Tests/LiveTimingTests/TrackGeometryTests.swift`
  - Before T-A, use a small hand-made circuit JSON fixture, `circuit-square.json`: a 1000 × 1000 square with 4 corners. Add `circuit-14-2026.json` assertions after T-A.

**Interfaces:**
- Produces:
  - `public struct Circuit: Sendable, Equatable { outline: [TrackPoint]; corners: [Corner]; marshalSectors: [TrackPoint]; rotationDegrees: Double }`
  - `public struct Corner: Sendable, Equatable { number: Int; letter: String; at: TrackPoint }`
  - `public static func Circuit.parse(_ json: JSONValue) -> Circuit?`: MultiViewer's `x`, `y`, `corners[].number`, `corners[].trackPosition`, `marshalSectors[].trackPosition` and `rotation`.
  - `public static func Circuit.url(circuitKey: Int, year: Int) -> URL`
  - `public struct MapTransform: Sendable { public func point(_ p: TrackPoint) -> CGPoint }`
  - `public struct TrackGeometry: Sendable`:
    - `public init(outline: [TrackPoint])`
    - `public func progress(of p: TrackPoint) -> Double`: 0..<1 along the lap, by projecting onto the nearest segment.
    - `public func fit(in size: CGSize, inset: CGFloat, userTurnDegrees: Double) -> MapTransform`: tries rotations in 1° steps, keeps the one that fills the box best, flips y, then adds the user turn.
    - `public var counterClockwise: Bool`
  - `public enum OutlineTracer { public static func trace(_ track: CarTrack, from: UTCms, to: UTCms) -> [TrackPoint]? }`: Android's rule. A lap closes when it is under 120 000 and over 20 000 units, with sample gaps under 2 s.
  - `public static func OutlineTracer.startFinish(...)`: per Android's `findStartFinish`. Read the signature from `origin/og-android` `LiveTiming.kt`.

- [ ] **Step 1: Write failing tests:**
  - `parsesSquare`
  - `progressAtCornersIsQuarters`: (0,0)→0, (1000,0)→0.25 …
  - `fitKeepsInsideBox`
  - `userTurnRotates90`
  - `yIsFlipped`
  - `traceClosesOneLap`: a synthetic square lap at 4 Hz.
  - `traceRejectsGappyLap`
  - `parsesInterlagos`: after T-A; corners count from the fixture, checked in Python.
- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the tests.** Expected: PASS with 0 warnings.
- [ ] **Step 5: Commit** "LiveTiming: circuit outline and track geometry".

### Task 6: Picture time and timing settings

**Files:**
- Create:
  - `Packages/DuoCore/Sources/LiveTiming/PictureClock.swift`
  - `Packages/DuoCore/Sources/LiveTiming/TimingSettings.swift`
- Test:
  - `Tests/LiveTimingTests/PictureClockTests.swift`
  - `Tests/LiveTimingTests/TimingSettingsTests.swift`

**Interfaces:**
- Produces:
  - `public struct PictureClock: Sendable { public var offsetMs: Int64; public init(offsetMs: Int64 = PictureClock.defaultOffsetMs); public static let defaultOffsetMs: Int64 = -7000; public func time(programDate: Date?, sessionStart: UTCms?, playerSeconds: Double) -> (t: UTCms, estimated: Bool)? }`:
    - with a program date: `programDate + offset`, not estimated;
    - else `sessionStart + playerSeconds*1000 + offset`, estimated;
    - else nil.
  - `public static func PictureClock.trackerDelaySeconds(...)` is not needed. Instead, the tracker delay is an `Int` of half-seconds in settings, applied by the multiview sync (Task 11).
  - `public final class TimingSettings: @unchecked Sendable`, over `any KeyValueStore`, atomic per instance as `MultiviewStore` is:
    - `offsetMs: Int64` (default −7000)
    - `nudge(by seconds: Int)`
    - `resetOffset()`
    - `mapTurn(circuitKey: Int) -> Double` and `setMapTurn(_:circuitKey:)`
    - `pitLossMs(circuitKey:) -> Int64?` and `setPitLossMs(_:circuitKey:)`
    - `panelFrame(_ panel: String, posture: String) -> CGRect?` and `setPanelFrame`
    - `showWholeRace: Bool` (false)
    - `trackerDelayHalfSeconds: Int` (0, clamped 0…40)
    - `hiddenCards: Set<Int>` (channel ids)
    - `speedOnMobileData: Bool` (true)
    - Keys are prefixed `timing.`. A corrupt value falls back to the default, and a failed encode keeps the old value (the beta.2 MultiviewStore rules).

- [ ] **Step 1: Write failing tests:**
  - `programDatePlusOffset`
  - `estimatedWithoutProgramDate`
  - `nilWithoutAnyClock`
  - `nudgeAndReset`: −7000 → −6000 → reset → −7000.
  - `perCircuitTurnAndPitLossPersist`
  - `corruptValuesFallBack`
  - `trackerDelayClamped`
- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the tests.** Expected: PASS with 0 warnings.
- [ ] **Step 5: Commit** "LiveTiming: picture clock and timing settings".

### Task 7: App, build 11 — data on replays: map panel, floating panels, timeline marks

**Files:**
- Modify `project.yml`: link the `LiveTiming` product.
- Create in `DuoApp/Timing/`:
  - `TimingController.swift`
  - `MapPanel.swift`
  - `FloatingPanels.swift`
  - `TimingSettingsSection.swift`
- Modify:
  - `DuoApp/Support/AppModel.swift`: own one `TimingSettings` and a `TimingArchive`; hand the controller to multiview and to the single player.
  - `DuoApp/Multiview/MultiviewView.swift` and `MultiviewControls.swift`: the "Map" button, floating panels, and timeline marks.
  - `DuoApp/Player/PlayerView.swift`: floating panels over the single feed.
  - `DuoApp/Support/SettingsView.swift`: the Track map section.
  - `README.md`: the Privacy section names F1's live timing and MultiViewer's circuit data.
  - `Config/Version.xcconfig`: `BETA_LABEL = beta.3`, `CURRENT_PROJECT_VERSION = 11`.
  - `.gitignore` if needed.

**Interfaces:**
- Consumes:
  - Tasks 1–6;
  - `MultiviewController.player(for:)`, `slots`, `seek(toSeconds:)`, `timeline` and `position`;
  - `PlayerController`'s `AVPlayer`.
- Produces:
  - `@MainActor @Observable final class TimingController`:
    - `init(archive: TimingArchive, settings: TimingSettings, http: any HTTPClient)`
    - `func attach(item: CatalogItem, clock: @escaping @MainActor () -> (programDate: Date?, playerSeconds: Double))`
    - `func detach()`
    - `private(set) var status: TimingStatus` (`.idle`, `.loading`, `.ready`, `.unavailable(String)`, `.estimated`)
    - `private(set) var snapshot: TimingSnapshot` (2 Hz)
    - `func mapState(at t: UTCms) -> MapState` (frame rate)
    - `var pictureTime: UTCms?`
    - `func nudge(_ seconds: Int)`
    - `var timelineMarks: [TimelineMark]`
  - `struct TimingSnapshot`: drivers, flags, header, timing, stints, picture time.
  - `struct MapState`: car dots `{number, tla, colour, point, dimmed, flyingRing}`, flags and caption.
  - `TimelineMark` (`.lightsOut`, `.chequered`, `.band(kind, from, to)`): in player seconds, as Android's `utc − offset − windowStart`.
  - Circuit fetch: MultiViewer through `http`, saved to Caches as `circuits/{key}-{year}.json`. The fallback is a traced outline saved as `circuits/traced-{key}.json`. Retries at 3, 10, 30 and 60 s, then every 60 s, with the status "Map unavailable — trying again…".

- [ ] **Step 1: Implement `TimingController`.**
  - Archive load on attach, through `SessionLookup`, then `TimingArchive.load`.
  - A 2 Hz `Task` publishes snapshots. The map view pulls `mapState(at:)` inside a `TimelineView(.animation)`, which pauses when the view is hidden.
  - Parsing runs off the main actor; only `LoadedSession` (Sendable) comes back.
  - Content with no `timingRef`, or no match, gives `.unavailable("No timing for this session")`, and the data UI hides.
- [ ] **Step 2: `MapPanel`.**
  - Draw outline, corners, start/finish, car dots, flags and the SC dot with `Canvas`, following the spec's Track map section.
  - Header: Map, −1 s / +1 s, ⟲ ⟳.
  - Car dots get 44 pt tap targets. Tapping calls a closure `onCar(String)`, which is a no-op until Task 9.
- [ ] **Step 3: `FloatingPanels`.**
  - The map panel and the tower placeholder are draggable and resizable, at 0.9 opacity, each with a close ✕.
  - Frames are saved per posture through `TimingSettings.setPanelFrame`.
  - The "Map" control toggles both, in multiview and in the single-feed player.
- [ ] **Step 4: Timeline marks** on the multiview scrubber: lights-out, chequered, and SC/VSC/red bands.
- [ ] **Step 5: Settings › Track map.** Offset with "Reset to −7 s", "Show the whole race on the Scrub Deck", and "Speed readouts on mobile data". Then the README Privacy update.
- [ ] **Step 6: Self-check.**
  - Every new file parse-checks: `swiftc -parse`.
  - No `print`, and no token in any string.
  - Bump the build to 11.
- [ ] **Step 7: Commit** "Timing on replays: map, floating panels, timeline marks (build 11)".
- [ ] **Owner check T-B1:**
  - The zero-warnings build.
  - On the São Paulo replay, the map moves with the picture, and −1/+1 s works.
  - Read how many seconds the TRACKER tile runs ahead of the world feed.

### Task 8: Tower, cards, lap states, battle, tap-a-car (DuoCore)

**Files:**
- Create in `Packages/DuoCore/Sources/LiveTiming/`:
  - `LapStates.swift`
  - `Tower.swift`
  - `DriverCard.swift`
  - `Battle.swift`
- Create: `Packages/DuoCore/Sources/Multiview/OnboardPlacement.swift`. Multiview now depends on `LiveTiming`.
- Test:
  - `Tests/LiveTimingTests/TowerTests.swift`
  - `Tests/LiveTimingTests/DriverCardTests.swift`
  - `Tests/LiveTimingTests/BattleTests.swift`
  - `Tests/MultiviewTests/OnboardPlacementTests.swift`

**Interfaces:**
- Produces:
  - `public enum LapState: Sendable { case unknown, pit, outLap, push, coolDown, knockedOut }`, and `LapStates.at(_ t:, timing:, …) -> [String: LapState]`, following Android's rules.
  - `public struct TowerRow: Sendable, Equatable { number; tla; teamColour; position: Int?; lastLap: String /* "1:32.456" or "PIT" */; lastLapPace: SectorPace; gap: String; interval: String; tyre: (compound: Character, laps: Int)?; dimmed: Bool; inKnockoutZone: Bool; battle: Bool }`
  - `public enum Tower { public static func rows(at t: UTCms, session: LoadedSession, favourite: String?) -> [TowerRow] }`:
    - sorted by position, with unknown positions last;
    - in qualifying, the gap header reads "Fastest";
    - the knockout zone is the bottom 5 in Q1 and Q2.
  - `public struct DriverCardModel: Sendable, Equatable { position: Int?; number: String; surname: String; teamColour: String; lapClock: String? /* m:ss.t */; inPit: Bool; flash: (text: String, pace: SectorPace)?; sectors: [SectorPace]; gap: String }`
  - `public static func DriverCardModel.at(_ t:, number:, session:) -> DriverCardModel?`: the flash shows for 6000 ms after `lineCrossedAt`.
  - `public enum Battle { public static func rivals(of number: String, updates: [[String: DriverTimingState]]) -> [String] }`: within 1.0 s in the last two updates.
  - `public enum Placement: Equatable { case makeMain(slot: Int), fill(slot: Int, channel: Channel), replace(slot: Int, channel: Channel), noFreeSpot, noOnboard(Int) }`
  - `public enum OnboardPlacement { public static func place(racingNumber: Int, slots: [Channel?], channels: [Channel], audioChannelId: Int?, lapStates: [String: LapState], placedAt: [Int: Date]) -> Placement }`:
    - in multiview, a car already showing becomes main;
    - otherwise an empty slot is filled;
    - otherwise the least interesting onboard (not audible) is replaced, using the Global Constraints ranking.

- [ ] **Step 1: Write failing tests:**
  - `towerSortedByPosition`
  - `towerPitShowsPIT`
  - `towerQualiKnockoutZoneBottomFive`
  - `towerUnknownCarKeepsNumber`
  - `retiredCarLeavesMap`: `MapState` excludes retired cars. Test the DuoCore helper `MapCars.visible(at:session:)`, which you add here.
  - `cardFlashLasts6s`
  - `cardSectorsColoured`
  - `battleNeedsTwoUpdates`
  - `battleOffWithoutFavourite`
  - Placement tests:
    - `placeMakesMainWhenShowing`
    - `placeFillsEmpty`
    - `placeReplacesPittingOverFlying`
    - `placeNeverReplacesAudible`
    - `placeNeverReplacesWorldFeed`
    - `placeTieOldestFirst`
    - `placeNoOnboardForCar`
    - `placeNoFreeSpot`
- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the tests.** Expected: PASS with 0 warnings.
- [ ] **Step 5: Commit** "LiveTiming: tower, driver cards, lap states, battle; Multiview: onboard placement".

### Task 9: App, build 12 — tower, driver cards and speed, tap a car, header, battle

**Files:**
- Create in `DuoApp/Timing/`:
  - `TowerView.swift`
  - `DriverCardView.swift`
  - `SessionHeaderView.swift`
  - `CarDataLoader.swift`
- Modify:
  - `DuoApp/Timing/TimingController.swift`
  - `DuoApp/Timing/MapPanel.swift`
  - `DuoApp/Timing/FloatingPanels.swift`
  - `DuoApp/Multiview/FeedTile.swift`: the card overlay and the "Hide card" long-press item.
  - `DuoApp/Multiview/MultiviewController.swift`: `func showOnboard(racingNumber: Int)` using `OnboardPlacement`, writing last-used feeds as a swap does.
  - `DuoApp/Player/PlayerController.swift`: in a single feed, switch to that onboard at the same moment.
  - `Config/Version.xcconfig` (build 12).

**Interfaces:**
- Consumes: Task 8.
- Produces:
  - `MultiviewController.showOnboard(racingNumber:) -> String?`: returns the notice text for `.noFreeSpot` or `.noOnboard`.
  - `CarDataLoader`:
    - downloads `CarData.z.jsonStream` in the background, using byte ranges if the T-A probe showed `Accept-Ranges`, else streaming;
    - saves it to Caches as `cardata/{sessionKey}.jsonStream`, deleted after 7 days;
    - pauses on cellular when `speedOnMobileData` is off (`NWPathMonitor` `isExpensive`);
    - exposes `func samples(car: String, around t: UTCms) -> [CarSample]`, which keeps a ±60 s window in memory.

- [ ] **Step 1: TowerView.**
  - The spec's columns, refreshed at 2 Hz from `snapshot`.
  - Tapping a row calls `showOnboard`.
  - The battle glow, and the Battle chip on the map header, which opens the rival's onboard.
- [ ] **Step 2: DriverCardView** over onboard tiles, with the speed readout from `CarDataLoader`: km/h or mph by `Locale.current.measurementSystem`, hidden when stale.
- [ ] **Step 3: SessionHeaderView** at the top of the tower: lap or clock, status, weather.
- [ ] **Step 4: Wire map dot taps** to `showOnboard`. Holding a dot does nothing until Task 15.
- [ ] **Step 5: Self-check** as in Task 7 Step 6, with the build set to 12. Commit "Tower, driver cards, tap a car to open its onboard (build 12)".
- [ ] **Owner check T-B2:** tap a car on the map and on the tower; the card shows the lap time and the speed.

### Task 10: Data layouts in the layout engine

**Files:**
- Modify: `Packages/DuoCore/Sources/Multiview/LayoutEngine.swift`.
- Test: `Tests/MultiviewTests/LayoutEngineTests.swift`, with new tests against the reference screens already in `Fixtures/layouts-reference.json` (flat 951×669 with fold x 456–496; book; laptop 669×951 with fold y 456–496).

**Interfaces:**
- Produces:
  - `public static func optionIDs(posture: Posture, feedCount: Int, hasTiming: Bool) -> [String]`. The existing two-argument form stays and means `hasTiming: false`. Data options are appended after the existing ones:
    - flat: `flat.director`;
    - book: `book.dataScreen`;
    - laptop: `laptop.raceEngineer` and `laptop.scrubDeck`.
    - Exception: laptop with 1 feed and timing gives `["laptop.scrubDeck", "laptop.raceEngineer"]`, with Scrub Deck as the default.
  - `public struct DataRegions: Equatable, Sendable { public var map: CGRect?; public var tower: CGRect?; public var console: CGRect?; public var deck: CGRect? }`
  - `public static func dataRegions(screen: CGSize, foldFrame: CGRect?, posture: Posture, feedCount: Int, optionID: String) -> DataRegions`.
  - `frames(...)` handles the new IDs:
    - **director:** the tower is a full-height right column 200 pt wide. The main feed is the largest 16:9 that fits to its left above a bottom row. The row holds up to 2 feeds and the map, each ≥ 200 pt wide. A fourth feed is hidden.
    - **dataScreen:** the feeds sit in the left half (1 alone, 2 stacked, 3–4 in a 2×2 grid); the map is the top of the right half and the tower the rest.
    - **raceEngineer / scrubDeck:** the main feed sits in the top half; the console or deck is the whole bottom half inside the margins; other feeds are hidden.
  - All of it follows the 6 pt margin and gap and the fold rule.
  - `usableOptionIDs` gains `hasTiming` the same way.

- [ ] **Step 1: Write failing tests:**
  - `directorTowerColumnAndRow`: the tower is 200 wide at the right edge, and the row tiles are ≥ 200 wide.
  - `directorFourthFeedHidden`
  - `dataScreenNothingInFold`
  - `dataScreenFourFeedsGrid219`: the tiles are at least 210 pt wide.
  - `laptopOneFeedDefaultsToScrubDeck`
  - `raceEngineerConsoleIsBottomHalf`
  - `noDataOptionsWithoutTiming`
  - `dataRegionsNeverOverlapTiles`
- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the tests.** Expected: PASS; the existing layout tests still pass.
- [ ] **Step 5: Commit** "LayoutEngine: Director's Desk, book data screen, Race Engineer and Scrub Deck regions".

### Task 11: App, build 13 — Duo data layouts and the tracker delay

**Files:**
- Modify:
  - `DuoApp/Multiview/MultiviewView.swift`: draw the data regions with `MapPanel`, `TowerView`, and placeholder console or deck views labelled "Race Engineer — next build" and "Scrub Deck — next build" (drawn and labelled, per the beta.2 rule).
  - `DuoApp/Multiview/MultiviewController.swift`: `layoutOption` and `cycleLayout` pass `hasTiming`. The sync holds TRACKER and DATA tiles `trackerDelayHalfSeconds × 0.5 s` behind the main feed's moment.
  - `DuoApp/Support/MultiviewSettings.swift`: "Tracker delay" in 0.5 s steps, with the default set from T-B1's measurement.
  - Delete `DuoApp/Multiview/ReservedArea.swift` and its use.
  - `Config/Version.xcconfig` (build 13).

- [ ] **Step 1: Wire `hasTiming = timing.status is ready or estimated`** into layout selection. When timing becomes unavailable, a remembered data layout falls back to the default for that posture.
- [ ] **Step 2: Data regions get views.**
  - Floating panels are hidden while a data layout shows the same panel.
  - Glides between layouts use the beta.2 technique: the same views, frames animated.
- [ ] **Step 3: Tracker delay** in the sync target for channels whose title is TRACKER or DATA. Use `Channel.title` as the feed picker already matches it.
- [ ] **Step 4: Self-check, build 13, commit** "Duo data layouts and tracker delay (build 13)".
- [ ] **Owner check T-B3:** each fold's data layout, glides, tracker delay.

### Task 12: Race calculations: pit circle maths, race lines, lap chart, events, readouts (DuoCore)

**Files:**
- Create in `Packages/DuoCore/Sources/LiveTiming/`:
  - `PitCircle.swift`
  - `RaceLines.swift`
  - `LapChart.swift`
  - `RaceEvents.swift`
  - `Readouts.swift`
- Test:
  - `PitCircleTests.swift`
  - `RaceLinesTests.swift`
  - `LapChartTests.swift`
  - `RaceEventsTests.swift`
  - `ReadoutsTests.swift`

**Interfaces:**
- Produces:
  - `public enum PitCircle`:
    - `static func referenceLapMs(leaderGreenLaps: [Int], typicalLapMs: Int?, lastLapMs: Int?) -> Int?`: the average of the last 5 green laps, else typical, else last.
    - `static func pitLossMs(sessionStops: [Int], storedMs: Int?) -> Int`: median, else stored, else 22000.
    - `static func layout(at t:, session:) -> PitCircleState?`: cars with an angle by time gap to the leader, labels, nil before the leader's first lap.
    - `static func rejoin(car: String, at t:, session:, pitLossMs: Int) -> Rejoin?`, where `Rejoin { position: Int; behind: String?; gapMs: Int }`. The text form is "If HAM stops now, out 2.1 s behind NOR", and the console's form is "Pit now → P7 behind ALO".
  - `public struct RaceLinesModel: Equatable { position: Int?; ahead: (tla: String, gap: String, closing: Bool?)?; behind: (tla: String, gap: String, closing: Bool?)?; tyre: (compound: String, laps: Int)?; pitNow: String?; lastLaps: [(lap: Int, time: String, sectors: [SectorPace])] /* up to 5 */ }`
  - `RaceLines.at(_ t:, car:, session:) -> RaceLinesModel?`: the trend compares the gap now with the gap 3 laps ago.
  - `public struct LapChartRow: Equatable { number: String; positions: [Int?] /* index = lap-1 */ }`
  - `LapChart.rows(until t: UTCms?, session:) -> [LapChartRow]`: nil `t` means the whole race (opt-in only).
  - `public enum RaceEventKind: Equatable { case lightsOut, pit(car: String), safetyCar, vsc, red, fastestLap(car: String), retirement(car: String), chequered }`
  - `public struct RaceEvent: Equatable { t: UTCms; lap: Int?; kind: RaceEventKind; end: UTCms? }`
  - `RaceEvents.list(until t: UTCms?, session:) -> [RaceEvent]`
  - `public struct Readout: Equatable { speedKmh: Int; gear: Int; rpm: Int; throttle: Int; brake: Int; aero: Bool?; stale: Bool }`
  - `Readouts.at(_ t:, samples:, channel45: Channel45Meaning) -> Readout?`, where `Channel45Meaning` is `.drs`, `.activeAero` or `.absent`. Decide it from the São Paulo 2026 fixture: if values change when a car is on a straight, it is `.activeAero` (label "Aero"); if it is constant, `.absent` (no light). Record the evidence in a test comment.

- [ ] **Step 1: Write failing tests:**
  - `referenceUsesLastFiveGreen`
  - `referenceFallsBackToTypicalThenLast`: the 0.98 joining-late case.
  - `pitLossMedianThenStoredThen22s`
  - `circleNilBeforeFirstLap`
  - `rejoinTextFormat`
  - `raceLinesTrendClosing`
  - `lastFiveLapsWithSectors`
  - `lapChartCutAtPictureTime`: no lap beyond the leader's lap at t.
  - `lapChartWholeRaceOptIn`
  - `eventsCutAtPictureTime`
  - `eventsIncludeSCBandWithEnd`
  - `readoutStale`
  - `channel45MeaningFromFixture`
- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.** Port from `origin/og-android` `PitCircle.kt` and `PitWindow.kt`.
- [ ] **Step 4: Run the tests.** Expected: PASS with 0 warnings.
- [ ] **Step 5: Commit** "LiveTiming: pit circle maths, race lines, lap chart, race events, readouts".

### Task 13: App, build 14 — Race Engineer and Scrub Deck

**Files:**
- Create:
  - `DuoApp/Timing/RaceEngineerConsole.swift`
  - `DuoApp/Timing/ScrubDeck.swift`
- Modify:
  - `DuoApp/Multiview/MultiviewView.swift`: replace the Task 11 placeholders.
  - `DuoApp/Multiview/MultiviewController.swift`: the Race Engineer top-onboard choice: the main feed if it's an onboard, else your driver's onboard, else the first onboard. It never moves the sound. With none, it shows "Tap a car to pick an onboard".
  - `Config/Version.xcconfig` (build 14).

- [ ] **Step 1: RaceEngineerConsole**, following the spec's sketch:
  - the readouts row from `Readouts` and `CarDataLoader`;
  - the mini map, with only this car highlighted;
  - the race lines;
  - the last 5 laps;
  - the drawn and labelled "Saved for beta.4: team radio" spot.

  Tapping the ahead or behind line calls `showOnboard`, and that car becomes the top onboard.
- [ ] **Step 2: ScrubDeck**, the event strip and the lap chart (races and sprints only; other sessions show the strip by time):
  - Your driver is highlighted; the future is drawn as an empty "fog" unless `showWholeRace` is on.
  - Dragging calls `controller.seek(toSeconds:)` with a time readout.
  - Tapping a marker seeks to 5 s before it.
  - Tapping a line highlights it and offers "Open onboard".

  Map times to player seconds with the inverse of picture time, as the timeline marks do.
- [ ] **Step 3: Self-check, build 14, commit** "Race Engineer and Scrub Deck (build 14)".
- [ ] **Owner check T-B4:** the exit test's laptop part.

### Task 14: Live: recording format, live feed assembly, archive top-up, next-live rule (DuoCore)

**Files:**
- Create in `Packages/DuoCore/Sources/LiveTiming/`:
  - `LiveRecording.swift`
  - `LiveFeed.swift`
  - `Backfill.swift`
- Create: `Packages/DuoCore/Sources/F1TV/NextLive.swift`.
- Test:
  - `LiveRecordingTests.swift`
  - `LiveFeedTests.swift`
  - `BackfillTests.swift`
  - `Tests/F1TVTests/NextLiveTests.swift`

**Interfaces:**
- Produces:
  - `public struct RecordedMessage: Equatable, Sendable { topic: String; utc: UTCms; opening: Bool; json: JSONValue }`
  - `public enum LiveRecording { static let excluded: Set<String> = ["CarData.z", "Heartbeat"]; static func line(_ m: RecordedMessage) -> String /* topic\tutc\t0|1\tjson\n */; static func header(sessionPath: String) -> String /* "#session\t<path>\n" */; static func read(_ data: Data) -> (sessionPath: String?, messages: [RecordedMessage]) }`
  - `public struct LiveFeed: Sendable`, which turns snapshot and delta messages into per-topic `[StreamLine]` relative to a stream start, so the archive parsers (Task 3) build the same timelines:
    - `mutating func apply(_ m: RecordedMessage)`
    - `func session(drivers:info:) -> LoadedSession?`
    - A new opening snapshot after a reconnect replaces topic state and does not duplicate history lines.
  - `public enum Backfill { static let spacing: Duration = .seconds(120); static let maxAttempts = 180; static func isComplete(archiveLast: UTCms, joinedAt: UTCms) -> Bool /* within 30 000 ms */ }`
  - `public enum NextLive { static func pick(live: [CatalogItem], onScreen: Int, liveAtStart: Set<Int>, declined: Set<Int>, watchedEnded: Bool) -> CatalogItem? }`: the first live item that is not on screen and not declined, and is either new since opening or, once the watched broadcast has ended, any live item.

- [ ] **Step 1: Write failing tests:**
  - `recordingRoundTrip`
  - `recordingExcludesCarDataAndHeartbeat`
  - `recordingAppendsAfterReopen`: the same session path with no second header.
  - `newSessionStartsFresh`
  - `liveFeedMatchesArchiveParsers`: feed the São Paulo archive lines in as recorded messages; `TimingTimeline` at a time t equals the archive-built one.
  - `reconnectSnapshotNoDuplicates`: no doubled laps or stops.
  - `backfillCompleteWithin30s`
  - `nextLivePicksNewSinceOpening`
  - `nextLiveSkipsDeclined`
  - `nextLiveAnyOnceEnded`
- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement**, porting `origin/og-android` `LiveRecorder.kt`, `LiveFeed.kt` and `AppState.pickNextLive`.
- [ ] **Step 4: Run the tests.** Expected: PASS with 0 warnings.
- [ ] **Step 5: Commit** "LiveTiming: live recording, live feed assembly, backfill; next live programme rule".

### Task 15: App, build 15 — live connection, recorder, top-up, next-live prompt, pit circle view

**Files:**
- Create in `DuoApp/Timing/`:
  - `LiveConnection.swift`
  - `LiveRecorder.swift`
  - `PitCircleView.swift`
  - `NextLivePrompt.swift`
- Modify:
  - `DuoApp/Timing/TimingController.swift`: the live mode.
  - `DuoApp/Timing/MapPanel.swift`: the Map / Pit circle switch, and holding a car for its pit window.
  - `DuoApp/Multiview/MultiviewView.swift` and `DuoApp/Player/PlayerView.swift`: the next-live prompt, hidden in PiP.
  - `DuoApp/Support/AppModel.swift`: the 60 s live-now check, only while a live session is watched.
  - `Config/Version.xcconfig` (build 15).

**Interfaces:**
- Produces:
  - `actor LiveConnection`, shared and reference-counted:
    - `func listen() -> AsyncStream<RecordedMessage>`, which replays the current session's recording first;
    - negotiate (POST `/signalrcore/negotiate?negotiateVersion=1`, keeping the sticky cookie);
    - `URLSessionWebSocketTask` to `wss://livetiming.formula1.com/signalrcore?id=<token>`, sending the Bearer header and the Android user agent the multiview already uses;
    - handshake, then subscribe;
    - ping every 15 s; reconnect after 5 s, with "Live timing dropped — reconnecting…";
    - the token is never logged.
  - `LiveRecorder`:
    - appends `LiveRecording.line`s to Caches as `live/{sessionKey}.txt`, flushed every 2 s;
    - deletes files older than 7 days at launch.
  - `TimingController` live mode:
    - `LiveFeed` gives a `LoadedSession`, refreshed at 2 Hz;
    - the status lines from Global Constraints;
    - the archive top-up with the `Backfill` schedule.

- [ ] **Step 1: LiveConnection and LiveRecorder.**
- [ ] **Step 2: The TimingController live mode** for live items (`CatalogItem.isLive`). A rewind reads the recording.
- [ ] **Step 3: PitCircleView**, following the spec's Pit circle section:
  - gap labels with a toggle;
  - tap or hold a car for the pit window text;
  - "The circle starts once the leader has finished a lap.";
  - store the session's measured pit loss per circuit in `TimingSettings`.
- [ ] **Step 4: NextLivePrompt** with "Switch" and "Not now". "Switch" opens the item with the same multiview or single choice.
- [ ] **Step 5: Self-check, build 15, commit** "Live timing, recording, pit circle, next live programme (build 15)".
- [ ] **Owner check T-C** (the first live weekend after this build) and **T-D**, the exit test.

## After Task 15 (controller)

- CHANGELOG: a beta.3 section with an "Untested — check later" list.
- README status; roadmap rows for 0.95, 0.96–0.98 pit circle, 0.99.4, and ideas #11, #19 and #20 marked as landed.
- Final whole-branch review, privacy scan, release text, as for beta.2.
