# v1.0-beta.5 — Showpieces: design

**Status: DRAFT for the owner, 2026-11-20. Nothing here is approved.** The decisions page is
`docs/design/beta5-questions.html`; each "Question for the owner" below is on it in plain words.
Until the owner answers, every recommendation is only a proposal. Choices the controller made are
marked **(controller's call)**; features beyond the roadmap are **(added)**.

## Goal and exit test

The beta of the four set pieces that only a folding phone does well. Two onboards that reach every
corner together, with the gap between them on the hinge. A strategy table that shows every car's
tyres and answers "what if they pit now?". Today's race beside a classic from the same circuit. A
private pad of your calls for the race, scored as the picture reaches each answer.

**Exit test (roadmap):** "In Mirror Lap, two onboards reach the same corner together on a replay;
Strategy Lab, Then and Now and Prediction Pad work".

**As steps (owner, iPhone Duo simulator, São Paulo 2026 race replay unless stated):**
1. **Mirror Lap.** Open multiview, fold to book (or Settings › Debug › Simulate fold › Book) and
   pick ⟳ "Mirror Lap". Choose the pair the builder names from the fixture (two cars running within
   about 2 s of each other for several laps; chosen in build 23, written in its CHANGELOG entry).
   Watch two laps: each time the front car's onboard turns into Turn 1 (the Senna S), the other
   onboard does too, within about a quarter of a second (O1). The gap on the hinge shows the time
   between them at that point and changes as one gains. Then "Lap against lap": pick the two cars'
   fastest laps; both onboards leave the line together and stay level through the lap.
2. **Strategy Lab.** Open flat, ⟳ "Strategy". Every car's tyre stints show up to the picture, with
   the same compound and tyre age as the tower. Tap a car: "Pit now?" gives the same rejoin as the
   pit circle's "If {CODE} stops now" line, plus the projection chosen in Q6.
3. **Then and Now.** From the same replay, in book, tap "Then and Now". The list shows the classic
   races at Interlagos that F1 TV has (which ones is answered by owner check T-C2). Pick one. Today's
   race plays on the left, the classic on the right; "Line up the starts" puts both at lights out
   (Q8). If F1 TV refuses two videos at once (O3), the right screen shows the fallback chosen in Q9.
4. **Prediction Pad.** Fold to laptop before lights out (rewind to the formation lap) and pick
   ⟳ "Predictions". Make the calls; they lock at lights out. Play or drag the Scrub Deck past the
   chequered flag: each call turns right or wrong as the picture reaches its answer, and the score
   shows. Close and reopen the app: the calls and score are still there.

Live behaviour (Mirror Lap on a live race, Then and Now with a live "Now", live calls) waits for
the first live weekend after the build that adds it, as in betas 3 and 4. The repo doesn't hold
the remaining race dates; if no live session is left in the season when beta.5 is built, these
stay on the "Untested — check later" list until next season (owner decision of 2026-11-20: build
every beta first, then test).

## Why

The roadmap gives beta.5 the Duo ideas 13 (Strategy Lab, open), 15 (Mirror Lap, book), 18 (Then
and Now, book, "needs test") and 21 (Prediction Pad, laptop). The research notes already point at
the techniques: projecting each car onto the circuit for along-track distance (Mirror Lap), and
stints from TimingAppData with a clean-lap filter and the pit-loss walk (Strategy Lab)
(`docs/research/open-source-f1-projects.md`, picks 5 and 6), and F1DB for the classic race at the
same circuit (`docs/research/open-source-f1-data.md`, addition 1).

## Goals

1. **Mirror Lap:** two onboards held level by track position, not by clock, with the gap on the
   hinge. Two modes: two cars racing each other, and any two laps (Q1).
2. **Strategy Lab:** every car's stints, tyre age and pace trend, and a "Pit now?" answer for any
   car, all from data the app already loads.
3. **Then and Now:** today's session beside a classic race at the same circuit, with the starts
   lined up.
4. **Prediction Pad:** your calls before and during a race, locked at the right moment, scored on
   the phone only.
5. **Added:** an era layout drawing in Then and Now (the circuit as it was, beside today's), if
   F1DB's circuit drawings may be used (O6); Mirror Lap on the closed phone as two stacked feeds.

## Non-goals (this beta)

- **Calendar, Kitchen Board, Countdown Lamp, Archive Atlas, the fold-shut recap and the Island
  Flag Ring:** beta.6. Then and Now's classic-race list is built so Archive Atlas can reuse it.
- **Mirror Lap of more than two cars**, or of feeds that aren't onboards.
- **Tyre sets left, tyre allocations, fuel loads, weather forecasts.** None is in the timing topics
  the app reads (`TimingArchive.topics(for:)`); Strategy Lab doesn't guess them.
- **Lap-by-lap data for classic races.** F1's timing archive is only used where it has the session
  (O5); classic races in Then and Now have no map, tower or lap sync.
- **Sharing predictions, leaderboards, accounts.** "Scored privately" (roadmap).
- **New video or data hosts.** See "Data sources" and Q7.

## Anti-goals (a failure even if it technically works)

- **Spoilers.** Nothing — a stint bar, a pit estimate, a prediction result, a gap, the classic
  race's winner — may show what the picture hasn't reached. In Mirror Lap neither onboard may run
  ahead of the picture time the tower and map use (Q2). The classic race's result stays hidden
  until tapped.
- **The video stalling, reloading or losing step** because of Mirror Lap's corrections or a second
  video.
- **A confident number the data can't support.** Pace trends and pit projections are labelled
  "estimate" and disappear when there are too few clean laps.
- **Predictions leaving the phone.**
- **Tokens, signed URLs, the owner's account** in logs, files, errors or commits.

## Constraints

Beta.4's constraints still hold: Swift 6 strict concurrency, iOS 27.1, no third-party dependencies;
DuoCore Foundation-only and tested on Linux; the layout rules (16:9 aspect-fit tiles, 6 pt margins,
at least 200 pt wide, nothing in the fold except "across the fold" — Q3 asks for one exception);
the privacy rules; `BETA_LABEL = beta.5`, build numbers continuing from beta.4's last,
MARKETING_VERSION 1.0.

New: none of the four features needs a new Apple framework. F1DB data (Q7) would be a bundled
resource file (JSON), not a library: the research note's "read it with GRDB or SQLite3" is not
followed, because GRDB is a third-party dependency and SQLite isn't available to a Foundation-only
DuoCore on Linux **(controller's call)**.

## Data sources

### What the app already has (verified in the repo)

- **Car positions:** `Position.z` for every car, decoded and interpolated per car with a 5 s gap
  limit (`Positions.swift`, beta.3). In the committed São Paulo 2026 race slice
  (`Packages/DuoCore/Tests/LiveTimingTests/Fixtures/sp26-race`, about 14 minutes) a sample of all
  cars arrives a **median 0.24 s apart** (10th percentile 0.16 s, 90th 0.40 s), measured for this
  draft.
- **Distance along the lap:** `TrackGeometry` projects a point onto the circuit outline and gives
  its distance along it (`progress(of:)`), on MultiViewer's outline or the outline traced from one
  lap.
- **Laps and line crossings:** TimingData `NumberOfLaps`, and the crossing times the pit circle
  already builds (`PitCircle.crossings`). Together with distance along the lap they give each car's
  race distance at any time.
- **Feeds in step:** every multiview feed checked carries `EXT-X-PROGRAM-DATE-TIME`, all starting at
  the same instant (roadmap, "Verified so far"), and `SyncPolicy` keeps a feed on a target offset
  from the main one (nudge ±3 % within 1 s, seek beyond). The tracker delay already holds TRACKER
  and DATA feeds a fixed time behind the main one (`TrackerDelay.lag`, used by
  `MultiviewController.syncError`); Mirror Lap holds one onboard a changing time behind, through
  the same path.
- **Onboards by car:** `Channel.racingNumber`, and beta.3's tap-a-car placement rules.
- **Stints:** `StintTimeline` from TimingAppData: per car, compound, new or used, `StartLaps`,
  `TotalLaps`, as they change.
- **Lap times and sectors:** `TimingTimeline` (last and best lap, sector colours, retired, in pit).
- **Pit stops, pit loss and the rejoin:** `PitCircle.pitStops`, `pitLossMs` (this session's
  clean stops, else the circuit's stored value, else 22 s) and `PitCircle.rejoin` ("If HAM stops
  now, out 2.1 s behind NOR").
- **Events:** `RaceEvents` (lights out, pits, safety car and VSC bands, fastest laps, retirements,
  chequered flag) and `TrackFlags`.
- **The catalogue:** `Catalogue.raceReplays(season:)` (full race replays of a season),
  `seasonVideos(season:)` (a season before 2018 as a flat list, replays first),
  `archiveRaces()` (the most watched race replays of every season), `TimingRef.circuitKey` from a
  video's `emfAttributes` when F1 TV gives one. The Archive room lists seasons back to 1981, but
  that is only the app's (and Android's) first-season constant, not a check of what F1 TV holds.

### What is not known yet (probes and open items)

- **Which seasons have timing and full onboards (O5).** Mirror Lap and Strategy Lab need F1's
  timing archive and, for Mirror Lap, two onboard feeds. The 2022 Australian GP returned one
  multiview feed (roadmap), and the timing archive's coverage by season isn't recorded. Both
  features show "Not available for this race" where either is missing.
- **Whether F1 TV plays two different videos at once on one account (O3).** Then and Now needs it.
- **What F1 TV holds from 1981 to 2017, and how it names it (O4).** Then and Now needs, per
  circuit, the classic races that have a full-race video.
- **F1DB (O6).** The subset's real size, and whether its circuit drawings (in its repository, not
  in its release files) carry the same CC BY 4.0 licence as its data.

### Classic races by circuit (Q7)

Then and Now needs "every race held at this circuit, and which of them F1 TV has". F1 TV's data
alone can't say which races were at a circuit: Grands Prix change names (the Brazilian GP is now
the São Paulo GP) and some names moved between circuits over the years, and `circuitKey` is
only known where F1 TV gives `emfAttributes` (O4). Options:
- **F1 TV only:** match by Grand Prix name; misses renamed races and can't list races F1 TV lacks.
- **F1DB, bundled (recommended):** a subset (circuits, races, winners, pole, fastest lap, pit stop
  counts, Driver of the Day where F1DB has it) built from F1DB's release on the Mac by a script in
  `spike/`, saved as JSON in the app's resources, credited in Settings › About ("Race history:
  F1DB, CC BY 4.0", with a link). **No new host:** the app never contacts F1DB; the file is updated
  with app releases. F1DB data is "commercial-safe" and needs credit (research note).
- **A hand-made table** of circuits and race names for the circuits on the current calendar.

The same answer feeds beta.6's Archive Atlas, so it is asked on both decisions pages.

## Features

Each feature gives: **Sees**, **Data** (with picture time), **Copy**, **Replay / live** and
**Duo**.

### 1. Mirror Lap (book)

- **Sees:** a ⟳ book layout, "Mirror Lap": one onboard on each screen, as large as fits. The gap
  sits on the hinge (Q3): the recommended form is a thin strip down the fold that fills in the
  Gap Thermometer's colours (blue over 3 s, amber 1–3 s, red under 1 s) with a small pill at its
  top: "+0.84" and ▼ closing or ▲ growing. A one-line header over each picture: code, team colour,
  position, lap. Tap a header to change that car. Two modes (Q1):
  - **Racing:** two cars in the race; the default pair is your driver and the nearer car ahead or
    behind (as the Gap Thermometer's). The gap is how much later the car behind reaches the place
    where the car ahead is.
  - **Lap against lap (added detail of the roadmap idea):** pick any two laps of the session (two
    drivers' fastest laps, or one driver's lap 10 and lap 50). Both onboards start at the line
    together and stay level; the gap is the running lap-time difference at that point ("−0.21"),
    like F1's own delta. The later of the two laps keeps the real moment; the earlier one is
    replayed beside it.
- **How it stays level:** each car's race distance over time comes from its positions projected on
  the circuit plus its line crossings. At each display tick, for the car whose onboard keeps the
  real moment (Q2: recommended, the car behind), take its race distance `d` at picture time; find
  when the other car was at `d` (a binary search on its distance series, interpolated between
  samples); the difference is the gap, and the other onboard's target offset. `SyncPolicy` then
  holds that onboard on the target offset (rate nudges within 1 s, a seek beyond, as beta.2). The
  gap changes by a few tenths a corner, so after the first seek the corrections are nudges.
- **Edge cases (controller's call):** a car in the pit lane, retired, or without position data for
  over 5 s pauses the mirror: "Mirror paused — {CODE} in the pits" / "{CODE} is out — pick another
  car"; the held-back onboard then plays in plain step. Gaps over one lap: "Too far apart to mirror
  — pick a closer car". Safety car periods work as normal (gaps shrink). Lap 1 starts once both
  cars have crossed the start line.
- **Feeds:** both onboards must be in the session. If one isn't among the playing feeds, it comes
  in by beta.3's tap-a-car rules. The sound stays with one feed (beta.2's rule), by default the
  onboard that keeps the real moment.
- **Data:** Position.z, TimingData (laps, crossings, in pit, retired), DriverList, the circuit
  outline. Picture time follows the onboard that keeps the real moment.
- **Copy:** "Mirror Lap"; "Racing" · "Lap against lap"; "Pick two cars"; "Pick two laps"; "Fastest
  laps"; "{CODE} is {gap} behind here"; "Mirror paused — {CODE} in the pits"; "Too far apart to
  mirror — pick a closer car"; "Mirror Lap needs two onboards and timing — not available for this
  race"; first time only: "Both cars reach each corner together. The gap on the hinge is the time
  between them."
- **Replay / live:** replay tests all of it. Live works only in Q2's recommended form (the car ahead
  is the one held back, so nothing needs to come from beyond the live edge); checked at the first
  live weekend after the build.
- **Duo:** whether the crease strip reads on the real hinge (Q3), and two onboards' decoding load in
  book (two feeds, the other two kept playing out of sight as beta.2 does).
- **Closed phone and other iPhones (added, controller's call):** the closed layout's two stacked
  feeds (beta.4) with the gap pill between them.

### 2. Strategy Lab (open flat)

- **Sees:** a ⟳ flat layout, "Strategy" (Q4: recommended, the feeds on the left screen, the Lab on
  the right). The Lab, top to bottom:
  - **Stints:** one row per car in race order: position, code, then a bar per stint in the
    compound's colour (S red, M yellow, H white, I green, W blue), solid for new tyres, hatched for
    used, with the lap number at each stop; the running stint grows with the picture; after it, the
    race's remaining laps in fog.
  - **Pace (Q5):** tap a car: its laps in this stint as dots, clean laps filled, and a trend line
    with "+0.07 s a lap (estimate)". Hidden with fewer than 5 clean laps in the stint.
  - **Pit now? (Q6):** for the tapped car (your driver by default): "Out P7 · 1.4 s behind ALO ·
    2.0 s ahead of GAS" (the pit circle's rejoin), and the recommended projection for "in 1 lap",
    "in 2 laps", "in 3 laps", from each car's pace trend. "A free stop" when the gap to the car
    behind is more than the pit loss. Under a safety car or VSC: "A stop now costs less" with no
    number, unless this session already has stops under one to measure **(controller's call)**.
  - Pit loss in use, small: "Pit loss 21.8 s (this race, 6 stops)" or "(Interlagos, stored)".
- **Clean laps (controller's call, FastF1's `IsAccurate` idea reimplemented):** not an in or out
  lap, track clear for the whole lap, all three sectors present, not lap 1, the previous lap not
  under a safety car, and within 107 % of the stint's middle lap.
- **Pace trend:** a straight-line fit of clean lap times over the stint's laps with a fixed fuel
  allowance per lap. The allowance comes from the research note's reading of f1-race-replay (about
  0.032 s per kg at 1.6 kg a lap); it is checked against the São Paulo 2026 fixture before use and
  is only an estimate (the copy says so). f1-race-replay has no LICENSE file, so only the idea is
  used.
- **Data:** StintTimeline, TimingTimeline, pit stops and pit loss, PitCircle's rejoin, TrackFlags;
  all cut at picture time.
- **Copy:** "Strategy"; "Stints"; "Pace"; "Pit now?"; "Out P{n}"; "{gap} behind {CODE}"; "{gap}
  ahead of {CODE}"; "In 1 lap" / "In {n} laps"; "A free stop"; "A stop now costs less (safety
  car)"; "estimate"; "Not enough clean laps yet"; "Pit now? works in races and sprints."; "Strategy
  needs timing — not available for this session".
- **Sessions:** races and sprints; qualifying and practice show the stints only (runs of laps on a
  set) **(controller's call)**.
- **Replay / live:** replay tests it all; live adds nothing new.
- **Duo:** readability of the stint rows at 22 cars on half the inner screen (about 455 pt wide in
  the simulator).
- **Other postures (controller's call):** the Lab is also a floating panel from a "Strategy"
  button, like the map, so it works on any iPhone.

### 3. Then and Now (book)

- **Sees:** a "Then and Now" button in the player and multiview controls (only where the session
  has a circuit). It opens a list: "Races at {circuit}" with each year, the Grand Prix's name then,
  and whether F1 TV has it ("Watch" or "No video on F1 TV"). Pick one. In book: today's session on
  the left screen (its main feed, the rest paused), the classic on the right. Under each, a strip:
  - Now: "2026 · Lap 23/71".
  - Then: "1991 · Brazilian Grand Prix", "Show result" (winner, pole and fastest lap appear only on
    tap: the classic race's result is a spoiler too) **(controller's call)**, and, if O6 allows, the
    circuit as it was drawn beside today's outline **(added)**.
  - "Line up the starts" (Q8).
  One sound at a time: each side's speaker button moves it.
- **Line up the starts (recommended in Q8):** Now's lights-out time comes from timing. The classic
  has no timing, so the first time, the owner scrubs Then to the start and taps "Mark lights out";
  the mark is remembered per video. "Line up the starts" seeks both to their lights out; from then
  on both play at normal speed and drift apart as their laps differ. Then's strip shows "About lap
  {n}" from the race's length and the winner's time in F1DB (Q7), labelled as an estimate.
- **Picking the default classic (controller's call):** the one last picked at this circuit, else
  the most watched one there (the order of `archiveRaces()`), else the oldest F1 TV has.
- **Data:** the classic-race index (Q7), F1 TV's catalogue for the video, timing for Now only.
- **Copy:** "Then and Now"; "Races at {circuit}"; "No video on F1 TV"; "Show result"; "Mark lights
  out"; "Line up the starts"; "About lap {n} (estimate)"; "F1 TV won't play two races at once on
  this account" (Q9's fallback line).
- **Replay / live:** replay first. "Now" live needs two videos at once (O3) and FairPlay for the live
  one beside a clear classic; checked at the first live weekend after the build.
- **Duo:** two different videos decoding at once in book; the real halves.
- **Other iPhones and closed (controller's call):** the two stacked, closed-layout style.

### 4. Prediction Pad (laptop)

- **Sees:** a ⟳ laptop layout, "Predictions": the video on the upright half, the pad on the flat
  half (the Scrub Deck's place). Before lights out, the calls (Q10, recommended set):
  - **Before the start** (lock at lights out in picture time): winner; podium (three in order);
    fastest lap; safety car (yes / no); your driver's finish (a position or "Out"; hidden with no
    driver picked).
  - **During the race:** "Next to pit" (pick a car any time; locks on tap, resolves at the next pit
    entry) and "Safety car in the next 10 laps?" (yes / no; resolves after 10 laps or at a safety
    car).
  Calls are big tap targets: a grid of driver codes in team colours, as the tower orders them.
  Each call shows "Locked" once locked, then a tick or a cross when the picture reaches its answer,
  and the points.
- **Scoring (Q11, recommended):** winner 5; each podium place exact 3, on the podium but wrong
  place 1; fastest lap 3; safety car 2; your driver exact 3, within two places 1; next to pit 2;
  safety car in 10 laps 2 **(controller's call: the values)**. A season page sums your races:
  "Your calls" in Settings, with "Clear my calls".
- **Replays:** the pad works on replays, locking at lights out in the picture; the card notes
  "Replay" next to its score, so a season total can be read with or without them
  **(controller's call)**.
- **Data:** TimingData positions at the chequered flag (the classification as timing shows it, not
  any later penalty), RaceEvents (fastest lap, pit entries), TrackFlags (safety car, VSC is not a
  safety car for the call **(controller's call)**), LapCount; all at picture time.
- **Copy:** "Predictions"; "Your calls"; "Winner"; "Podium"; "Fastest lap"; "Safety car?"; "{CODE}
  finishes"; "Next to pit"; "Safety car in the next 10 laps?"; "Locks at lights out"; "Locked";
  "{n} points"; "Replay"; "Your calls stay on this iPhone."; "Clear my calls".
- **Sessions:** races and sprints (Q10's option C adds qualifying).
- **Replay / live:** replay tests all of it; live adds nothing new.
- **Duo:** laptop pose on the real hinge; tap targets at least 44 pt (the design pass).
- **Other postures (controller's call):** a "Predictions" sheet from the controls.

## Settings

- **Mirror Lap:** "Gap on the hinge" (on; off moves the pill to the top of the right screen).
- **Strategy:** "Pit loss" shows the value in use with "Reset" for the circuit's stored value.
- **Then and Now:** "Forget lights-out marks".
- **Predictions:** "Predictions" (on), "Your calls" (season totals), "Clear my calls".
- **Remembered:** Mirror Lap's last pair and mode, the classic last picked per circuit, the
  lights-out mark per classic video, the calls per session.

## Logic library (DuoCore, tested on Linux)

- **Mirror sync:** race-distance series per car from positions, outline and crossings; time at a
  distance (interpolated); the gap and target offset for both modes; pause reasons; the one-lap
  limit.
- **Strategy:** stint rows cut at picture time, the clean-lap filter, the pace fit with the fuel
  allowance, rejoin projections for 1–3 laps, "free stop".
- **Classic index:** reading the bundled F1DB subset; races by circuit; matching a race to F1 TV
  catalogue items (by season and name, then `circuitKey` where given); the "about lap" estimate.
- **Prediction card:** the calls, locking, resolving at picture time, scoring, the season sum;
  JSON for the phone.
- **Layout engine:** `book.mirror`, `flat.strategy`, `book.thenAndNow`, `laptop.predictions`.

## App (built and checked by the owner in the simulator)

- A Mirror Lap controller on the multiview controller: the pair, the target offset per tick, and
  the hinge strip view.
- The Strategy Lab view (Canvas for the stint rows), the Then and Now screen with a second single
  player beside the session, the Prediction Pad view, and the store for calls.
- A `spike/` script that builds the F1DB subset JSON on the Mac (if Q7 is B).
- Settings › About credit for F1DB (if Q7 is B); the README's Status and Credits.

## Privacy

- **No new hosts.** Mirror Lap and Strategy Lab use F1's live timing as today; Then and Now uses
  F1 TV for both videos; F1DB is a file inside the app (Q7), never fetched by the app.
- **Your calls stay on the phone,** in the app's own storage, cleared by "Clear my calls" or
  deleting the app. Like any app data they are part of the phone's own backup; the app never
  sends them anywhere.
- **The README** gains a Credits line for F1DB (if used).

## Testing

- **DuoCore:** the mirror sync on the committed São Paulo race slice (distance series, time at a
  distance, the gap for a pair, pit and retirement pauses); the clean-lap filter and pace fit on the
  slice; the rejoin projections against the pit circle's own; the classic index on a small
  committed F1DB sample (a few circuits); the prediction card (locking, resolving, scoring, a
  rewind before lights out unlocking nothing already locked). Zero warnings.
- **App:** each build checked by the owner; anything unchecked goes into the CHANGELOG's
  "Untested — check later".

## Work order (builds handed to the owner)

23. **Mirror Lap:** the sync engine, `book.mirror`, the hinge strip, both modes. The exit test's
    first part can be run after this build.
24. **Strategy Lab:** stints, pace, Pit now?, the floating panel.
25. **Then and Now:** the F1DB subset (if Q7 is B) and its script, the races list, the second
    player, line up the starts, the fallback (Q9).
26. **Prediction Pad:** calls, locking, scoring, season page.
27. **Fixes from the beta.5 review,** as beta.3's build 16.

Each build is pushed as it lands, tested or not (owner's standing instruction). Build numbers are
indicative: they follow on from beta.4's last build.

## Owner checks

- **T-C1 (before build 25, about 5 minutes on the Mac):** a `spike/` probe asks F1 TV to play two
  different race replays at once (São Paulo 2026 and one classic), keeps both playing for 2 minutes,
  and reports each answer's HTTP status and any error text. Answers O3.
- **T-C2 (before build 25, about 10 minutes on the Mac):** a probe lists, for every season from 1981
  to 2017, the full-race videos F1 TV has (title, year, `emfAttributes` circuit key if any) and,
  for 2018 to 2026, the race replays with their circuit key. Only titles and counts are shared.
  Answers O4 and part of O5.
- **T-F (before build 25, if Q7 is B):** run the F1DB subset script; report the file size and
  F1DB's licence note for its circuit drawings. Answers O6.
- **T-B:** each build's zero-warnings build and a short simulator check.
- **T-D, the exit test:** above.

## Open items (confirmed while building or by a probe, not owner decisions)

- **O1. Mirror Lap's accuracy.** Positions arrive a median 0.24 s apart (measured); interpolated,
  the expected error at a corner is under 0.1 s, but it isn't measured against the picture. The
  build 23 check reads it off two onboards at Turn 1 by eye.
- **O2. Whether every onboard matches timing at the same −7 s offset** as the world feed. All feeds
  start at the same program date-time (verified), but no onboard has been checked against timing
  at a corner.
- **O3. Two videos at once on one F1 TV account** (T-C1).
- **O4. F1 TV's classic races:** which seasons from 1981 to 2017 have full races, how they are
  titled, and whether they carry a circuit key (T-C2).
- **O5. Which seasons have F1's timing archive and full multiview onboards.** `SeasonView`'s 2018
  line is F1 TV's weekend pages, not timing; the 2022 Australian GP had one multiview feed.
  Mirror Lap and Strategy Lab say "Not available for this race" when either is missing; T-C2
  lists race replays by season so the builder can sample a few.
- **O6. F1DB:** the subset's size (the research note's "single-digit MB" is a guess) and the
  licence of its circuit drawings (in the repository, not in the release files).
- **O7. Two onboards decoding in book on the real Duo** while two more play out of sight (beta.2
  played four in the simulator; the hardware limit is beta.2's own open item).

## Risks

- **Mirror Lap jitter:** a target offset that moves every tick could make the held-back onboard
  stutter. The offset is smoothed over about a second and corrected by rate, not seeks, after the
  first alignment.
- **Strategy estimates misread as forecasts.** Labelled "estimate", hidden when thin, never shown
  for wet laps.
- **Then and Now blocked by F1 TV (O3)**, or by thin classic coverage (O4). Q9's fallback keeps the
  feature useful as a side-by-side of today with the classic's facts and layout.
- **F1DB credit forgotten:** the About line and README credit are in build 25's checklist.

## Questions for the owner

1. **Mirror Lap: which laps.** Two cars racing each other now, any two laps of the session (two
   fastest laps, or one driver early and late), or both. **Recommendation:** both; the same engine
   does both, and "lap against lap" is the showpiece in qualifying.
2. **Mirror Lap: which car keeps the real moment.** The car behind (the car ahead is replayed a
   moment late), or the car ahead (the car behind is shown a moment early). **Recommendation:** the
   car behind. Nothing then runs ahead of the timing, so there are no spoilers and it can work live.
3. **Mirror Lap: where the gap shows.** A pill at the top of the hinge, a coloured strip down the
   hinge with the pill (the roadmap's "gap on the hinge"; an exception to "nothing in the fold"), or
   under each picture. **Recommendation:** the strip and pill, checked on the real hinge in beta.7.
4. **Strategy Lab: where it lives.** Open flat with the feeds on the left and the Lab on the right; a
   full-screen Lab with a small picture; or a floating panel anywhere. **Recommendation:** open flat,
   half and half, plus the floating panel on other iPhones.
5. **Strategy Lab: how much estimating.** Stints and "Pit now?" only; plus each stint's pace trend;
   or also a "best lap to stop". **Recommendation:** stints, Pit now? and the pace trend, marked as
   an estimate. A best lap to stop needs tyre data F1 doesn't send.
6. **"Pit now?": what it answers.** Now only; now and in 1, 2 or 3 laps; or also a safety-car
   version. **Recommendation:** now and in 1–3 laps; a safety-car note without a number.
7. **Race history from 1981 (also beta.6's Archive Atlas).** F1 TV's own lists only; a free, open
   record of every race (F1DB) copied into the app with credit; or a hand-made list.
   **Recommendation:** F1DB inside the app, no new website contacted, credited in About.
8. **Then and Now: lining up the races.** Play independently; line up the starts once; or keep both
   at the same lap by jumping the classic. **Recommendation:** line up the starts; jumping is jarring.
9. **If F1 TV plays only one video at a time.** The classic becomes a card (result on tap, its
   circuit drawing); the two take turns; or Then and Now waits. **Recommendation:** the card.
10. **Prediction Pad: which calls.** Five before the start; plus two during the race; plus
    qualifying. **Recommendation:** five before the start and two during, races and sprints.
11. **Prediction Pad: scores.** Points and a season total on the phone; plus a picture to share; or
    just right and wrong. **Recommendation:** points and a season total, nothing shared.

## Sources

- Repo: `docs/roadmap.md` (Duo ideas, "Verified so far", the research notes' licence lines); the
  beta.2–beta.4 specs and the beta.3 rulings; `README.md`; `DuoApp/Rooms/ArchiveRoom.swift`,
  `SeasonView.swift`; `Packages/DuoCore/Sources/F1TV/Catalogue.swift`, `Models.swift`,
  `TimingRef.swift`; `Packages/DuoCore/Sources/LiveTiming/` (`Positions.swift`,
  `TrackGeometry.swift`, `Timing.swift` (`StintTimeline`), `PitCircle.swift`, `RaceEvents.swift`,
  `TimingArchive.swift`); `Packages/DuoCore/Sources/Multiview/SyncPolicy.swift`,
  `LayoutEngine.swift`; the committed São Paulo 2026 race fixture (position spacing measured).
- `docs/research/open-source-f1-projects.md` (FastF1's `IsAccurate`, f1-dash's
  `calculatePosition`, f1-race-replay's fuel model; licences) and
  `docs/research/open-source-f1-data.md` (F1DB, f1-circuits, OpenF1, Jolpica terms).
