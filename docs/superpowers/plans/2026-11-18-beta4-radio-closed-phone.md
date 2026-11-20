# v1.0-beta.4 — Radio and the closed phone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the drivers' voices and make the closed phone useful:
- team radio by lap, in step with the picture, with transcripts made on the phone;
- the closed phone's three pages (Picture, Radio Scanner, Gap Thermometer) with Unfold to See;
- a small haptic vocabulary for flags and your driver;
- two book layouts (Onboard and Logbook, Ear-Matched Rivals) and the hinge as an audio mixer.

**Architecture:**
- **Logic in DuoCore**, Foundation only, tested on Linux:
  - radio clips, lap labels and the transcription queue (`LiveTiming`);
  - the event detector and haptic schedule shared by haptics and Unfold to See (`LiveTiming`);
  - the gap pair and the logbook model (`LiveTiming`);
  - closed pages, the mixer curve, beta.4 settings and two book layouts (`Multiview`).
- **App.** A `@MainActor` `RadioController` per watched session sits beside `TimingController`. It reads the loaded session and picture time, downloads clips, plays them through `AVAudioEngine` and ducks the feeds. Around it:
  - a `Transcriber` actor around `SpeechAnalyzer`;
  - a `HapticsPlayer` (Core Haptics);
  - a `CompanionController` that runs the event detector for cards and haptics;
  - SwiftUI views for each surface.

**Tech Stack:**
- Swift 6 with strict concurrency, SwiftUI and UIKit;
- AVFoundation (`AVAudioEngine`, `AVAudioPlayerNode`, `AVAudioUnitTimePitch`, `AVAudioSession`);
- Speech (`SpeechAnalyzer`, `SpeechTranscriber`, `DictationTranscriber`, `SFSpeechRecognizer`);
- Core Haptics;
- XcodeGen;
- Swift Testing in DuoCore (`/opt/swift/usr/bin/swift test` from `Packages/DuoCore`).

**Spec:** `docs/superpowers/specs/2026-11-18-beta4-radio-closed-phone-design.md` (owner-approved 2026-11-18; all ten questions answered "agree", so each recommendation is the decision). Read it with this plan; it is the authority. The beta.3 rulings in `docs/superpowers/notes/2026-11-17-beta3-rulings.md` still apply.

## Changes on `main` since this plan was written (2026-11-19, build 16 fixes from the Duo)

These landed during the weekend's device checks. Tasks 8–14 build on them and must keep them:

- **Live plays through FairPlay** (6564599). `PlayerController.begin(url:license:startAt:date:)`
  takes the PLAY reply's licence URL when `PlayInfo.isFairPlay`; a `FairPlayKeys`
  (`DuoApp/Player/FairPlayKeys.swift`, an `AVContentKeySession`) takes the asset before the item
  exists and lives as long as the playback; `teardownPlayback()` stops it. DuoCore: `FairPlay`,
  `FairPlayError`, `F1TVSession.fairPlayCertificate()` and `fairPlayLicense(spc:keyURI:licenseURL:)`,
  `HTTPRequest.body`, `PlayInfo.drmType`. Task 10's `PlaybackHost` conformance and anything that
  rebuilds the player item must go through `begin`, never `AVPlayerItem(url:)` directly.
- **Each feed plays as F1 TV's own link says** (785255d): PLAY takes `Channel.playChannelId`
  (nil for the main INTERNATIONAL feed of older races), while `Channel.id` stays the feed's
  identity. Anything that sends PLAY for a channel uses `playChannelId`.
- **Multiview's "Watch the main feed"** (d898169, 6564599): `MultiviewController.mainFeedFallback`
  is set when F1 TV has no multiview (`.multiviewUnavailable`) or sends it protected
  (`.protectedContent`); `AppModel.watchMainFeed()` closes the multiview, waits for its stop and
  starts the single-feed player. `MultiviewController.waitForStop()` exists for that.
- **Errors say why** (f273cb5): `F1TVError.detail` carries F1 TV's status and own words.
- **The live start choice hangs on the button that asked** (3073622): `DetailView.asksStart`.
- **Settings › About shows the source commit** (25fd63e): `DUO_COMMIT` from the install script.
- **Polish moved forward (2026-11-19, owner):** the opening screen (`DuoApp/Opening/OpeningView.swift`,
  shown over `RootView` from `DuoApp.swift`; the launch screen is plain `LaunchBackground`) and the
  Apple design pass q1, q2, q3, q5, q6, q7, one commit each. Glass over video goes through
  `View.videoGlass(in:)` (Theme.swift); floating panels use `.glassEffect(.regular, in:)`;
  prominent buttons are `.glassProminent` with `.tint(Theme.accent)`. New multiview or closed-phone
  chrome in Tasks 8–14 uses the same styles, not black-opacity boxes. Tower rows and canvas labels
  scale with `@ScaledMetric` (the draw functions take `textScale`). q8 and q9 (touch areas,
  VoiceOver for map and pit circle) wait for the laptop-pose tap and drag fix. Simulator build:
  0 warnings. `scripts/check-build.sh` builds for the simulator without the phone.

**Open (decide after the FP1 multiview probe, owner-run):** asked the app's multiview way
(Android-style, `WEB_DASH`), F1 TV sends live multiview as Widevine, which iOS cannot play; asked
Safari-style it sends FairPlay, but for replays only one feed. Until the probe shows the
Safari-style request returns all live feeds, **live sessions play in the single-feed player
only**. That affects the beta.4 surfaces drawn in `MultiviewView` (Task 12's closed pager and
Unfold to See, Task 14's book layouts): during a live session they are not reachable. Ruling:
no task changes now; if the probe shows all feeds (FairPlay), add a task before Task 12 for
FairPlay multiview (one key session for all the feeds' assets); if not, ask the owner whether the
closed pages should also come to the single-feed player.

**FP1 probe, shape matrix (owner's Mac, 2026-11-19 16:33 PST, FP1 1000010435, player_tm):** every
Safari-style shape (WEB_HLS and WEB_DASH, with or without channelId) answered one SWITCHER feed in
FairPlay (`CMAFFP`); both Android-style shapes answered all 26 feeds (`MULTI`) in Widevine
(`CMAFWV`). So one live multiview request never gives more than one feed iOS can play. Still open:
probes A, B and C (a separate Safari-style PLAY per channel, side by side), which decide whether
live multiview can be built from separate FairPlay feeds. Until then the ruling above stands.

**FP1 probes A, B, C (same evening, ~16:45 PST):** C opened separate Safari-style multiview
sessions for 1033, 1003 and 1004 at the same time, all still serving after 20 s; B's separate
single-feed (player_bm) requests both played and kept playing, with different links, but the
answer doesn't name the channel, so it is not yet shown that each link is the feed asked for; A
stopped at 1025. 1025 (INTERNATIONAL) answered 404 when asked by channelId in A and C, matching
the no-channelId rule (`Channel.playChannelId`). Next check (owner, in the app, live): pick a
driver's onboard from the session page in the single-feed player and see that it is that
driver's onboard. If it is, add the FairPlay multiview task (separate PLAY and key session per
feed) before Task 12.

**Confirmed (owner, FP1, 2026-11-19):** picking a driver's onboard on the live session page played
that driver's onboard, live. **Ruling:** add a task before Task 12, "Live multiview through
FairPlay": for a live session, open each feed with its own Safari-style single PLAY
(`playChannelId`, so INTERNATIONAL goes without a channelId) and its own `FairPlayKeys` session,
instead of the one multiview PLAY; keep "Watch the main feed" as the fallback when any feed
fails. Sized and written into this plan on Sunday, before Task 8 starts. Cost if wrong: one
task's work, and live keeps the single-feed fallback it has now.

## Global Constraints

**Weekend freeze (Las Vegas, build 16 under live test)**
- The owner tests build 16 live from FP1, Thu 19 Nov 16:30 PST, to the race, Sat 21 Nov 20:00 PST. The phone stays on the race build (commit `cc569d2`) until after the race; new work on `main` is only built in the Mac simulator until then.
- **Tasks 1–7 may merge to `main` at any time.** They must be purely additive:
  - new files and new types only;
  - no new cases on existing public enums;
  - no new stored properties on existing types unless they have defaults;
  - no change to `TimingArchive.topics(for:)`, `LiveFeed`, `LayoutEngine.optionIDs` or anything else the app reads;
  - every existing test passes unmodified;
  - the build 16 harness's pure app files (see Checking app code) still typecheck against the branch.
- **Tasks 8–14 merge only after the race (Sun 22 Nov).** They change `DuoApp/`, `Config/`, `project.yml`, `DuoApp/Info.plist`, the README's app claims, the app's loading or its layout options. They may be written and reviewed on branches before then.
- If a hotfix to build 16 is needed during the weekend, it goes first. Any beta.4 branch is then rebased onto it.

**Platform and language**
- iOS 27.1 deployment target.
- Swift 6 language mode with `SWIFT_STRICT_CONCURRENCY: complete`.
- App types that touch UI, AVFoundation, Speech or Core Haptics are `@MainActor`, except the `Transcriber` actor.
- Callbacks from AVFoundation, Speech, Core Haptics or URLSession are `@Sendable` and hop to the main actor with plain values.

**DuoCore and dependencies**
- DuoCore imports Foundation only; the existing conditional `import CoreGraphics` in `LayoutEngine.swift` stays.
- No third-party dependencies anywhere.
- New app frameworks (app only): Speech, Core Haptics, `AVAudioEngine`.

**Hosts and privacy**
- No new hosts. Clip audio comes from `https://livetiming.formula1.com/static/` + SessionInfo `Path` + the capture's `Path` (`RadioClips.audioURL`).
- A clip is fetched first **without** the F1 TV sign-in. On 401/403, it is fetched once more with `Authorization: Bearer`, only to that URL. Nothing else gets the token.
- A refusal never signs the user out.
- Clips are cached in `Caches/radio/{sessionKey}/` and deleted after 7 days.
- Transcripts are stored per session in `Caches/radio/{sessionKey}/transcripts.json`, cleared with the clips.
- No server speech service and no upload. No microphone. Tokens, cookies and signed URLs are never logged, printed, put in errors or files, or committed.
- No radio audio (mp3) is ever committed. Tests use timing lines only.

**Picture time** (beta.3's rules hold)
- A clip exists once picture time ≥ its `Utc`. Before that it is not listed, counted, badged, carded, ticked, transcribed for display, or played.
- "Show the whole race" (`TimingSettings.showWholeRace`) also shows the whole radio list (`visible(at: nil)`).
- Rewinding past a playing clip's `Utc` stops it.
- Transcription may run up to 2 min ahead of picture time. Its text shows only when its clip does.
- Cards and haptics fire only when normal play crosses the event. They never fire on data arriving, a seek or a scrub, and not for 2 s of picture time after a seek.

**Numbers**
- Transcription:
  - one clip at a time, nearest picture time first, up to 120 000 ms ahead;
  - a clip not done in 45 s is skipped;
  - three failures in a row → wait 2 min;
  - results kept by clip path.
- Event cards: older cards stack ("+2"). The jump goes to 5 s before the event by default ("Rewind when opening": 3, 5, 10 or 15 s). The "Back to where you were" chip lasts 15 s.
- Haptics: at most one every 2 s (wall clock). Priority: red, safety car, VSC, chequered, yellow, pits, purple. Yellow at most once per 60 s of picture time.
- Gap colour: cool blue at ≥ 3000 ms, amber at 2000 ms, red at ≤ 1000 ms. The Thermometer refreshes at 2 Hz.
- Hinge mixer:
  - 70° = all radio, 160° = all commentary, linear between;
  - smoothing: exponential, factor 0.3 per reading;
  - 5° dead zone (hysteresis);
  - the mix bar shows for 2 s.
- Clip ducking: feeds silent while a clip plays (Android `RADIO_DUCK = 0`), unless the mixer is on.

**Copy** (verbatim from the spec; beta.1–beta.3 copy stays)
- Radio panel:
  - "Team radio", "Hide team radio", "Radio";
  - "Radio shows up here as it happens.", "No radio from {CODE} yet.";
  - "Transcribing…", "(no words recognised)", "Getting the speech model ready…";
  - "Transcripts aren't available on this iPhone — clips still play";
  - "Couldn't load this clip", "Couldn't play that radio clip";
  - "Allow speech recognition in Settings to see transcripts".
- Info.plist speech reason: "Team radio clips are turned into text on this iPhone. The app never listens to you."
- Closed:
  - "Radio Scanner", "No radio from {CODE} yet. Swipe for another driver.", "New radio — tap to play";
  - "Swipe up or down for Picture, Radio and Gap";
  - "Gap Thermometer", "The Gap Thermometer works in races and sprints.", "Gaps start after the first lap.";
  - "{CODE} in the pits", "{CODE} is out — swipe for another pair".
- Cards:
  - "Yellow flag · Lap 23", "Safety car · Lap 23", "Virtual safety car · Lap 23", "Red flag";
  - "{CODE} pits · Lap 31", "{CODE} on the radio · Lap 31";
  - "{CODE} passes {CODE2} for P4", "{CODE2} passes {CODE} for P4";
  - "{CODE} is out", "Chequered flag";
  - each with "Unfold to see";
  - after the jump: "Rewound to {card title} — Back to where you were".
- Haptics:
  - "Haptics", and the events "Yellow flag", "Safety car", "Virtual safety car", "Red flag", "Your driver pits", "Purple sector", "Chequered flag";
  - "Feel it";
  - footer "Haptics follow the picture, so they never come before what you see.";
  - "Show haptics on screen" draws "Haptic: Yellow flag".
- Mixer: "Hinge mixer — fold to hear more radio, open for more commentary", "Commentary ◀━━●━━▶ Radio", "No radio to mix yet".
- Book:
  - "Radio", "Laps", "Stops", "Race control";
  - "No stops yet.", "Nothing from race control about {CODE}.", "Tap a car to pick an onboard";
  - "Left ear · {CODE}", "Right ear · {CODE}", "Put on headphones to hear each driver in one ear".
- Settings:
  - "Transcripts", "Play radio as it happens", "Hinge mixer";
  - "Event cards" with "Flags", "My driver's stops and radio", "My driver's position changes", "Chequered flag";
  - "Rewind when opening";
  - "Transcribe a test clip" (Debug; removed before release).

**Lap labels** (formatting lives in the app; rulings for what the spec leaves open)
- `.lap(n)` → "Lap n"; `.beforeStart` → "Before the start"; `.afterFlag` → "After the flag".
- `.qualifying(part: 2, remainingMs: 492_000)` → "Q2 · 8:12 left". A nil part → "Qualifying"; a nil remaining → "Q2".
- `.practice(elapsedMs:)` → "m:ss", or "h:mm:ss" from an hour.
- `.unknown` → no label (no header, nothing on the row).
- The Radio list shows a header whenever a row's label differs from the row above. Lapped drivers can repeat a header; that is accepted (Android parity: the driver's own lap).

**Screens**
- Inner screen 951×669 pt flat, fold at x 456–496; 669×951 turned for laptop.
- **The outer screen is 466 × 678 pt** (portrait), measured by the owner on 2026-11-18 in Settings › Fold. Closed layouts still take their size from the view (`GeometryReader`) and scale type from it; the measured size is for mockups and checks, not hard-coded in the app.
- The closed layout applies wherever the multiview's is used (narrower than 600 pt, or posture closed), so also on any iPhone.

**Build, fixtures, commits**
- `Config/Version.xcconfig`: `BETA_LABEL = beta.4` from Task 10. `CURRENT_PROJECT_VERSION` goes 17, 18, 19, 20, 21 at Tasks 10, 11, 12, 13, 14; build 22 is the final fixes.
- **Fixtures** are timing lines trimmed by `spike/trim_fixtures.py` from the owner's raw data in the **main checkout's** `spike/beta3-fixtures/`, which git ignores.
  - A worktree has no copy. The controller gives the implementer that absolute path, or copies the folder into the worktree's `spike/` (it stays ignored).
  - If the folder is missing, the task stops and reports BLOCKED. Never invent fixture data.
  - The committed total stays under 3.3 MB.
- Commits end with the session's attribution lines. Push to `main` only.
- No AI model names in code, docs or commit bodies; the attribution trailer is the only exception.
- Every build adds a CHANGELOG build section with an "Untested — check later" list (beta.3's format).

**Checking app code** (agents cannot compile the app)
- **`swiftc -parse`** on every new or changed app file: syntax only.
- **Linux typecheck harness** for the app's pure files (no SwiftUI, AVFoundation, Speech or Core Haptics imports), as for builds 11–16:
  - a scratch SwiftPM package in the scratchpad, outside the repo, named `apptc17`, `apptc18`… per build;
  - a `CoreGraphics` stub target (the `CGFloat`, `CGPoint`, `CGSize` and `CGRect` the files use);
  - an `AppPure` target holding copies of the listed app files, depending on the branch's `Packages/DuoCore` by path, built with `-warnings-as-errors`;
  - a `Runner` executable whose named checks print `PASS <name>` or `FAIL <name>`, and `DONE`.
  - Each app task lists its harness files and checks. The harness is never committed.
- **Owner's build:** zero warnings and the task's owner check. Anything unchecked goes in the CHANGELOG "Untested — check later" list.
- Pure app files must not import SwiftUI, so the harness can take them. Put formatting, row building, copy and decisions there.

**Real-device checks (the iPhone Duo arrived 2026-11-18)**
- The feel of haptics, the outer screen, the hinge mixer's feel, transcription speed and a real unfold are owner checks on the build that adds each. They are not deferred to beta.7.

## Review Focus

1. **A seek, scrub or rewind across a clip or an event.**
   - Nothing fires: no card, haptic or auto-play.
   - Rewinding past a playing clip's `Utc` stops it, and later clips leave every list, count and tick.
   - Tests: Task 2 (`seekAcrossYellowFiresNothing`, `seekAcrossClipDoesNotAutoPlay`, `quietTwoSecondsAfterSeek`, `backwardOrLongStepIsASeek`); Task 10 harness (`rewindStopsPlayingClip`, `ticksOnlyUpToPictureTime`).
2. **Clip audio refused or failing.**
   - On 401/403 the clip is fetched once more with the token, to the same URL only.
   - A second refusal or a network error gives "Couldn't load this clip".
   - Nobody is signed out, the video keeps playing, and the token never appears in errors or file names.
   - Test: Task 10 harness (`clipRefusedThenTokenOnce`, `tokenOnlyToClipURL`, `refusedTwiceCouldntLoad`, `cacheNameHasNoToken`).
3. **No favourite driver, a driver with no radio, or a session with no radio at all.**
   - Each surface shows its empty state.
   - The Scanner defaults to the leader, and the Gap pair to P1 and P2.
   - Your-driver cards and haptics stay off.
   - The order the Scanner swipes through never reveals who has radio.
   - Tests: Task 2 (`noFavouriteNoDriverEvents`); Task 3 (`defaultPairWithoutFavourite`); Task 4 (`defaultDriverIsLeaderWithoutFavourite`, `orderIsRacePositionNotRadio`); Task 10 harness (`emptyRadioCopy`).
4. **Transcription unavailable, failing or slow.**
   - Clips still play.
   - A 45 s timeout skips the clip; three failures in a row wait 2 min; an empty result stores "(no words recognised)".
   - A phone without an on-device engine shows the "aren't available" line, never a server.
   - Tests: Task 1 (`queueTimeoutSkips`, `threeFailuresWaitTwoMinutes`, `noWordsStored`); Task 11 harness (`unavailableShowsNote`, `permissionDeniedNote`).
5. **Duplicate clips after a live reconnect or an archive top-up.** The same path is listed, ticked, carded and transcribed once. Test: Task 8 (`liveReconnectAndTopUpKeepClipsOnce`).

---

## Pre-freeze tasks (DuoCore only; may merge any time)

Tasks 1, 2 and 5 wait for the radio groundwork, being built by another worker, to reach `main` (they read `RadioClips`). Task 6 needs Task 2's types. Tasks 3, 4 and 7 need nothing and can start at once.

### Task 1: Radio logic (groundwork, landing separately): verify and complete

**Files:**
- Check, and complete where short: `Packages/DuoCore/Sources/LiveTiming/Radio.swift` (groundwork).
- Create, unless the groundwork already has it: `Packages/DuoCore/Sources/LiveTiming/TranscriptionQueue.swift`.
- Modify: `spike/trim_fixtures.py`, which writes two new slices:
  - `sp26-race-long/`: the race's whole TeamRadio, TrackStatus, LapCount, SessionStatus, RaceControlMessages, DriverList, SessionInfo and Heartbeat. Also TimingData reduced to `NumberOfLaps`, `Position`, `InPit`, `PitOut`, `Retired` and `Stopped` per car (measured: about 104 KB).
  - `sp26-quali-long/`: qualifying's whole TeamRadio, TrackStatus, SessionStatus, RaceControlMessages, ExtrapolatedClock, DriverList, SessionInfo and Heartbeat.
- Modify: `Packages/DuoCore/Tests/LiveTimingTests/Fixtures/README.md` (the two slices; the cap is now 3.3 MB).
- Test: `Packages/DuoCore/Tests/LiveTimingTests/RadioTests.swift` (groundwork); create `RadioRaceTests.swift` and `TranscriptionQueueTests.swift`.

**Interfaces** (confirm against the merged code; the controller fixes later tasks' Consumes lines to match):
- Produces (groundwork):
  - `public struct RadioFileTime: Sendable, Hashable`.
  - `public struct RadioClip: Sendable, Hashable { utc: UTCms; racingNumber: String; path: String; fileTime: RadioFileTime?; init(utc:racingNumber:path:); func fileUtc(gmtOffsetSeconds:) -> UTCms? }`.
  - `public struct RadioClips: Sendable, Equatable`:
    - `init()`, `init(lines: [StreamLine])`, `mutating func add(_ line: StreamLine)` (duplicates by path dropped);
    - `var all: [RadioClip]` (oldest `Utc` first);
    - `func visible(at t: UTCms?, driver: String? = nil) -> [RadioClip]`;
    - `static let audioBase`, `static func audioURL(sessionPath: String, clipPath: String) -> URL?`.
  - `public enum RadioLapLabel: Sendable, Equatable { case beforeStart, lap(Int), afterFlag, qualifying(part: Int?, remainingMs: Int?), practice(elapsedMs: Int), unknown }`.
  - `public static func RadioClips.lapLabel(for clip: RadioClip, in session: LoadedSession) -> RadioLapLabel`.
- Produces (expected; write it if missing):
  - `public enum TranscriptResult: Sendable, Equatable, Codable { case text(String), noWords }`.
  - `public struct TranscriptionQueue: Sendable`:
    - statics: `lookaheadMs: Int64 = 120_000`, `timeout: TimeInterval = 45`, `failuresBeforePause = 3`, `pause: TimeInterval = 120`;
    - `init(results: [String: TranscriptResult] = [:])`;
    - `mutating func next(clips: [RadioClip], pictureTime: UTCms?, now: TimeInterval) -> RadioClip?`: nil while one is running, while paused, or when nothing is left. Otherwise the not-yet-done, not-failed clip with `utc ≤ t + lookahead` nearest to `t` (ties: earlier). A nil `t` means any clip, oldest first;
    - `mutating func finished(path: String, result: TranscriptResult)`;
    - `mutating func failed(path: String, now: TimeInterval)`: a timeout counts as a failure;
    - `var results: [String: TranscriptResult]`;
    - `var running: String?`.

- [ ] **Step 1: Diff the merged groundwork against the spec's Radio bullets** (parser list/keyed/day prefix/duplicates, audio URL, visible at a time, driver filter, lap labels, queue). List each gap in the task report. The steps below fill them.
- [ ] **Step 2: Trim the long slices** with `spike/trim_fixtures.py` (raw folder: see Global Constraints). The script prints a `check:` line for every value the tests below assert. Commit the slices.
- [ ] **Step 3: Write the failing tests** (`RadioRaceTests`, on `sp26-race-long`, plus the quali slice):
  - `wholeRaceHas30ClipsFrom8Drivers`: counts ANT 8, NOR 5, RUS 5, VER 4, HAM 3, HAD 3, LEC 1, GAS 1.
  - `antOnLaps19_20_22`: ANT's clips label `.lap(19)`, `.lap(20)`, `.lap(22)` at 17:30:23, 17:31:23 and 17:34:26 UTC.
  - `lastFourAfterTheFlag`: the clips after `Finished` (18:38:47 UTC) are `.afterFlag`; the three from before 17:03:23 are `.beforeStart`.
  - `qualifyingHas36ClipsFrom15Drivers`.
  - `lapsSeventeenToTwentyThreeShowOnlyReached`: `visible(at:)` at lap 23's picture time lists exactly the clips with `utc ≤ t`.
- [ ] **Step 4: Write the failing queue tests** (`TranscriptionQueueTests`):
  - `nearestFirstWithinTwoMinutes`;
  - `nothingBeyondTwoMinutes`;
  - `oneAtATime`;
  - `queueTimeoutSkips` (a failed clip is never offered again);
  - `threeFailuresWaitTwoMinutes`: nothing at +119 s, a clip at +120 s, and the count resets on a success;
  - `noWordsStored`;
  - `resultsKeyedByPath`: a known path is never offered;
  - `wholeRaceModeOldestFirst`.
- [ ] **Step 5: Run** `cd Packages/DuoCore && /opt/swift/usr/bin/swift test --filter LiveTimingTests`. Expected: the new tests FAIL.
- [ ] **Step 6: Fill the gaps.** Port the queue rules from `origin/og-android` `AppState.kt` (read with `git show`).
- [ ] **Step 7: Run all tests.** Expected: PASS with 0 warnings, and the existing tests are unchanged.
- [ ] **Step 8: Commit** "Radio: whole-race checks, transcription queue".

### Task 2: Event detector and haptic schedule

**Files:**
- Create:
  - `Packages/DuoCore/Sources/LiveTiming/CompanionEvents.swift`
  - `Packages/DuoCore/Sources/LiveTiming/HapticSchedule.swift`
- Test:
  - `Packages/DuoCore/Tests/LiveTimingTests/CompanionEventsTests.swift`
  - `HapticScheduleTests.swift`

**Interfaces:**
- Consumes: `LoadedSession` (`flags`, `timing`, `sessionStatus`, `drivers`), `RadioClips` (Task 1), `TrackStatusKind`.
- Produces:
  - `public enum CompanionEventKind: Sendable, Equatable`, with these cases:
    - `yellow`, `safetyCar`, `vsc`, `red`, `chequered`;
    - `pit(car: String)`, `radio(car: String)`, `out(car: String)`;
    - `passed(car: String, other: String, position: Int)`: `car` passes `other` for P`position`;
    - `purpleSector(car: String)`.
  - `public struct CompanionEvent: Sendable, Equatable { t: UTCms; lap: Int?; kind: CompanionEventKind }`. Track events carry the leader's lap, as `RaceEvents` does. Car events carry that car's lap (count + 1, as the radio labels). Both are nil outside races and before lights out (the pre-race yellows read "Yellow flag", not "Lap 1").
  - `public enum PictureMotion: Sendable { case play, seek }`
  - `public struct EventDetector: Sendable`:
    - statics: `seekQuietMs: Int64 = 2000`, `yellowRepeatMs: Int64 = 60_000`, `jumpMs: Int64 = 10_000`;
    - `public init()`;
    - `public mutating func step(to t: UTCms, motion: PictureMotion, session: LoadedSession, radio: RadioClips, favourite: String?, listening: Set<String> = []) -> [CompanionEvent]`. `listening` holds the racing numbers whose clips auto-play or flash (the Scanner's driver, the Rivals pair, every car for the Radio panel's flash). Their crossed clips come back as `.radio(car:)` under the same crossing and seek rules. The favourite's are always reported.
    - It returns the events in `(previous t, t]`, oldest first. The first step, a `.seek`, a backward step or a step over `jumpMs` only set the baseline and start the quiet period.
    - Track events: entering yellow from clear, entering SC, VSC or red from anything else, and each `Finished`. Yellow fires at most once per `yellowRepeatMs` of picture time.
    - Favourite events (radio also for `listening`), all off when `favourite` is nil and `listening` is empty:
      - `pit` (InPit false→true);
      - `radio` (a clip's `utc` crossed);
      - `out` (Retired or Stopped false→true);
      - `purpleSector` (a sector becomes `.overallBest`);
      - `passed`: a one-place change, with the other car the one the favourite swapped with. Neither car may be in the pit lane (InPit or PitOut) at either end of the step. Larger changes give nothing (pit cycles, retirements).
  - `public enum HapticKind: String, CaseIterable, Sendable { case red, safetyCar, vsc, chequered, yellow, pits, purpleSector }`. Declared in priority order; `var priority: Int` is the index.
  - `public static func HapticKind.from(_ kind: CompanionEventKind) -> HapticKind?`: `radio`, `out` and `passed` have no haptic.
  - `public struct HapticSchedule: Sendable`:
    - `static let spacing: TimeInterval = 2`;
    - `mutating func offer(_ kind: HapticKind, now: TimeInterval)`: one waiting slot, and a stronger kind replaces a weaker one waiting;
    - `mutating func due(now: TimeInterval) -> HapticKind?`: the waiting kind once `spacing` has passed since the last one played.

- [ ] **Step 1: Write failing tests:**
  - `raceYellowsOnLaps17And20`: stepping through `sp26-race-long` at 500 ms gives `.yellow` with laps 17 and 20 between 17:27 and 17:32 UTC.
  - `qualifyingTwoRedFlags`: on `sp26-quali-long`, at 18:02:25 and 20:03:20 UTC.
  - `seekAcrossYellowFiresNothing`
  - `quietTwoSecondsAfterSeek`
  - `backwardOrLongStepIsASeek`
  - `yellowOncePerMinute`: synthetic yellows at +0, +30 s and +61 s give two events.
  - `noFavouriteNoDriverEvents`
  - `favouriteRadioPitOutPurple`: synthetic lines.
  - `passedOnePlaceNamesOther`
  - `pitCycleShuffleNoPassed`
  - `radioEventOnlyWhenCrossed`: a clip whose `utc` is still ahead gives nothing.
  - `listenedCarsRadioCrossed`: with no favourite, a listened car's clip comes back as `.radio`.
  - `seekAcrossClipDoesNotAutoPlay`: a seek past a listened car's clip gives nothing.
  - Schedule tests:
    - `spacingTwoSeconds`;
    - `strongerReplacesWaiting`;
    - `weakerDroppedWhileStrongerWaits`;
    - `priorityOrder`.
- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.** Read each car's state at both ends of the step from `TimingTimeline.at`, track status from `TrackFlags.at`, and `Finished` from `sessionStatus`. Nothing after `t` is read.
- [ ] **Step 4: Run all tests.** Expected: PASS with 0 warnings.
- [ ] **Step 5: Commit** "LiveTiming: event detector for cards and haptics; haptic schedule".

### Task 3: Gap pair

**Files:**
- Create: `Packages/DuoCore/Sources/LiveTiming/GapPair.swift`
- Test: `Packages/DuoCore/Tests/LiveTimingTests/GapPairTests.swift`

**Interfaces:**
- Consumes: `LoadedSession`, `TimingTimeline`, `RaceLines.trendLaps`, `F1Values` (gap text parsing).
- Produces:
  - `public enum GapTrend: Sendable, Equatable { case closing, growing, steady }`: steady within 100 ms.
  - `public enum GapReading: Sendable, Equatable`, with these cases:
    - `gap(ms: Int, ahead: String, behind: String, trend: GapTrend?, heat: Double)`;
    - `lapped(text: String, ahead: String, behind: String)`;
    - `inPit(car: String)`, `out(car: String)`;
    - `beforeFirstLap`, `notRace`.
  - `public enum GapPair`:
    - `static func heat(gapMs: Int) -> Double`: 0 at ≥ 3000, 0.5 at 2000, 1 at ≤ 1000, linear between.
    - `static func reading(_ a: String, _ b: String, at t: UTCms, session: LoadedSession) -> GapReading`. Adjacent cars use F1's interval; others use the difference of their gaps to the leader. F1's text stands when it is not a time ("1L"). The trend compares the gap now with the gap 3 laps ago (`RaceLines.trendLaps`).
    - `static func defaultPair(favourite: String?, at t: UTCms, session: LoadedSession) -> (String, String)?`: your driver and the nearer car ahead or behind; without a favourite, P1 and P2.
    - `static func shifted(_ pair: (String, String), by step: Int, at t: UTCms, session: LoadedSession) -> (String, String)?`: moves an adjacent pair along the race order. Nil past either end.

- [ ] **Step 1: Write failing tests** (synthetic `TimingData` lines through `TimingTimeline.build`):
  - `adjacentUsesInterval`
  - `nonAdjacentSubtractsGaps`
  - `lappedKeepsF1Text`
  - `inPitAndOut`
  - `notRaceInQualifying`
  - `beforeFirstLap`
  - `trendClosingOverThreeLaps`
  - `heatStops`: 3000→0, 2000→0.5, 1000→1, 500→1, 5000→0.
  - `defaultPairNearerRival`
  - `defaultPairWithoutFavourite`
  - `shiftStopsAtEnds`
  - `nothingAfterT`: a gap change after `t` is not read.
- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run all tests.** Expected: PASS with 0 warnings.
- [ ] **Step 5: Commit** "LiveTiming: gap pair for the Gap Thermometer".

### Task 4: Closed pages and the hinge mixer curve

**Files:**
- Create:
  - `Packages/DuoCore/Sources/Multiview/ClosedPager.swift`
  - `Packages/DuoCore/Sources/Multiview/HingeMixer.swift`
- Test:
  - `Packages/DuoCore/Tests/MultiviewTests/ClosedPagerTests.swift`
  - `HingeMixerTests.swift`

**Interfaces:**
- Produces:
  - `public enum ClosedPage: String, CaseIterable, Codable, Sendable { case picture, radio, gap }`
  - `public enum ClosedPager`:
    - `static func page(from: ClosedPage, up: Bool) -> ClosedPage?`: swiping up goes picture → radio → gap. There is no wrap; nil at either end.
    - `static func raceOrder(at t: UTCms, session: LoadedSession) -> [String]`: by position, unknown positions last, then by number. Radio is never read.
    - `static func driver(after current: String?, forward: Bool, order: [String]) -> String?`: wraps.
    - `static func defaultDriver(favourite: String?, order: [String]) -> String?`: your driver, else the leader.
  - `public struct MixLevels: Sendable, Equatable { public var commentary: Float; public var radio: Float }`
  - `public struct HingeMixer: Sendable`:
    - statics: `allRadioAngle = 70.0`, `allCommentaryAngle = 160.0`, `deadZone = 5.0`, `smoothing = 0.3`;
    - `static func levels(angle: Double) -> MixLevels`: clamped and linear, `commentary + radio == 1`;
    - `mutating func update(angle: Double) -> MixLevels?`: smooths the reading. It returns new levels only when the smoothed angle has moved more than `deadZone` from the last applied angle, or crossed a clamp end. The first reading always applies.

- [ ] **Step 1: Write failing tests:**
  - `pagesUpDownNoWrap`
  - `orderIsRacePositionNotRadio`
  - `driverSwipeWraps`
  - `defaultDriverIsLeaderWithoutFavourite`
  - `levelsAtEnds`: 70°→(0, 1), 160°→(1, 0), 30°→(0, 1), 180°→(1, 0), 115°→(0.5, 0.5).
  - `deadZoneIgnoresJitter`: readings 100, 102, 98, 103 apply only the first.
  - `smoothingFollowsAMove`
  - `endsAlwaysReached`
- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run all tests.** Expected: PASS with 0 warnings.
- [ ] **Step 5: Commit** "Multiview: closed-phone pages and the hinge mixer curve".

### Task 5: Logbook model and race control by car

**Files:**
- Create: `Packages/DuoCore/Sources/LiveTiming/Logbook.swift`
- Test: `Packages/DuoCore/Tests/LiveTimingTests/LogbookTests.swift`

**Interfaces:**
- Consumes: `LoadedSession`, `RaceEvents.list(until:session:)` (`.pit(car:)` with `end`), `StintTimeline`, `TimingTimeline.completedLaps(of:upTo:)`, `RadioClips` (Task 1).
- Produces:
  - `public struct RaceControlEntry: Sendable, Equatable { t: UTCms; text: String; cars: [String] }`
  - `public enum RaceControlLog`:
    - `static func parse(lines: [StreamLine], streamStart: UTCms) -> [RaceControlEntry]`: the cars come from `RacingNumber` and from "CAR 44 (HAM)" in the text. Duplicates are dropped as beta.3 does.
    - `static func entries(for car: String, until t: UTCms?, in all: [RaceControlEntry]) -> [RaceControlEntry]`.
  - `public struct LogbookStop: Sendable, Equatable { lap: Int?; laneMs: Int?; off: String?; on: String? }`
  - `public struct LogbookModel: Sendable, Equatable`:
    - `number`, `position: Int?`;
    - `tyre: (compound: String, laps: Int)?` (hand-written `==`);
    - `lastLap: String?`;
    - `radio: [RadioClip]`, `laps: [CompletedLap]`, `stops: [LogbookStop]`, `raceControl: [RaceControlEntry]`;
    - `ahead: String?`, `behind: String?`.
  - `public static func Logbook.at(_ t: UTCms?, car: String, session: LoadedSession, radio: RadioClips, raceControl: [RaceControlEntry]) -> LogbookModel?`: a nil `t` means the whole race.

- [ ] **Step 1: Write failing tests:**
  - `raceControlNamesCarFromText`
  - `raceControlByNumberField`
  - `stopsWithLaneTimeAndTyres`: synthetic pit, then stints.
  - `stopStillInLaneHasNoTime`
  - `nothingAfterT`
  - `radioOnlyThisCar`
  - `unknownCarGivesNil`
- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.** Reuse `TrackFlags.controlMessages` for reading the lines.
- [ ] **Step 4: Run all tests.** Expected: PASS with 0 warnings.
- [ ] **Step 5: Commit** "LiveTiming: logbook model and race control by car".

### Task 6: Beta.4 settings store

**Files:**
- Create: `Packages/DuoCore/Sources/Multiview/CompanionSettings.swift`
- Test: `Packages/DuoCore/Tests/MultiviewTests/CompanionSettingsTests.swift`

**Interfaces:**
- Consumes: `KeyValueStore`, `ClosedPage` (Task 4), `HapticKind` (Task 2).
- Produces:
  - `public enum CardGroup: String, CaseIterable, Codable, Sendable { case flags, myStopsAndRadio, myPositions, chequered }`, and `static func of(_ kind: CompanionEventKind) -> CardGroup?`:
    - flags: yellow, SC, VSC, red;
    - myStopsAndRadio: pit, radio, out;
    - myPositions: passed;
    - chequered;
    - purple sector: nil (no card).
  - `public enum RadioFilter: Codable, Sendable, Equatable { case all, myDriver, driver(String) }`
  - `public final class CompanionSettings: @unchecked Sendable` over `any KeyValueStore`. Keys are prefixed `companion.`; locking and corrupt-value rules are those of `MultiviewStore` and `TimingSettings`.
    - `transcripts` (true), `autoPlayRadio` (true), `hingeMixer` (false);
    - `haptics` (true), `hapticOn(_:) -> Bool` (true), `setHaptic(_:on:)`;
    - `cardGroupOn(_:) -> Bool` (true), `setCardGroup(_:on:)`;
    - `rewindSeconds: Int` (5; only 3, 5, 10 or 15, anything else reads 5);
    - `showHapticsOnScreen` (false);
    - `lastClosedPage: ClosedPage` (`.picture`), `scannerDriver: String?`, `gapPair: [String]?` (two numbers);
    - `radioFilter: RadioFilter` (`.all`);
    - `closedHintShown` (false).
  - The Radio panel's frame per posture reuses `TimingSettings.panelFrame("radio", posture:)`.

- [ ] **Step 1: Write failing tests:**
  - `defaults`
  - `roundTrip`
  - `rewindOnlyAllowedValues`
  - `corruptFallsBack`
  - `cardGroupOfEachKind`
- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run all tests.** Expected: PASS with 0 warnings.
- [ ] **Step 5: Commit** "Multiview: beta.4 settings".

### Task 7: Radio probe for owner check T-A4

**Files:**
- Modify:
  - `spike/timing_recorder.py`: add `--radio`;
  - `spike/.gitignore`: add `radio-probe/`.

**Interfaces:**
- Produces: `pbpaste | python3 spike/timing_recorder.py --radio`.
  - It downloads the first three race clips of `2026/2026-11-08_São_Paulo_Grand_Prix/2026-11-08_Race/` (paths from its TeamRadio file): first with no `Authorization`, then with the pasted token.
  - It saves to `spike/radio-probe/`.
  - It prints per try: HTTP status, bytes, the format from the first bytes (`ID3` or an MPEG frame sync), sample rate, bitrate and duration from the first MPEG frame header (or the Xing/Info frame).
  - The token is never printed. The `--base-url` test stub works for it as for `--archive`.

- [ ] **Step 1: Write the probe** with the standard library only, reusing the script's HTTP and sign-in helpers.
- [ ] **Step 2: Check it against a local stub.** Run `python3 -m http.server` serving a folder with a synthetic MPEG header file, then `--base-url http://127.0.0.1:<port>`. Expected: one report line per try, and no token in the output.
- [ ] **Step 3: Commit** "Spike: radio probe for T-A4".

## Post-freeze tasks (merge on or after Sun 22 Nov)

### Task 8: Radio in the session's loading (DuoCore, after freeze)

**Files:**
- Modify:
  - `Packages/DuoCore/Sources/LiveTiming/TimingArchive.swift`:
    - `LoadedSession` gains `radio: RadioClips` and `raceControl: [RaceControlEntry]` (init defaults: empty);
    - `topics(for:)` adds `TeamRadio` as an optional topic;
    - the load fills both fields.
  - `Packages/DuoCore/Sources/LiveTiming/LiveFeed.swift`: `session(...)` fills both from the live lines, incrementally on the build 16 fast path. A reconnect snapshot and the archive top-up add clips through `RadioClips.add`, which drops paths already seen.
- Test:
  - `TimingArchiveTests.swift`
  - `LiveFeedTests.swift`

**Interfaces:**
- Consumes: Tasks 1 and 5.
- Produces: `LoadedSession.radio`, `LoadedSession.raceControl`.
- Merged API this task builds on:
  - `RaceControlEntry` carries `category: String?` and `flag: String?` (F1's raw `Category` and `Flag`, nil when absent) and reads F1's multi-car form ("CARS 87 (BEA) AND 55 (SAI)") as well as "CAR 44 (HAM)" and `RacingNumber`.
  - `RaceControlLog` is a struct with `mutating func add(_ line: StreamLine)` (the same de-duplication: same Utc and same text, the first kept), `all`, `init(lines:streamStart:)`, and the static `parse(lines:streamStart:)` and `entries(for:until:in:)`. The live feed and the archive top-up add through `RaceControlLog.add`, as clips go through `RadioClips.add`.
  - The `Radio.swift` trap on extreme GMT offsets is already fixed (nothing to do here).

- [ ] **Step 1: Write failing tests:**
  - `archiveLoadsRadio`
  - `missingTeamRadioIsOptional`: a 403 on TeamRadio lands in `missing`, and the session loads.
  - `liveFeedHasRadio`
  - `liveReconnectAndTopUpKeepClipsOnce`
  - `incrementalRebuildMatchesFull`
  - `archiveLoadMatchesLongRace`: the archive loader's `LoadedSession` (radio and race control included) equals the one `RadioRaceTests.longRace()` builds by hand for `sp26-race-long`;
  - `raceControlResentIsKeptOnce`: a message sent again by a reconnect or the top-up is not repeated.
- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run all tests.** Expected: PASS with 0 warnings. The build 16 harness's pure files still typecheck against this branch.
- [ ] **Step 5: Commit** "Timing: team radio and race control in the loaded session".

### Task 9: Book layouts Onboard and Logbook, and Rivals (DuoCore, after freeze)

**Files:**
- Modify: `Packages/DuoCore/Sources/Multiview/LayoutEngine.swift`.
- Test: `Packages/DuoCore/Tests/MultiviewTests/LayoutEngineTests.swift`, against `Fixtures/layouts-reference.json`.

**Interfaces:**
- Produces:
  - `optionIDs(posture: .book, feedCount:, hasTiming: true)` appends `book.logbook`, then `book.rivals` when `feedCount >= 2`. Lists without timing are unchanged.
  - `DataRegions` gains `logbook: CGRect?`, `leftStrip: CGRect?` and `rightStrip: CGRect?` (default nil; `rects` includes them).
  - **`book.logbook`:**
    - tile 0 is the largest 16:9 in the left screen, vertically centred;
    - `logbook` is the whole right screen inside the margins;
    - other feeds are hidden.
  - **`book.rivals`:**
    - tiles 0 and 1 are one per screen, each the largest 16:9 above a strip;
    - each strip is 64 pt tall (the minimum), or what is left under the tile when that is more;
    - other feeds are hidden.
  - All of it follows the 6 pt margin and gap, the 200 pt minimum width and the fold rule.

- [ ] **Step 1: Write failing tests:**
  - `logbookRightScreen`
  - `rivalsTwoTilesTwoStrips`
  - `rivalsNeedsTwoFeeds`
  - `nothingInFold`
  - `regionsNeverOverlapTiles`
  - `plainListsUnchanged`: every existing posture and feed count without timing gives today's list.
- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run all tests.** Expected: PASS; the existing layout tests still pass.
- [ ] **Step 5: Commit** "LayoutEngine: Onboard and Logbook, and Rivals".

### Owner check before Task 10 (T-A4)

The owner runs `pbpaste | python3 spike/timing_recorder.py --radio` on the Mac (about 5 minutes) and shares the report only. Its answer fixes O5:
- whether clips need the token;
- the format;
- typical duration.

Task 10 works either way (no token first, then once with it). The answer goes into the build 17 CHANGELOG.

**Done 2026-11-19:** clips need no token (HTTP 200 without it); MP3, 48 kHz, 128 kbps, 3–11 s,
47–174 KB each. See spec O5. Build 17's CHANGELOG repeats this.

### Task 10: App, build 17 — radio on replays

**Files:**
- Create in `DuoApp/Radio/`:
  - `RadioController.swift`
  - `RadioAudio.swift`
  - `RadioFetch.swift` (pure)
  - `RadioModels.swift` (pure)
  - `RadioPanel.swift`
  - `RadioRow.swift`
  - `RadioSettingsSection.swift`
  - `TranscribeProbe.swift`
- Modify:
  - `DuoApp/Support/AppModel.swift`: own `CompanionSettings` and one `RadioController` per watched session, beside `TimingController`.
  - `DuoApp/Multiview/MultiviewController.swift`: conform to `PlaybackHost` (below). `setFeedVolume` sets the audible feed's `player.volume` and leaves `isMuted` (the role rule) alone. `seekGeneration` goes up on every `seek(toSeconds:)` and on the main feed's `AVPlayerItem.timeJumpedNotification`.
  - `DuoApp/Player/PlayerController.swift`: the same. `timeJumpedNotification` covers the system scrubber.
  - `DuoApp/Multiview/MultiviewControls.swift` and `DuoApp/Player/PlayerView.swift`: the "Radio" button beside Map.
  - `DuoApp/Timing/FloatingPanels.swift`: the Radio panel. Its frame is saved per posture as `"radio"`.
  - `DuoApp/Timing/RaceEngineerConsole.swift`: replace the "Saved for beta.4: team radio" spot with the engineered driver's last three clips with ▶.
  - `DuoApp/Timing/ScrubDeck.swift`: radio ticks.
  - `DuoApp/Support/SettingsView.swift`: Team radio section; Debug › "Transcribe a test clip".
  - `README.md` Status.
  - `Config/Version.xcconfig`: `BETA_LABEL = beta.4`, build 17.
  - `CHANGELOG.md`

**Interfaces:**
- Consumes:
  - `LoadedSession.radio` (Task 8), `RadioClips`, `RadioLapLabel`, `CompanionSettings` (Task 6);
  - `TranscriptionQueue` (Task 1): transcripts are `[String: String]` keyed by clip path, with `TranscriptionQueue.noWords` as the "no words" text (there is no `TranscriptResult`). Rows read them only through `transcript(for:at:)` and `transcribing(visibleAt:in:)`, never from the raw `running` or `results`, so nothing later than picture time reaches a row;
  - `CompanionEventKind.radio(car:path:)`, which carries the clip's path;
  - `TimingController.loadedSession`, `pictureTime`, `showWholeRace`;
  - `Tower.carNumber(forDriver:in:)`, `DeckAxis.markerTarget`.
- Nil picture time. In DuoCore a nil `t` means "the whole race". In the app, `TimingController.pictureTime` is nil when there is no time yet. So build the cut as `showWholeRace ? nil : t`, and show nothing when `t` is nil (the same for `shouldStop` and `tickFractions`).
- The favourite is private in `TimingController`: add an accessor for it, and convert it to a racing number with `Tower.carNumber(forDriver:in:)`.
- Produces:
  - `enum RadioFetch` (pure):
    - `static func cacheURL(base: URL, sessionKey: String, clipPath: String) -> URL`: the file name is the clip's last path segment;
    - `static func fetch(_ url: URL, http: any HTTPClient, token: @Sendable () async -> String?) async -> RadioFetchResult`, where `RadioFetchResult` is `.data(Data)`, `.refused` or `.failed`;
    - `static func expired(modified: Date, now: Date) -> Bool`: 7 days.
  - `struct RadioRowModel: Equatable, Sendable { path; number; tla; teamColour; label: String?; header: String?; transcript: TranscriptLine; isNew: Bool }`, where `enum TranscriptLine { case none, transcribing, text(String), noWords }`. Whether transcripts are available at all is a panel-level line (Task 11's `TranscriptState`), not a row's.
  - `enum RadioModels` (pure):
    - `static func label(_ l: RadioLapLabel) -> String?`: the Global Constraints formats;
    - `static func rows(clips: [RadioClip], session: LoadedSession, queue: TranscriptionQueue, at t: UTCms?) -> [RadioRowModel]`: transcripts and the clip in progress come from `queue.transcript(for:at:)` and `queue.transcribing(visibleAt:in:)`; `t` is the cut (`showWholeRace ? nil : pictureTime`), and a nil picture time with the whole race off gives no rows;
    - `static func emptyText(filter: RadioFilter, tla: String?) -> String`;
    - `static func shouldStop(playing: RadioClip, pictureTime: UTCms?) -> Bool`;
    - `static func tickFractions(...)`: the deck's ticks, only up to picture time unless whole race.
  - `@MainActor @Observable final class RadioController`:
    - `init(settings: CompanionSettings, timing: TimingController, http: any HTTPClient, token: @escaping @Sendable () async -> String?)`;
    - `func attach(host: any PlaybackHost)` and `func detach()`, where `@MainActor protocol PlaybackHost: AnyObject { func setFeedVolume(_ volume: Float); var playbackRate: Double { get }; var seekGeneration: Int { get } }`. Both the multiview and the single-feed player attach. A changed `seekGeneration` between two ticks is a `.seek`;
    - it runs its own `EventDetector` with `listening` = every car. A clip crossed in normal play makes its row `isNew` for 3 s (one soft flash); a clip that appears through a seek never flashes;
    - `func listen(_ cars: Set<String>)`, and `var crossed: AsyncStream<RadioClip>`: clips of listened cars crossed in normal play. Tasks 12 and 14 auto-play from it, never from rows appearing;
    - `private(set) var rows: [RadioRowModel]` (2 Hz, at picture time), `var filter: RadioFilter`;
    - `func play(path: String, pan: Float = 0)`, `func stop()`, `private(set) var playing: String?`, `private(set) var notice: String?`;
    - `func clips(for number: String, limit: Int?) -> [RadioRowModel]`.
  - `RadioAudio`: one `AVAudioEngine` with an `AVAudioPlayerNode` → `AVAudioUnitTimePitch` (rate = the feeds' rate) → the main mixer. Pan and volume are on the player node. It restarts after an engine configuration change.

- [ ] **Step 1: RadioFetch and RadioModels** (pure), and their harness checks:
  - `clipRefusedThenTokenOnce`, `tokenOnlyToClipURL`, `refusedTwiceCouldntLoad`, `cacheNameHasNoToken`;
  - `labelFormats`, `headersWhenLabelChanges`, `unknownHasNoLabel`;
  - `emptyRadioCopy`;
  - `rewindStopsPlayingClip`, `ticksOnlyUpToPictureTime`, `wholeRaceShowsAll`.
- [ ] **Step 2: RadioAudio and RadioController.**
  - Downloads run off the main actor, when a clip is first played. Clips are cached; files older than 7 days are deleted at launch.
  - Playing a clip sets the feeds' volume to 0; it goes back to 1 at the end, on stop, on rewind past the clip (`shouldStop`), and on detach.
  - Copy: "Couldn't load this clip", "Couldn't play that radio clip".
- [ ] **Step 3: Views.**
  - The Radio panel: chips All · My driver · driver; lap headers; the list follows new clips; one soft flash for a new clip; tap to play, tap again to stop; "Hide team radio".
  - Race Engineer's spot.
  - Scrub Deck ticks: taller for your driver, behind the fog; a tap seeks 5 s before (`markerTarget`).
- [ ] **Step 4: The "Transcribe a test clip" probe** (Settings › Debug, for O4).
  - It transcribes the first cached clip with `SpeechTranscriber`.
  - It shows: available or not, locale, model installed or downloading, seconds taken, and the text.
  - It uses the same calls Task 11's `Transcriber` will use, in one function.
- [ ] **Step 5: Self-check.**
  - `swiftc -parse` on every changed file.
  - Harness `apptc17`: `RadioFetch.swift`, `RadioModels.swift`, `MultiviewLayout.swift` and the build 16 harness files. All checks PASS.
  - No `print`, and no token in any string.
  - Bump to build 17; add the CHANGELOG build 17 section with its untested list; README Status.
- [ ] **Step 6: Commit** "Team radio on replays: Radio panel, Race Engineer's spot, Scrub Deck ticks (build 17)".
- [ ] **Owner check T-B17:**
  - The zero-warnings build (`xcodegen generate` first; new folder `DuoApp/Radio`).
  - São Paulo race replay, laps 17–23: clips appear only as reached, under their lap; ANT has 8 over the race.
  - A clip plays while the feeds go quiet, at the feeds' speed.
  - Ticks; Race Engineer's spot.
  - The probe in the simulator **and on the Duo** (O4).

### Task 11: App, build 18 — transcripts

**Files:**
- Create in `DuoApp/Radio/`:
  - `Transcriber.swift`
  - `TranscriptStore.swift` (pure)
  - `TranscriptState.swift` (pure)
- Modify:
  - `RadioController.swift`: drive `TranscriptionQueue` while a radio surface shows and Transcripts is on.
  - `RadioRow.swift`
  - `RadioSettingsSection.swift`
  - `TranscribeProbe.swift`: call `Transcriber`.
  - `DuoApp/Info.plist`: `NSSpeechRecognitionUsageDescription` with the Global Constraints reason. Always present: the `SFSpeechRecognizer` fallback needs it, whatever O1 finds.
  - `README.md`: the Privacy line under F1's live timing (verbatim from the spec), and the note on iOS's model download.
  - `Config/Version.xcconfig` (build 18).
  - `CHANGELOG.md`

**Interfaces:**
- Consumes: `TranscriptionQueue` (Task 1). There is no `TranscriptResult`: a transcript is a `String`, and `TranscriptionQueue.noWords` stands for "no words".
- Produces:
  - `enum TranscriberReadiness: Sendable, Equatable { case ready, downloadingModel, unavailable, permissionDenied }`, declared in the pure `TranscriptState.swift` so the harness can take it.
  - `actor Transcriber`:
    - `func prepare() async -> TranscriberReadiness`;
    - `func transcribe(fileURL: URL, hints: [String]) async throws -> String` (a blank result means no words; the queue stores `noWords`).
    - The engine:
      - `SpeechTranscriber` in a `SpeechAnalyzer` with `analyzeSequence(from:)`;
      - locale from `supportedLocale(equivalentTo:)`, en-GB, then en-US;
      - a missing model through `AssetInventory.assetInstallationRequest(supporting:)`;
      - when `SpeechTranscriber.isAvailable` is false: `DictationTranscriber`, then `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`;
      - never a server.
    - Hints go in `AnalysisContext.contextualStrings`: DriverList names and teams, plus Android's radio words. Read them from `origin/og-android` `Transcriber.kt`.
  - `struct TranscriptStore` (pure): loads and saves `[String: String]` (clip path to transcript) as `transcripts.json` beside the clips. A corrupt file reads as empty. The queue is seeded from it with `TranscriptionQueue(results:)`.
  - `enum TranscriptState` (pure): the panel's line for each readiness: "Getting the speech model ready…", "Transcripts aren't available on this iPhone — clips still play", "Allow speech recognition in Settings to see transcripts".
  - The controller drives the queue like this:
    - `next(from:at:now:)` with `now` the monotonic clock in ms (e.g. system uptime × 1000, as `Int64`), using the queue's constants `aheadMs`, `timeoutMs`, `failuresBeforeWait` and `waitMs`;
    - call `next` only while `prepare()` says `.ready`;
    - the 45 s timeout is a task group racing a sleep, and on timeout the controller calls `timedOut(path:)`, NOT `failed`; `failed(path:at:)` is for a transcriber error;
    - call `cancelled(path:)` when a radio surface closes;
    - when `next` replaces the running job, cancel the old transcriber task and drop any late report from the cancelled task.

- [ ] **Step 1: TranscriptStore and TranscriptState**, and their harness checks:
  - `storeRoundTrip`, `corruptStoreEmpty`;
  - `unavailableShowsNote`, `permissionDeniedNote`, `downloadingNote`.
- [ ] **Step 2: Transcriber**, then the controller's queue loop: one clip at a time, and only while a radio surface is on screen.
- [ ] **Step 3: Transcript lines in rows** (up to two lines, in quotes).
- [ ] **Step 4: Self-check** as in Task 10 (harness `apptc18` adds the two pure files). Build 18, CHANGELOG, README.
- [ ] **Step 5: Commit** "Team radio transcripts on the phone (build 18)".
- [ ] **Owner check T-B18:**
  - Transcripts in the simulator if O4 said yes.
  - **On the Duo:**
    - transcription speed: seconds per clip over 10 clips;
    - the model-download line;
    - whether a permission prompt appears (O1);
    - whether a fallback ran (O7);
    - warmth over 20 minutes of radio on screen.

### Task 12: App, build 19 — the closed phone and Unfold to See

**Owner decision (2026-11-18), part of this task:** on the outer screen (466 × 678 pt) the Picture
page stacks two feeds full width when the multiview has two or more (main on top, left/right
still changes the main one); with one feed, the timing tower fills the space below. This needs a
two-tile closed option in `LayoutEngine` (Task 9 adds the book shapes there; add `closed.stack`
alongside, with tests: both tiles 466 wide, stacked within the safe height, the main one on top)
and the Picture page in `ClosedPagerView`. Since build 16 the closed layout already uses the full
width (`MultiviewLayout.input`).

**Files:**
- Create in `DuoApp/Closed/`:
  - `ClosedPagerView.swift`
  - `RadioScannerView.swift`
  - `GapThermometerView.swift`
  - `EventCardsView.swift`
  - `BackChip.swift`
  - `CompanionController.swift`
  - `CompanionModels.swift` (pure)
  - `ClosedSettingsSection.swift`
- Modify:
  - `DuoApp/Multiview/MultiviewView.swift`: the closed layout becomes the pager (the Picture page is today's closed layout, its horizontal swipe unchanged).
  - `DuoApp/Multiview/MultiviewController.swift`: `func jump(toPictureTime:)` through the Scrub Deck's seek, and `func jumpBack()`.
  - `DuoApp/Support/SettingsView.swift`: the Closed phone section. Debug shows the screen's size in points ("Screen: W × H pt") for measuring the outer screen.
  - `Config/Version.xcconfig` (build 19).
  - `CHANGELOG.md`

**Interfaces:**
- Merged API notes:
  - `.radio(car:path:)` carries the clip path.
  - Pass `listening: []` to this task's detector (auto-play comes from `radio.crossed`), or drop `.radio` cards for cars other than the favourite.
  - After a `.seek`, remove the cards later than picture time.
  - Validate the stored `scannerDriver` and `gapPair` against the session's cars before use.
  - `rewindSeconds` is in seconds: multiply by 1000 before subtracting it from `t` (ms).
  - The favourite is a racing number (see Task 10's accessor and `Tower.carNumber(forDriver:in:)`).
  - `GapReading` has `.sameCar` as well as `.beforeFirstLap`; show nothing special for it (a pair is never the same car).
- Consumes: `EventDetector`, `CompanionEvent` (Task 2), `GapPair` (Task 3), `ClosedPager`, `ClosedPage` (Task 4), `CompanionSettings`, `CardGroup` (Task 6), `RadioController` (Task 10), `FoldState.posture`.
- Produces:
  - `enum CompanionModels` (pure):
    - `static func cardTitle(_ e: CompanionEvent, drivers: [String: DriverInfo]) -> String`: the spec's card copy;
    - `static func gapText(_ r: GapReading, drivers:) -> (big: String, note: String?, arrow: String?)`;
    - `static func scannerHeader(...)`.
  - `@MainActor @Observable final class CompanionController`:
    - `init(settings: CompanionSettings, timing: TimingController, radio: RadioController)`;
    - `func attach(host: any PlaybackHost)` (Task 10), from both `MultiviewView` and `PlayerView`. In the single-feed player it drives haptics only (no pager, no cards);
    - each 500 ms tick calls `EventDetector.step`. A changed `host.seekGeneration` since the last tick is a `.seek`;
    - `private(set) var cards: [CompanionEvent]` (newest first), `func dismissTop()`;
    - `func postureChanged(from: Posture, to: Posture)`: closed → open with a card showing jumps to the card's `t − rewindSeconds`;
    - `func tapCard()`: the jump on a phone without a fold, and on the Duo while closed;
    - `private(set) var backChip: (title: String, until: Date)?`, `func back()`;
    - `var hapticEvents: AsyncStream<CompanionEvent>` (Task 13 consumes it).
  - Pager:
    - vertical swipe between pages with dots on the right edge;
    - horizontal swipe changes the feed, driver or pair;
    - opens on `lastClosedPage`;
    - the first-time hint;
    - sizes come from `GeometryReader` and type scales with the height (no fixed outer-screen numbers);
    - the feeds keep playing out of sight, with sound, on every page.
  - Radio Scanner:
    - code, team colour, position and lap; large-type transcripts scrolling; one big ▶ / ■;
    - the Scanner calls `radio.listen([driver])` and auto-plays from `radio.crossed` when "Play radio as it happens" is on; otherwise it shows "New radio — tap to play".
  - Gap Thermometer:
    - two codes at either end of a tall bar, the gap in large digits, ▼ or ▲;
    - the colour interpolates blue → amber → red by `heat`;
    - left/right shifts the pair; press and hold opens a two-driver picker (reuse `DriverPicker`);
    - 2 Hz.

- [ ] **Step 1: CompanionModels**, and its harness checks:
  - `cardTitles` (every kind);
  - `gapTexts` (each reading);
  - `jumpTarget`: `t − rewind` from the offset, kept in the timeline;
  - `backChipExpires15s`;
  - `cardsRespectGroups`.
- [ ] **Step 2: CompanionController**, the card stack and Unfold to See, with "Back to where you were". On a live item, "LIVE" returns to the edge as today.
- [ ] **Step 3: The pager, the Scanner and the Thermometer**, each with the spec's empty states.
- [ ] **Step 4: Self-check** (harness `apptc19` adds `CompanionModels.swift`). Build 19, CHANGELOG.
- [ ] **Step 5: Commit** "Closed phone: Radio Scanner, Gap Thermometer, Unfold to See (build 19)".
- [ ] **Owner check T-B19:**
  - Exit-test step 2 in the simulator.
  - **On the Duo:**
    - measure the outer screen (Debug's "Screen" line) and write it in the notes;
    - readability at arm's length;
    - how the swipes feel;
    - what a real unfold does: is the app still in front, and how fast does the posture change;
    - closed with the screen off: foreground or background (O6, Q10).

### Task 13: App, build 20 — haptics

**Files:**
- Create in `DuoApp/Haptics/`:
  - `HapticsPlayer.swift`
  - `HapticPatterns.swift` (pure: pattern descriptions as plain values)
  - `HapticsSettingsSection.swift`
- Modify:
  - `DuoApp/Closed/CompanionController.swift`: feed `HapticSchedule`.
  - `DuoApp/Player/PlayerView.swift` and `DuoApp/Multiview/MultiviewView.swift`: the "Haptic: …" debug label.
  - `DuoApp/Support/SettingsView.swift`
  - `Config/Version.xcconfig` (build 20).
  - `CHANGELOG.md`

**Interfaces:**
- Merged API notes:
  - `HapticSchedule` has no timer. Poll `due(now:)` on the 500 ms tick, and call `reset()` on a `.seek`.
  - Play a haptic only when `haptics && hapticOn(kind)` and the hardware supports haptics.
  - `now` is `TimeInterval` seconds here (the transcription queue uses ms).
- Consumes: `HapticKind`, `HapticSchedule` (Task 2), `CompanionController.hapticEvents` (Task 12), `CompanionSettings`.
- Produces:
  - `struct HapticPattern: Equatable, Sendable { events: [(time: Double, duration: Double?, intensity: Float, sharpness: Float)] }` (hand-written `==`), and `static func HapticPatterns.pattern(for: HapticKind) -> HapticPattern`. Each kind follows the spec's table:
    - yellow: two short soft taps;
    - safety car: three firm pulses;
    - VSC: three soft pulses;
    - red: one long strong buzz, 0.8 s;
    - your driver pits: a rising ramp;
    - purple sector: one crisp tick;
    - chequered: a slow triple.
  - `@MainActor final class HapticsPlayer`:
    - `var supported: Bool` (`capabilitiesForHardware().supportsHaptics`);
    - `func play(_ kind: HapticKind)`: haptics-only patterns; the engine restarts from its reset and stopped handlers;
    - `private(set) var lastShown: (HapticKind, Date)?` for "Show haptics on screen", set on the same path as the real haptic.
  - The single-feed player gets haptics and the Radio panel, not the pager: `PlayerView` attaches the `CompanionController` through `PlaybackHost` (Task 12).

- [ ] **Step 1: HapticPatterns**, and its harness checks: `redIs0_8s`, `eachKindHasPattern`, `labelsMatchSettings`.
- [ ] **Step 2: HapticsPlayer**, the scheduling path and the debug label. Settings › Haptics, hidden without haptic hardware, with "Feel it" per event.
- [ ] **Step 3: Self-check** (harness `apptc20`). Build 20, CHANGELOG.
- [ ] **Step 4: Commit** "Haptics for flags and your driver (build 20)".
- [ ] **Owner check T-B20:**
  - Exit-test step 3 in the simulator, with "Show haptics on screen".
  - **On the Duo:** each "Feel it" and each event in a replay; whether the seven feel distinct; whether yellow nags. O2 on the simulator and with the screen off.
  - The exit test (T-D) can run after this build.

### Owner check before Task 14 (T-R1)

On the São Paulo replay, play an onboard and list its audio options. Listen to whether its team-radio track is continuous radio, clips only, or onboard sound (Q1).
- **If continuous:** the mixer crossfades commentary with that onboard while it plays.
- **Otherwise:** the mixer mixes clips only.

Task 14's Step 3 follows the answer.

### Task 14: App, build 21 — Onboard and Logbook, Ear-Matched Rivals, the hinge mixer

**Files:**
- Create in `DuoApp/Book/`:
  - `LogbookView.swift`
  - `RivalsStrip.swift`
  - `MixerBar.swift`
  - `BookModels.swift` (pure)
- Modify:
  - `DuoApp/Multiview/MultiviewView.swift`: draw the `logbook` and strip regions.
  - `DuoApp/Multiview/MultiviewController.swift`: the Logbook's onboard follows Race Engineer's rules (the main feed if it is an onboard, else your driver's, else the first). For Rivals, the two drivers' onboards go in slots 0 and 1.
  - `DuoApp/Radio/RadioController.swift`: per-clip pan, and the mixer.
  - `DuoApp/Radio/RadioSettingsSection.swift`: "Hinge mixer".
  - `Config/Version.xcconfig` (build 21).
  - `CHANGELOG.md`

**Interfaces:**
- Merged API notes:
  - `GapPair.defaultPair` is nil outside races: fall back to the neighbours in `ClosedPager.raceOrder`.
  - The logbook's tyres are already formatted as Race Engineer's ("Medium", nil when unknown); show them as given.
  - Race control uses `RaceControlEntry.category` and `flag` to filter blue flags (no text matching).
  - `FoldState.hingeAngle` is `Double?`: a nil must not reach `HingeMixer.update`.
- Consumes: Task 9's regions, `Logbook` and `RaceControlLog` (Task 5), `LoadedSession.raceControl` (Task 8), `HingeMixer` (Task 4), `GapPair.defaultPair` (Rivals' default pair), `FoldState.hingeAngle`, `RadioController.play(path:pan:)`.
- Produces:
  - `enum BookModels` (pure):
    - `static func stopLine(_ s: LogbookStop) -> String`;
    - `static func raceControlLine(_ e: RaceControlEntry) -> String`;
    - `static func earLabel(left: Bool, tla: String) -> String`;
    - `static func pan(left: Bool, headphones: Bool) -> Float`: −1 or +1 with headphones, else 0.
  - `RadioController`:
    - `func setMixer(_ levels: MixLevels?)`: nil means off. While on, a clip doesn't silence the feeds: feeds get `levels.commentary` under a clip and the clip gets `levels.radio`. Feeds are at 1 without a clip.
    - Headphones are read from `AVAudioSession.sharedInstance().currentRoute`, and followed on route changes.
  - The mixer runs only in book and laptop with the setting on. `HingeMixer.update` is fed from `FoldState.hingeAngle` changes. `MixerBar` shows for 2 s on a change; "No radio to mix yet" when the session has no clip yet.

- [ ] **Step 1: BookModels**, and its harness checks: `stopLines`, `raceControlLines`, `earLabels`, `panCentredWithoutHeadphones`.
- [ ] **Step 2: LogbookView.**
  - A header (position, tyre and laps on it, last lap), then **Radio**, **Laps** (sector colours), **Stops** and **Race control**, each with its empty copy.
  - Tapping the car ahead or behind switches both screens (beta.3's tap-a-car rules).
- [ ] **Step 3: Rivals and the mixer.**
  - Strips: the last transcript and ▶; a tap on a strip's header changes that driver.
  - Rivals calls `radio.listen` with the pair and auto-plays from `radio.crossed` when the setting is on. Each clip is panned to its screen's ear; commentary stays centred.
  - The mixer follows T-R1's answer.
- [ ] **Step 4: Self-check** (harness `apptc21`). Build 21, CHANGELOG.
- [ ] **Step 5: Commit** "Book: Onboard and Logbook, Ear-Matched Rivals; the hinge mixer (build 21)".
- [ ] **Owner check T-B21:**
  - Both book options in the simulator; panning with headphones on the Mac.
  - **On the Duo:**
    - the real book halves;
    - AirPods panning;
    - the hinge mixer's feel: angle noise, update rate, and whether the 5° dead zone feels steppy.
- [ ] **Owner check T-C4** (the first live weekend after build 20): live radio, transcripts and haptics against a real stream delay.

## After Task 14 (controller)

- Build 22, the final fixes from the beta.4 review, as for beta.3's build 16:
  - remove the "Transcribe a test clip" probe;
  - one fix round only.
- CHANGELOG: the v1.0-beta.4 section with its summary and the "Untested — check later" lists.
- README status; roadmap ideas 4, 6, 7, 8, 9, 16 and 17 marked as landed.
- A rulings note, `docs/superpowers/notes/<date>-beta4-rulings.md`, with the rulings in this plan's Global Constraints and Task 2 (clocks, priority, dead zone, pit-cycle passes, lap-label formats, card groups).
- The test checklist for beta.4.
- Final whole-branch review, privacy scan (no tokens, no mp3, no personal data, no model names), release text.
