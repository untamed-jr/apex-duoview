# v1.0-beta.3 — Live data: design

Draft for the owner's approval (2026-11-16). The owner picked Race Engineer "C", Scrub Deck "C"
and data layouts "C" in conversation, and approved the summary ("all good, if you can think of other
features add it"). The extra features the controller added are marked **(added)**.

## Goal and exit test

The beta where the race data joins the picture. A track map with every car, a timing tower, flags,
driver cards and the pit circle, all kept in step with the video. Tapping a car opens its onboard.
The fold gives the data its own room instead of covering the video: Director's Desk open flat, a data
screen half-open like a book, and Race Engineer and Scrub Deck half-open like a laptop.

**Exit test (owner, in the iPhone Duo simulator, on the São Paulo 2026 race replay):**
1. The track map and timing match the picture. A car crossing the line on the world feed crosses
   it on the map within about a second, and the tower's order changes when the overtake happens on
   screen.
2. Tapping a car on the map or the tower brings up its onboard.
3. In laptop posture, Race Engineer and Scrub Deck both work: the console follows the onboard,
   and dragging the Scrub Deck moves every feed to that moment.

Live behaviour (live timing, recording, the next-live offer) is checked at the first live weekend
after the live build. It is listed as untested until then, as in beta.2.

## Why

The owner's aim since beta.1: an app like the Android one, built for the Duo, using every bit of
the screen. The Android app has the map, tower, flags, cards and pit circle, but it lays them over
the video. On the Duo the second half of the screen can carry the data instead. Race Engineer and
Scrub Deck are the owner's own Duo ideas (roadmap #19, #20), and Director's Desk is #11.

## Goals

1. **Timing data for the session being watched, from F1's own live timing:** the live hub during
   a live session, F1's archive for replays. It works with the viewer's F1 TV sign-in, as Android
   does.
2. **Kept in step with the picture.** Everything shown is read at one "picture time" (below). Data
   never runs ahead of the picture (no spoilers).
3. **From Android, carried over:**
   - the track map: outline, corner numbers, start/finish, team-coloured car dots with
     three-letter codes, dimming in the pits, a yellow ring for a flying lap in qualifying;
   - flags on the map: yellow sectors, safety car, virtual safety car and red flag, with a caption;
   - the timing tower;
   - driver cards over onboards, with a speed readout;
   - the pit circle, with the 0.98 fix for joining late;
   - tap a car to open its onboard;
   - the −7 s timing offset with −1 s / +1 s nudge buttons;
   - lights-out and chequered marks on the timeline;
   - the offer of the next live programme (0.95);
   - live timing saved to the phone (0.99.4, adapted).
4. **Duo layouts (owner, option C):**
   - **Flat:** Director's Desk as a ⟳ layout.
   - **Book:** a ⟳ layout with the feeds on the left screen and the map and tower on the right.
   - **Laptop:** Race Engineer and Scrub Deck.
   - **Any fold:** the map and tower as floating panels, switched on from the controls.
5. **Race Engineer (owner, option C):** an onboard on the top screen. On the bottom screen, the
   car's live readouts plus that driver's race. Tap the car ahead or behind to switch the onboard to it.
6. **Scrub Deck (owner, option C):** the video on the top screen, with a lap chart and event
   markers below. Drag to scrub every feed; tap a marker to jump just before it. Your driver's line
   is highlighted.
7. **Added:**
   - a session header: lap count (or the session clock), track status and the weather;
   - safety car and red flag bands on the multiview timeline, as well as lights out and chequered;
   - a "battle" highlight when your driver is within a second of another car;
   - a delay setting for the tracker feed (the beta.2 note that the tracker runs ahead).

## Non-goals (this beta)

- **Team radio, transcripts, haptics on flags, closed-phone modes:** beta.4. Race Engineer keeps a
  drawn and labelled spot: "Saved for beta.4: team radio".
- **Strategy Lab, Mirror Lap, Then and Now, Prediction Pad:** beta.5.
- **Android's "edge" map,** where the lap is unrolled along the screen edge over the video. Not
  built, because the Duo layouts give the map real room. **This is the controller's call; the owner
  can ask for it.**
- **Recording live timing by alarm in the background.** iOS doesn't allow it. The app records only
  while it is open or playing (roadmap, 0.99.4 adapted).
- **Speeds from history.** Car telemetry (speed, gear, throttle, brake, revs, DRS) is not saved
  while recording, as on Android. A live session joined late has readouts only from the moment of
  joining.
- **Data for content without timing** (Paddock shows, documentaries, older seasons the archive
  doesn't have): no data panels, no errors. The ⟳ data layouts don't appear for that content.

## Anti-goals (a failure even if it technically works)

- **Data ahead of the picture.** A tower, lap chart or event list that reveals a pass, a crash or
  the result before the video shows it.
- **Data that disturbs the video:**
  - a stall, a dropped frame or a reload caused by the data;
  - data panels covering the video in the Duo data layouts;
  - the video waiting for timing to load.
- **Extra F1 TV video requests.** Timing uses F1's timing service, never another video PLAY.
- **Tokens, cookies or signed URLs** in logs, errors, files or commits. Timing files on the phone
  hold timing only.
- **Battery or heat out of proportion:** the map redraws at most at the display's frame rate and
  only while visible, and the tower at most twice a second.

## Constraints

Everything in beta.2's constraints still holds:
- Swift 6 with strict concurrency, iOS 27.1, `@MainActor` for UI and AVFoundation, no third-party
  dependencies;
- DuoCore stays Foundation-only, apart from the existing conditional CoreGraphics import;
- the layout rules: 16:9 aspect-fit tiles, 6 pt margins, at least 200 pt wide, nothing in the
  fold except "across the fold";
- the privacy rules;
- `BETA_LABEL = beta.3`, with the build number continuing from 10.

New for beta.3:
- **Hosts:**
  - `livetiming.formula1.com`: `/signalrcore` for live, `/static/` for the archive;
  - `api.multiviewer.app` for circuit outlines, credited already in Settings.
  The README's Privacy section is updated to say so.
- **Auth:** the F1 TV subscription token as `Authorization: Bearer`, the same token as the video
  API, for both the hub and the archive. **Timing refusals never sign the user out (controller's
  call):** F1's archive answers 403 for files it hasn't published yet (Android logs it and retries),
  so a 401/403 from any timing request only marks that piece unavailable ("No timing for this
  session", or retry where Android retries). An expired sign-in is still caught by the video side,
  as today.
- **Compressed topics** (`Position.z`, `CarData.z`): base64, then raw deflate with no zlib header.
  Apple's Compression framework isn't on Linux, and DuoCore must be testable there. So DuoCore
  carries its own small raw-deflate decoder (RFC 1951), tested against real archive lines.
  **Builder's call:** the app may switch to the Compression framework if it is measurably faster,
  but both must pass the same tests.
- **Fixtures come from real data.** The owner downloads the São Paulo 2026 race and qualifying
  archives with `spike/timing_recorder.py --archive`, plus the circuit file (owner check T-A). The
  builder trims them to small slices for the tests. Timing data holds no personal data, so trimmed
  fixtures may be committed.
- **The app can't be compiled in the cloud;** the owner's Mac builds are the checkpoints, as before.

## Approaches considered

There was one sensible way: port the Android app's approach. The others were ruled out:

- **A (chosen): F1's own live timing and archive, like Android.** It is the only source that is
  live, complete and works with the viewer's own F1 TV sign-in. Android's code tells us exactly
  which topics, formats and quirks to handle.
- **B: OpenF1 or Jolpica.** Their data terms are non-commercial, with rate limits, and live OpenF1
  is paid. Ruled out for the shipped app (`docs/research/open-source-f1-data.md`); they may still
  be used as development references.
- **C: borrow f1-dash's code.** It is AGPL, which would put the app under that licence. Only its
  ideas are used, such as buffering frames and reading the moment "now − delay"
  (`docs/research/open-source-f1-projects.md`).

## What the owner decided

### Picture time (keeping data in step)

- **Picture time** = the main feed's program date-time (`AVPlayerItem.currentDate()`) + the
  timing offset.
  - The offset defaults to **−7 s**, Android's value, because F1 stamps its video about 7 s
    after its timing.
  - It is one global setting, remembered.
  - The map panel's header has −1 s / +1 s buttons. Settings › Track map shows the offset with
    "Reset to −7 s".
- **Without a program date-time** (rare, older content): picture time = the session start
  (`SessionInfo` / archive) + the player position. The map panel shows "Timing estimated — nudge
  until the cars match", as Android does.
- **Everything reads picture time:** the map at the display's frame rate while it is visible; the
  tower, cards, header and console at 2 Hz; the Scrub Deck when the moment changes. Nothing is
  shown for times after picture time.
- **Tracker delay (added).** The beta.2 owner check found F1's TRACKER feed a little ahead of the
  world feed.
  - Settings › Multiview gets "Tracker delay", in 0.5 s steps. The multiview sync holds the
    TRACKER (and DATA) tiles that much behind the main feed's moment.
  - The default is measured in owner check T-B (the owner reads the lag off the São Paulo replay),
    then set in the next build. It starts at 0.

### Data sources and how they flow

- **Finding the session:** from the F1 TV content's metadata (`emfAttributes`: year, meeting key,
  session key, circuit key, names) and the archive's `{year}/Index.json`, matched the way Android
  does:
  1. the session key;
  2. else the meeting plus the session name in the title;
  3. else, for live broadcasts and the replays right after them, the weekend's session that
     started within the watched moment and the 4 h before it.
  If the index lags, the archive's `SessionInfo.json` is probed in the session's folder.
- **Replays:** the archive's `DriverList.json`, `SessionInfo.json` and the `.jsonStream` topics:
  - Position.z, Heartbeat, TimingData, TimingAppData, SessionStatus, RaceControlMessages,
    TrackStatus, LapCount (races), ExtrapolatedClock;
  - WeatherData, only if the archive has it (added).
  - `CarData.z` is read only when Race Engineer or an onboard's speed readout needs it, and then
    only a window around picture time, never the whole file in memory.
- **Live:** SignalR Core at `/signalrcore`, the same 13 topics as Android plus WeatherData.
  - Negotiate, then the WebSocket, then the handshake; ping every 15 s; reconnect after 5 s.
  - One shared connection per app, released when nothing uses it.
  - The first reply gives each topic's state so far; later messages are deltas, merged the way F1
    sends them (nested objects, and arrays given as objects keyed "0", "1"…).
- **Archive start time:** the median of the first 50 Heartbeat beats. If Position disagrees with
  it by more than 60 s, Position wins (Android's fix for the 2026 Mexico race).
- **Circuit outline:** MultiViewer's `circuits/{circuitKey}/{year}`, with corners and marshal
  sectors. It is kept on the phone per circuit and year.
  - Fallback: an outline traced from one clean lap of positions (Android's rules), also kept per
    circuit.
  - Map load retries after 3, 10, 30 and 60 s, then every 60 s. Meanwhile it shows "Map
    unavailable — trying again…".
- **Live recording (0.99.4, adapted):** while the app is open or playing during a live session,
  every topic except CarData.z and Heartbeat is appended to one file per session in the app's
  caches.
  - Format: Android's, one line per message: topic, UTC milliseconds, whether it is the opening
    snapshot, then the JSON.
  - Flushed every 2 s, and appended to again if the same session is reopened.
  - Rewinding a live session reads this file. When F1's archive for the session appears, the app
    tops up from it, retrying every 2 min for up to 6 h, as Android does.
  - Recordings older than 7 days are deleted. **This is the controller's call.**
- **Errors never stop the video.** Each missing piece fails on its own, with Android's status
  lines:
  - "Connecting to live timing…"
  - "Live timing dropped — reconnecting…"
  - "Live timing is connected, but F1 isn't sending car positions"
  - "No timing for this session"

### Track map

Android's look, in the beta.1 dark style:
- **Outline:** a dark wide stroke under a light thin one, auto-rotated to fill its box, plus a
  user turn in 15° steps with Reset, remembered per circuit.
- **Markings:** corner numbers, and a chequered start/finish line with START and FINISH labels.
- **Car dots:** a dot in the team colour with a dark ring and the three-letter code. Cars in the
  pits or knocked out are dimmed and smaller; a car on a flying lap in qualifying gets a yellow
  ring; retired cars are removed.
- **Movement:** positions are interpolated between samples. A car with a gap of more than 5 s in
  its data is hidden until data returns.
- **Flags:**
  - yellow marshal sectors, with double yellow drawn thicker;
  - safety car and virtual safety car turn the outline yellow, and it pulses when it is ending;
  - a red flag turns the outline red;
  - an "SC" dot just ahead of the leader;
  - a caption such as "Safety car", "VSC ending" or "Red flag · Q3 resumes in 4:12";
  - colours: yellow `#FFD60A`, red `#FF3B30`.
- **Tapping a car** opens its onboard (below). The touch target is 44 pt. Holding a car shows its
  pit window.
- **The panel's header** carries Map / Pit circle, the −1 s / +1 s offset buttons, and ⟲ ⟳ turn.

### Pit circle (Android, including 0.98)

The lap is drawn as a circle in time at the leader's pace, with the finish at the top and the pit
lane as an inner arc.
- **Reference lap:** the average of the leader's last 5 green laps.
  - A lap is green when it has no stop and the track is clear at its midpoint.
  - Before the leader has 5 green laps: their typical lap, then their last timed lap. This is the
    0.98 fix for joining live part-way.
  - Before any lap: "The circle starts once the leader has finished a lap."
- **Pit loss:** the median of this session's clean stops. Otherwise the value kept for this circuit
  on the phone, otherwise 22 s.
- **Gap labels:** gaps to the car ahead by default, or to the leader with a toggle.
- **Tap or hold a car** to measure every gap to it and show its pit window: "If HAM stops now, out
  2.1 s behind NOR".
- **Cars with no position** are placed by their gap.
- **Where it appears:** it is the map panel's second view, and Race Engineer's "Pit now" line uses
  the same calculation.

### Timing tower

- **Refresh:** twice a second, sorted by position.
- **Columns:**
  - position;
  - a team colour bar;
  - the three-letter code;
  - last lap, or "PIT", coloured purple or green for pace;
  - gap to the leader ("Fastest" in qualifying);
  - interval;
  - tyre: a compound ring with its letter, and laps on that set.
- **Qualifying:** the knockout zone is shaded, and knocked-out cars are dimmed.
- **Header (added):**
  - "Lap 23/71" for races, or the session clock otherwise;
  - track status;
  - the weather: air and track temperature, plus a rain mark when it is raining.
- **Battle highlight (added):** when your driver is within 1.0 s of the car ahead or behind for
  two timing updates in a row, both rows glow.
  - A "Battle" chip appears on the map panel's header.
  - Tapping the chip opens the rival's onboard.
  - With no driver picked, this is off.
- **Tapping a row** opens that car's onboard.

### Driver cards and speed

Over any onboard tile, in multiview or a single feed, as on Android:
- **Main line:** a position box, then the number and surname in the team colour, then a running
  lap clock. It shows "PIT" in the pits.
- **After crossing the line:** the lap time for 6 s, coloured purple, green or white.
- **Below:**
  - three sector bars: purple, green, yellow, or grey for none yet;
  - the interval ("Fastest" in qualifying);
  - the speed readout, km/h or mph following the phone's region. It hides when its data is more
    than 5 s old.
- **Showing it:** a card can be hidden per tile from a long-press menu item, "Hide card". It is on
  by default.

### Tap a car to open its onboard

Matching uses the onboard channel's `racingNumber`, against the timing data's car numbers.
- **In multiview:**
  1. A car already showing is made the main feed.
  2. Otherwise it fills an empty spot.
  3. Otherwise it replaces the "least interesting" onboard, as Android ranks them:
     - a car in the pits or knocked out first;
     - then out-laps and cool-down laps;
     - then flying laps;
     - ties go to the one placed longest ago.
  - It never replaces the feed with the sound, or a non-onboard feed such as the world feed,
    tracker or data.
  - If nothing can be replaced: "No free spot — change a feed in the editor."
  - The change goes into the last-used feeds, as a manual swap does.
- **In a single feed:** the player switches to that onboard at the same moment.
- **No onboard for that car:** "No onboard for car 44 in this session."

### Duo layouts with data (owner, option C)

New ⟳ options are added after the existing ones. Each choice is remembered per posture and feed
count, as in beta.2. Data layouts are offered only when the session has timing data. Geometry
follows beta.2's rules and is computed from the screen and fold, never hard-coded.

- **Flat: Director's Desk.**
  ```
  ┌─────────────────────────┬──────────┐
  │                         │  tower   │
  │      main feed          │          │
  │                         │          │
  ├───────┬───────┬─────────┤          │
  │ feed2 │ feed3 │   map   │          │
  └───────┴───────┴─────────┴──────────┘
  ```
  - The tower is a full-height column on the right.
  - The main feed is as large as fits beside it.
  - Below the main feed is a row with up to two other feeds and the map.
  - A fourth feed keeps playing out of sight. **This is the controller's call:** at 200 pt
    minimum width, a fourth tile doesn't fit on the simulator's screen.
- **Book: Data screen.** The left screen holds the feeds:
  - one feed on its own;
  - two stacked;
  - three or four in a 2 × 2 grid (on the simulator these tiles are about 219 pt wide).

  The right screen holds the map on top and the tower below it. Nothing crosses the fold.
- **Laptop.** The top screen keeps the video. The bottom screen (669 × 455 on the simulator)
  holds the data.
  - **One feed:** Scrub Deck is the default in the bottom half, replacing beta.2's labelled
    placeholder.
  - **Two to four feeds:** beta.2's laptop default stays, and ⟳ adds Race Engineer and Scrub Deck.
  - In both, the feeds not on the top screen keep playing out of sight.
- **Floating panels (any fold, any layout, and the single-feed player):**
  - a "Map" button in the controls shows the map and tower as panels over the video;
  - each panel can be dragged and resized, with corner handles and pinch, at 0.9 opacity;
  - position and size are remembered per posture;
  - each panel has its own close ✕;
  - the button turns both back on.

### Race Engineer (laptop, owner option C)

**The top screen shows an onboard.** The first one available:
1. the main feed, if it's an onboard;
2. otherwise your driver's onboard;
3. otherwise the first onboard among the feeds.

If none is available, it shows "Tap a car to pick an onboard" over the main feed.

**The bottom screen is the console:**
```
┌──────────────── console ──────────────────┐
│ 287 km/h  7th   ▮▮▮▮▮▯ throttle   DRS ●   │
│ ▯▯▯▯▯▯ brake    ▬▬▬▬▬▬▬ mini map (HAM ●)  │
│ P4  ▲ NOR +1.2s closing  ▼ RUS -0.8s ↗    │
│ Medium · 18 laps   Pit now → P7 behind ALO│
│ L41 1:32.4 ■■■  L40 1:32.9 ■■□  L39 …     │
│ [ Saved for beta.4: team radio ]          │
└───────────────────────────────────────────┘
```
- **Readouts** from `CarData.z`:
  - speed (channel 2), gear (3) and revs (0);
  - throttle (4) and brake (5) bars;
  - DRS (45), lit when open. **2026 rules replace DRS with active aero and an overtake mode
    (controller's call):** the builder reads channel 45 in the São Paulo 2026 fixture; if it holds
    the active-aero state, the light is labelled "Aero"; if it holds nothing useful, the light is
    left out. It is never shown with a meaning the data doesn't carry.

  They update with picture time and hold the last value if data pauses, greying after 5 s.
- **A mini map** with only this car highlighted.
- **Race lines:**
  - position;
  - the car ahead and behind, with the gap and whether it is closing or growing (the trend over
    the last 3 laps);
  - tyre compound and laps on the set;
  - "Pit now → P7 behind ALO", from the pit circle;
  - the last 5 laps, with sector colours.
- **Tapping the car ahead or behind** switches the top onboard to that driver, using the
  tap-a-car rules.

### Scrub Deck (laptop, owner option C)

**The top screen shows the main feed.**

**The bottom screen has two parts:**
- **An event strip**, laid out by lap. It shows:
  - lights out;
  - pit stops: small ticks for all drivers, prominent ones for your driver;
  - safety car, virtual safety car and red flag periods, as bands;
  - each new fastest lap;
  - retirements;
  - the chequered flag.
- **A lap chart** for races and sprints: one line per driver, position by lap, with your driver
  highlighted. Qualifying and practice show only the event strip, with time instead of laps.

**Controls:**
- **Dragging** anywhere scrubs every feed together, through the multiview controller's seek. While
  dragging, the time is shown.
- **Tapping a marker** jumps to 5 s before it.
- **Tapping a line** highlights that driver and offers "Open onboard".

**No spoilers (controller's call):**
- The chart and the markers are drawn only up to picture time. The future is an empty "fog" that
  fills in as the race plays or as you drag.
- Settings › Track map has "Show the whole race on the Scrub Deck", off by default, for rewatching.

### Timeline marks and the next live programme

- **Timeline marks:** the multiview timeline gets lights-out and chequered marks, plus safety car
  and red flag bands (added). Each sits at the moment of its timing event minus the offset.
- **The next live programme (0.95):**
  - **When it checks:** only while a live session is being watched, every 60 s, through F1 TV's
    "live now" list.
  - **What it offers:** a programme that has started since this one was opened, or any live one
    once this broadcast has ended.
  - **The prompt:** "Switch" or "Not now". "Not now" is remembered for that programme.
  - **Where it shows:** at the top of the video, but not in picture in picture.
  - **On "Switch":** opens that programme with the same multiview or single-feed choice.

## Logic library (DuoCore, tested on Linux)

A new target, `LiveTiming`, Foundation only:
- **Raw-deflate decoder and `.z` decoding.**
- **Stream lines:** parsing `.jsonStream` lines (`HH:MM:SS.mmm` + JSON, BOM stripped).
- **SignalR Core:**
  - parsing the negotiate reply;
  - framing with the 0x1E record separator;
  - message types 1, 3, 6 and 7;
  - the subscribe invocation.
- **Delta merging** of topic state, F1 style.
- **Topic parsers:** DriverList, SessionInfo, Position, TimingData, TimingAppData, TrackStatus,
  RaceControlMessages, LapCount, ExtrapolatedClock, WeatherData, CarData.
- **Time series:**
  - per-car positions with a binary search and interpolation (5 s gap limit);
  - timing snapshots per driver at a given time;
  - car data in windows.
- **Session lookup** from metadata plus `Index.json`, and the archive start time from the
  Heartbeat median (with the 60 s rule).
- **Track geometry:**
  - fit and rotation;
  - progress along the lap;
  - the traced outline and start line (fallback).
- **Flag state** (Android's `TrackFlags` rules and tests).
- **Lap states:** pit, out lap, push, cool-down, knocked out.
- **Race calculations:**
  - the pit circle: reference lap, pit loss, rejoin position;
  - the tower rows;
  - the battle rule;
  - lap chart rows and the event list, cut at picture time.
- **The tap-a-car choice:** which spot an onboard goes to.
- **The live recording format:** writer and reader.
- **Picture-time arithmetic:** the offset, the estimate fallback, and the tracker delay.

**Store additions** (in MultiviewStore, or a new `TimingSettings` store; builder's call):
- the timing offset;
- the map turn per circuit;
- pit loss per circuit;
- panel frames per posture;
- whether to show the whole race;
- the tracker delay;
- the "Hide card" choice per tile.

The layout engine gains the data options:
- `flat.director`;
- `book.dataScreen`;
- `laptop.raceEngineer`;
- `laptop.scrubDeck`.

They return frames for the feed tiles and also the data regions (map, tower, console, deck). Tests
check every region against beta.2's rules.

## App (built and checked by the owner in the simulator)

- **A timing controller** (`@MainActor`, one per watched session), shared by the multiview and
  the single-feed player.
  - It loads the archive or connects live, and holds the parsed series.
  - It publishes picture-time snapshots at 2 Hz, and serves the map on demand at frame rate.
  - Parsing runs off the main actor and only plain values come back, as with every beta.1 and
    beta.2 callback.
- **The live connection:** a shared, reference-counted `URLSessionWebSocketTask` client.
- **The live recorder.**
- **Views:**
  - map panel and pit circle (SwiftUI `Canvas` in a `TimelineView` that pauses when hidden);
  - tower;
  - driver card;
  - console;
  - Scrub Deck;
  - floating panel container;
  - session header;
  - next-live prompt.
- **Settings:**
  - Track map: offset with Reset, show the whole race, units follow region;
  - Multiview: tracker delay.
- **The README's Privacy section** names F1's live timing and MultiViewer's circuit data.

## Testing

- **DuoCore:** every parser and calculation above has tests against trimmed real fixtures from
  São Paulo 2026 (race and qualifying). They include:
  - the Heartbeat and Position start-time rule;
  - delta merges, including arrays as keyed objects;
  - the flag cases from Android's FlagsTest;
  - the pit circle's fallback chain (green laps, then typical lap, then last lap);
  - the no-spoiler cut;
  - the tap-a-car ranking;
  - recorder round trips;
  - the inflater on real lines.
  The tests must run with zero warnings.
- **Layouts:** the new option IDs, against the reference screens of beta.2.
- **App:** each build is checked by the owner (below). Anything not yet checked goes into the
  CHANGELOG's "Untested — check later" list, as in beta.2.

## Work order (builds handed to the owner)

1. **Data on replays:**
   - session lookup, archive loading, picture time and the offset;
   - map with flags, as a floating panel in any fold;
   - timeline marks.
   The owner check includes reading the tracker lag.
2. **Tower, driver cards and speed readout, tap a car to open its onboard, the session header,
   and the battle highlight.**
3. **The Duo data layouts:** Director's Desk, book data screen, and the laptop one-feed Scrub Deck
   spot as a placeholder, plus the tracker delay setting.
4. **Race Engineer and Scrub Deck.**
5. **Pit circle, the live connection, recording, the archive top-up and the next-live offer.**

Each build is pushed as it lands, tested or not (owner's standing instruction).

## Owner checks

- **T-A (before build 1, about 10 minutes on the Mac):** download the São Paulo 2026 race and
  qualifying archives with `spike/timing_recorder.py --archive`, plus the circuit file. Before the
  owner runs it, the script gains `--circuit 14 2026`, the year's `Index.json`, WeatherData, and a
  check of whether the archive serves `CarData.z.jsonStream` in byte ranges (it reports the file
  size and the `Accept-Ranges` answer). Upload the zip.

  The cloud session can't reach these hosts, and the archive needs the F1 TV token, which stays on
  the Mac.
- **T-B:** each build's zero-warnings build and a short simulator check. Build 1's check reads how
  many seconds the tracker feed runs ahead.
- **T-C:** the first live weekend after build 5. Check live timing, recording, rewinding, and the
  next-live offer.
- **T-D, the exit test:** above.

## Open items

- **Whether the archive accepts the token from the iPhone app** as it does from Android and the
  spike. Checked at build 1. If it doesn't, the same request is tried with the Android user agent
  that multiview already uses.
- **CarData archive size per race:** it may be hundreds of MB. Windowed streaming is the plan; if
  F1 serves it only as one file without byte ranges, Race Engineer's replay readouts may need a
  one-time download with a progress bar. Measured with T-A.
- **MultiViewer has no published terms.** Fetch per user, keep on the phone, credit in Settings,
  as decided in the research notes.
- **The tracker delay default:** from T-B.
