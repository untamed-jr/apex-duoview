# v1.0-beta.4 — Radio and the closed phone: design

**Status: DRAFT for owner review.** Written 2026-11-18 by the controller; nothing here is approved
yet. Owner decisions are under "Questions for the owner", each with a recommendation. Choices the
controller made are marked **(controller's call)**; features beyond the roadmap are **(added)**.

## Goal and exit test

The beta that adds the drivers' voices and makes the closed phone useful. Team radio arrives by
lap, in step with the picture, with a transcript made on the phone. Closed, the phone is a glance
companion: one driver's radio, a gap meter, and an event card that takes you to the moment when
you open it. Haptics give flags a feel. Half-open like a book: one driver's onboard beside their
logbook, or two rivals, one in each ear.

**Exit test (roadmap):** "Team radio plays by lap with transcripts; the closed-phone modes work in
the simulator; haptics fire on flags".

**As steps (owner, iPhone Duo simulator, São Paulo 2026 race replay unless stated):**
1. **Radio by lap.** Open the Radio panel and play from lap 17 to lap 23. Only clips the picture
   has reached are listed, under their lap. ANT (8 clips in this race), NOR (5) and RUS (5) have the most.
   Tapping a clip plays it while the feeds go quiet; its transcript shows under it (O4 covers a
   simulator that can't transcribe).
2. **Closed-phone modes.** Close the simulator (or Settings › Debug › Simulate fold › Closed).
   Swipe up to the Radio Scanner and pick ANT: on laps 19, 20 and 22 his clips play when the
   picture reaches them and the transcript scrolls. Swipe up to the Gap Thermometer: its colour follows the gap. A yellow
   flag (laps 17 and 20) brings up an event card; unfolding jumps every feed to 5 s before it, and "Back to where
   you were" returns.
3. **Haptics on flags.** The race's yellow flags, and the two red flags in the São Paulo 2026
   qualifying replay, each fire their haptic as the picture reaches them (how this is checked in
   a simulator without haptics is Q2). The race had no safety car or VSC; those are covered by
   DuoCore tests and "Feel it" in Settings.

Live behaviour (live radio, haptics on a live stream) is checked at the first live weekend after
the build that adds it, and listed as untested until then, as in beta.3. Beta.3's own live check
(T-C, Las Vegas, November 19–22) is still pending and comes first.

## Why

The roadmap gives beta.4 the closed and radio Duo ideas: 4 (haptic vocabulary), 6 (hinge as an
audio mixer), 7 (Radio Scanner), 8 (Unfold to See), 9 (Gap Thermometer), 16 (Onboard and Logbook)
and 17 (Ear-Matched Rivals). Android's team radio panel, transcribed on the phone, is the last
Android timing feature to carry over; Race Engineer keeps a spot for it ("Saved for beta.4: team
radio").

## Goals

1. **Team radio from F1's live timing, like Android:** every clip F1 publishes, by lap, in step
   with the picture, tap to hear, with a transcript made on the phone.
2. **The closed phone as a companion:** Picture (beta.2's closed layout), Radio Scanner and Gap
   Thermometer, with Unfold to See over all three.
3. **A small haptic vocabulary**, one feel per event, learnable.
4. **Book layouts:** Onboard and Logbook, and Ear-Matched Rivals.
5. **The hinge as an audio mixer**, opt-in, in book and laptop.
6. **Added:** radio ticks on the Scrub Deck (the README promises radio on the touch timeline),
   and radio in Race Engineer's saved spot.

## Non-goals (this beta)

- **Island Flag Ring, fold-shut recap, lock-screen and Dynamic Island alerts:** beta.6. Unfold to
  See and haptics work while the app is on screen (screen off is Q10).
- **Other radio sources.** OpenF1's radio is ruled out by its terms
  (`docs/research/open-source-f1-data.md`). The onboards' own radio audio track is Q1.
- **Transcripts in other languages, or translation.** Radio is English; Android asks for English.
- **The opening-screen intro:** not planned here (Q9).
- **Anything that listens to the microphone.** Voice questions (idea 27) stay a beta.7 experiment.

## Anti-goals (a failure even if it technically works)

- **Radio ahead of the picture.** No clip, transcript, count, badge, list order, haptic or card
  may reveal a clip or event the picture hasn't reached.
- **Radio audio leaving the phone:** no server speech service, no upload.
- **The video stalling, reloading or losing step** because of downloads, transcription, haptics
  or the mixer.
- **Haptics that nag** through a busy session.
- **Radio audio in the repository.** Clips are F1's recordings and the repo is public. Tests use
  the timing lines (already committed, trimmed), never mp3 files.
- **Tokens or signed URLs** in logs, files, errors or commits.

## Constraints

Beta.3's constraints still hold: Swift 6 strict concurrency, iOS 27.1, no third-party
dependencies; DuoCore Foundation-only and tested on Linux; the layout and privacy rules;
`BETA_LABEL = beta.4`, build numbers from 17, MARKETING_VERSION 1.0.

New: the app (not DuoCore) uses Speech (`SpeechAnalyzer`, `SpeechTranscriber`), Core Haptics
(`CHHapticEngine`) and `AVAudioEngine` (clip playback, so a clip can be panned to one ear). No new
hosts (Privacy). The cloud session can't reach F1's hosts, so the owner's Mac fetches sample clips
(T-A4).

## Data sources

### F1's TeamRadio topic (from the repo's real data)

- **Shape:** each message adds `Captures`; each capture has `Utc` (when F1 published the clip),
  `RacingNumber` and `Path` (`TeamRadio/ANT_12_20261108_141229.mp3`). The opening state is a list;
  later messages are objects keyed "2", "3"… (São Paulo 2026, `spike/beta3-fixtures/`).
- **Audio:** `https://livetiming.formula1.com/static/` + the session's `Path` (SessionInfo) + the
  capture's `Path`, an MP3 (Android's `radioBase + clip.path`).
- **How much:** the São Paulo 2026 race has **30 clips from 8 drivers** in about two hours (ANT 8,
  NOR 5, RUS 5, VER 4, HAM 3, HAD 3, LEC 1, GAS 1); qualifying 36 from 15. Most drivers have no
  radio in a race, so every feature has an empty state.
- **Timing:** `Utc` is 6–43 s after the file name's time in qualifying (median 20 s) and 11–50 s
  in the race (median 34 s), leaving out the opening list's older pre-race clips.
- **Day-prefixed lines** (the 2026 Mexico race's radio) already parse in `StreamLine`.

### Where it comes from in the app

- **Replays:** add `TeamRadio` to `TimingArchive.topics(for:)` as an optional topic (missing
  today, so replays have no radio yet).
- **Live:** already there: the hub subscribes to it, the recorder writes it, the archive top-up
  (`Backfill.topics`) reads it. Only the parser and views are new.
- **Clip audio:** downloaded once, when first needed (to play or transcribe), kept in
  `Caches/radio/{sessionKey}/`, deleted after 7 days. Fetched **without the F1 TV sign-in**, as
  Android does; if F1 refuses (T-A4), once more with it, to the same host only. A refusal never
  signs you out.

### Picture time for radio

- **A clip exists once picture time ≥ its `Utc`.** Before that it isn't listed, counted, badged
  or played (Android: `clip.utc <= now`). `Utc` is the later, safe time.
- **Lap label:** the driver's lap at `Utc`, as Android's `lapAt` (lap count + 1), so it can be a
  lap after the words were said **(controller's call: Android parity)**. Before lights out "Before
  the start"; after the flag "After the flag"; qualifying "Q2 · 8:12 left"; practice the elapsed
  time.
- **Rewinding** past a playing clip's `Utc` stops it; later clips disappear.
- **"Show the whole race"** also shows the whole radio list: one switch for all spoilers
  **(controller's call**, as beta.3 ruled for that setting's scope).
- **Transcribing ahead:** up to 2 minutes beyond picture time, as Android, so text is ready; it
  shows only when its clip does.

### Transcripts on the phone

- **Engine:** `SpeechTranscriber` in a `SpeechAnalyzer`, fed the file with
  `analyzeSequence(from:)`. Locale from `supportedLocale(equivalentTo:)`, en-GB first, then en-US.
  The model, if missing, is installed with `AssetInventory.assetInstallationRequest(supporting:)`
  (a system download). If `SpeechTranscriber.isAvailable` is false: `DictationTranscriber`, then
  `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`. A fallback is used only if it
  runs on the phone (O7).
- **On the phone only, no server fallback.** Android falls back to Google's speech service; this
  app doesn't, so a phone without an on-device English engine plays clips without text (Q8).
- **Hints:** `AnalysisContext.contextualStrings` (whether `SpeechTranscriber` uses them is O7) with drivers' names and teams from DriverList and
  Android's radio words ("box box", "copy", "lift and coast", …).
- **One clip at a time,** nearest the picture first; a clip not done within 45 s is skipped; three failures in a row
  wait 2 minutes (Android's rules). Results are kept by clip path, so a replay is transcribed once;
  nothing recognised stores "(no words recognised)".
- **No microphone permission** (Android needs one): the app reads files. Whether iOS still asks for
  speech-recognition permission for files is O1. If it does, the Info.plist reason is "Team radio
  clips are turned into text on this iPhone. The app never listens to you." and the panel shows
  "Allow speech recognition in Settings to see transcripts".

### Other data (loaded since beta.3)

TimingData, TimingAppData, TrackStatus, RaceControlMessages, LapCount, and beta.3's pit stops,
battle rule and race lines, all cut at picture time.

## Features

Each feature gives: **Sees** (in simple words), **Data** (with picture time), **Copy**,
**Replay / live** and **Duo**.

### 1. Team radio by lap, with transcripts

- **Sees:** a "Radio" button beside Map (multiview controls and single-feed player) opens a
  floating panel, like beta.3's map and tower. Oldest clip at the top, newest at the bottom, the
  list following new ones; a small "Lap 23" header per lap. Each row: team-colour bar, three-letter
  code, up to two lines of transcript, ▶. A new clip flashes once, softly. Chips: "All" · "My
  driver" · a driver. Tap a row to play: the feeds go silent until it ends (Android's
  `RADIO_DUCK = 0`); tap again to stop. Clips follow the feeds' speed, as Android.
  - Race Engineer's saved spot: the engineered driver's last three clips with ▶.
  - The Scrub Deck: a small tick per clip, a taller one for your driver, drawn only up to the
    picture (behind the fog, as every marker); tap to jump 5 s before.
- **Data:** TeamRadio captures at picture time ≥ `Utc`; lap at `Utc`; DriverList; transcripts.
- **Copy:** title "Team radio"; close "Hide team radio"; before the first clip "Radio shows up here
  as it happens." (on replays and live alike, so it never hints whether radio is coming); "No radio from {CODE} yet."; "Transcribing…"; "(no words
  recognised)"; "Getting the speech model ready…"; "Transcripts aren't available on this iPhone —
  clips still play"; "Couldn't load this clip"; "Couldn't play that radio clip".
- **Replay / live:** replay tests all of it. Live needs a weekend: clips from the hub, radio
  replayed from the recording after a rewind, and the top-up filling radio from before the join.
- **Duo:** nothing specific; transcription speed and heat need a real iPhone (any).

### 2. Radio Scanner (closed)

- **Sees:** closed, the outer screen has three pages, **Picture**, **Radio Scanner** and **Gap
  Thermometer**. Swipe up or down between them (dots on the right edge); swipe left or right to
  change what the page shows, as Picture already changes the feed (Q3). The feeds keep playing
  out of sight, with sound. The Scanner follows one driver: code, team colour, position and lap on
  top; their clips so far as a large-type transcript that scrolls; one big ▶ / ■. A new clip plays
  by itself when the picture reaches it (Q4). Left/right changes the driver in race order; the
  default is your driver, else the leader.
- **Data:** that driver's clips at picture time; position and lap from TimingData. The swipe order
  is race position, never "drivers with radio" (that would reveal who is about to speak).
- **Copy:** "Radio Scanner"; "No radio from {CODE} yet. Swipe for another driver."; with auto-play
  off, "New radio — tap to play"; first time only, "Swipe up or down for Picture, Radio and Gap".
- **Replay / live:** replay tests it all (ANT, São Paulo 2026); live adds clips arriving while
  closed.
- **Duo:** the outer screen's real size, readability at arm's length, and how the swipes feel.

### 3. Unfold to See (closed)

- **Sees:** while closed, on any page, an event slides in as a card at the top; older cards stack
  behind ("+2"). Unfold while a card shows and every feed jumps to 5 s before the event (Q5), in
  the usual open layout, with a "Back to where you were" chip for 15 s. Swipe a card away and
  unfolding simply carries on.
- **Data:** track status changes (yellow, SC, VSC, red); your driver entering the pits, on the
  radio, gaining or losing a place, retiring; the chequered flag. Cards fire only when normal play
  crosses the event at picture time: never on data arriving, a seek or a scrub, and not for 2 s
  after a seek. The jump is the multiview seek the Scrub Deck uses, to the event's time less the
  offset less 5 s.
- **Copy:** "Yellow flag · Lap 23"; "Safety car · Lap 23"; "Virtual safety car · Lap 23"; "Red
  flag"; "{CODE} pits · Lap 31"; "{CODE} on the radio · Lap 31"; "{CODE} passes {CODE2} for P4";
  "{CODE2} passes {CODE} for P4"; "{CODE} is out"; "Chequered flag"; each with "Unfold to see".
  After the jump: "Rewound to Safety car · Lap 23 — Back to where you were".
- **Replay / live:** replay tests cards and jump (yellow flags in the race, a red flag in
  qualifying). Live adds the jump back from the live edge and "LIVE" to return.
- **Duo:** what unfolding really does: whether the app stays in front, how fast the posture
  changes, and the screen-off case (Q10, O6).

**Other iPhones and the single-feed player (controller's call).** The pager, Radio Scanner and Gap
Thermometer appear wherever the multiview uses its closed layout, so also on any iPhone (under
600 pt wide). Event cards show there too, but with no fold to open, tapping the card makes the
jump. The single-feed player gets the Radio panel and haptics, not the pager.

### 4. Gap Thermometer (closed)

- **Sees:** two drivers' codes at either end of a tall bar, the gap in large digits, ▼ closing or
  ▲ growing. The colour slides from cool blue (over 3 s) through amber (1–3 s) to red (under 1 s,
  beta.3's battle threshold). The default pair is your driver and the nearer car ahead or behind;
  left/right moves along the race order; press and hold to pick both.
- **Data:** TimingData at picture time: the interval for adjacent cars, else the difference of
  gaps to the leader; F1's text for lapped cars ("1L"); the 3-lap trend from beta.3's race lines.
  Races and sprints only (beta.3 ruled other sessions' intervals are lap-time gaps).
- **Copy:** "Gap Thermometer"; "The Gap Thermometer works in races and sprints."; "Gaps start
  after the first lap."; "{CODE} in the pits"; "{CODE} is out — swipe for another pair".
- **Replay / live:** replay tests it all; live adds nothing new.
- **Duo:** colour and readability on the outer screen; battery at 2 Hz over a race.

### 5. The haptic vocabulary

| Event | Feel | When |
|---|---|---|
| Yellow flag | two short soft taps | the track turns yellow; at most once a minute |
| Safety car | three firm pulses | SC deployed |
| Virtual safety car **(added)** | three soft pulses | VSC deployed |
| Red flag **(added)** | one long strong buzz (0.8 s) | red flag |
| Your driver pits | a rising ramp | your driver enters the pit lane |
| Purple sector | one crisp tick | your driver sets an overall fastest sector |
| Chequered flag **(added)** | a slow triple | the leader takes the flag |

- **Sees (feels):** one haptic at most every 2 s; a stronger event replaces a weaker one waiting
  (red, SC, VSC, yellow, pits, purple). Your driver's events are off with no driver picked.
- **Data:** TrackStatus (2, 4, 5, 6), the chequered flag, your driver's InPit and sector colours.
  Same crossing rule as Unfold to See. On live, timing arrives about 7 s
  before the picture, so the haptic lands with the picture. Core Haptics, haptics-only patterns,
  restarted from the engine's reset and stopped handlers; a phone without haptics
  (`capabilitiesForHardware().supportsHaptics`) hides the settings.
- **Copy:** Settings › Haptics: "Haptics", one switch per event (the table's names), "Feel it";
  footer "Haptics follow the picture, so they never come before what you see." Settings › Debug:
  "Show haptics on screen" draws "Haptic: Yellow flag" when one fires.
- **Replay / live:** replay tests when they fire; live tests them against a real stream delay.
- **Duo (or any iPhone):** the feel itself. The simulator is not expected to play haptics, and
  Core Haptics stops when the app is suspended (O2; Q2).

### 6. The hinge as an audio mixer

- **Sees:** Settings › Team radio › "Hinge mixer", off by default (Q6). On, in book and laptop,
  the hinge sets the balance: more closed, more radio; more open, more commentary, from 70° (all
  radio) to 160° (all commentary) with a 5° dead zone. A thin bar shows for 2 s when the mix
  changes.
- **Data:** `FoldState.hingeAngle`, smoothed (the repo's SDK notes say Apple doesn't guarantee the
  angle's update rate). With clips as the source, a clip no longer silences the feeds: the angle
  sets the commentary under the clip and the clip's own level. If Q1 adds the onboard's radio
  track, the mixer instead crossfades the commentary feed with that onboard continuously, so two
  feeds are heard at once (a change to beta.2's one-sound rule, for this setting only).
- **Copy:** "Hinge mixer — fold to hear more radio, open for more commentary"; bar "Commentary
  ◀━━●━━▶ Radio"; "No radio to mix yet".
- **Replay / live:** replay, with Simulate fold's angle slider; live adds nothing.
- **Duo:** all of the feel: angle noise and update rate, and whether people move the hinge while
  watching.

### 7. Onboard and Logbook (book)

- **Sees:** a ⟳ book option (with timing). Left screen: one onboard, by Race Engineer's rules (the
  main feed if an onboard, else your driver's, else the first). Right screen: that driver's
  logbook in one column: a header (position, tyre and laps on it, last lap), then **Radio** (clips
  with transcripts, tap to play), **Laps** (times with sector colours), **Stops** (lap, pit-lane
  time, tyres off and on) and **Race control** (penalties, investigations, track limits naming the
  car). Tap the car ahead or behind in the header to switch both screens (beta.3's tap-a-car
  rules).
- **Data:** TimingData, TimingAppData, pit stops, RaceControlMessages by racing number, TeamRadio;
  all cut at picture time.
- **Copy:** "Radio", "Laps", "Stops", "Race control"; "No radio from {CODE} yet."; "No stops
  yet."; "Nothing from race control about {CODE}."; "Tap a car to pick an onboard".
- **Replay / live:** replay tests it all; live adds nothing new.
- **Duo:** the real book halves.

### 8. Ear-Matched Rivals (book)

- **Sees:** a ⟳ book option, "Rivals": two onboards, one per screen, each with a slim radio strip
  (last transcript, ▶). The left screen's driver is in the left ear, the right's in the right;
  commentary stays in both. Clips play by themselves as the picture reaches them (Q4). Default
  pair: your driver and the nearer rival; tap a strip's header to change one.
- **Data:** the two drivers' clips at picture time, played through `AVAudioEngine` with the player
  node panned −1 or +1; headphones from `AVAudioSession`'s current route, else clips play centred.
  Panning a streamed feed's own sound is likely not possible (O3), so only clips are panned.
- **Copy:** "Left ear · {CODE}", "Right ear · {CODE}"; "Put on headphones to hear each driver in
  one ear"; "No radio from {CODE} yet."
- **Replay / live:** replay tests it all; panning can be heard with headphones on the Mac running
  the simulator.
- **Duo:** the book posture with AirPods on the phone.

## Settings

- **Team radio:** "Transcripts" (on); "Play radio as it happens" (on, Scanner and Rivals only;
  Q4); "Hinge mixer" (off).
- **Haptics:** "Haptics" (on), one switch per event, "Feel it" each.
- **Closed phone:** "Event cards" ("Flags", "My driver's stops and radio", "My driver's position
  changes", "Chequered flag"); "Rewind when opening" (3, 5, 10 or 15 s; 5).
- **Debug:** "Show haptics on screen"; "Transcribe a test clip" (build 17's probe, removed before
  release); Simulate fold (Closed, and the angle slider) as today.
- **Remembered:** the last closed page and its driver or pair, the Radio panel's frame per
  posture, the radio filter.

## Logic library (DuoCore, tested on Linux)

- **Radio:** the TeamRadio parser (list or keyed, duplicates by path dropped), `RadioClip`, the
  audio URL, clips visible at a time, lap labels, the driver filter, the transcription queue
  order and retry rules.
- **Event detector,** shared by haptics and Unfold to See: events crossed between two picture
  times in normal play, seek suppression, 2 s spacing, priority, yellow once a minute.
- **Gap pair:** gap, trend and colour for any two cars, lapped or in the pits.
- **Mixer curve:** angle to two levels, dead zone, smoothing.
- **Layout engine:** `book.logbook` and `book.rivals`. The closed pages are a page index on
  `closed.main`, not new layouts.

## App (built and checked by the owner in the simulator)

- A radio controller (`@MainActor`, one per watched session): clips, background downloads, the
  `AVAudioEngine` player, ducking through the multiview controller.
- A transcriber actor around `SpeechAnalyzer`, and the transcript store.
- A haptics player (Core Haptics engine and patterns).
- Views: Radio panel, Race Engineer's radio spot, Scrub Deck ticks, the closed pager, event card
  and "Back" chip, mixer bar, logbook, rivals strips.
- The README's Status and Privacy sections.

## Privacy

- **No new hosts.** Clips come from `livetiming.formula1.com/static/`, already named in the
  README, sent without the F1 TV sign-in where F1 allows it (as Android). Transcription, haptics
  and the mixer contact nothing.
- **Transcription is on the phone.** Clip audio never leaves it; there is no server fallback. iOS
  may download its English speech model from Apple the first time: a system download shared by
  all apps, not a request from this app. The README says so.
- **No microphone.** If iOS asks for speech-recognition permission, the reason says the app never
  listens.
- **Kept on the phone:** clips in `Caches/radio`, deleted after 7 days; transcripts (a few KB per
  session) so a replay isn't transcribed twice, cleared with the caches. Nothing about you.
- **README line under F1's live timing:** "Team radio clips come from the same host. They are
  turned into text on your phone by iOS's own speech recognition; the audio is never sent
  anywhere."

## Testing

- **DuoCore:** tests on the committed São Paulo 2026 TeamRadio lines (the race fixture has 3
  lines; the builder trims a longer slice from the private copies): the parser (list, keyed, day
  prefix, duplicates), the picture-time cut, lap labels, transcription order, the event detector
  (crossing versus seek, spacing, priority, yellow once a minute, qualifying's red flags), the gap
  pair, the mixer curve, the new layout options. Zero warnings; no audio files in the repo.
- **App:** each build checked by the owner; anything unchecked goes in the CHANGELOG's "Untested —
  check later", as in beta.3.

## Work order (builds handed to the owner)

The exit test's three parts land first; the book features and the mixer last.

17. **Radio on replays:** archive topic, parser and lap labels; the Radio panel with play and
    silence; Race Engineer's spot and Scrub Deck ticks; the "Transcribe a test clip" probe (O4).
18. **Transcripts:** the transcriber, model-download line, store, fallbacks, permission note.
19. **Closed phone:** the pager, Radio Scanner, Gap Thermometer, Unfold to See with the event
    detector, "Back to where you were".
20. **Haptics:** the vocabulary, settings, "Feel it", the on-screen debug label. The exit test can
    be run after this build.
21. **Book and the mixer:** Onboard and Logbook, Ear-Matched Rivals, the hinge mixer.
22. **Final fixes from the beta.4 review,** as beta.3's build 16.

Each build is pushed as it lands, tested or not (owner's standing instruction).

## Owner checks

- **T-A4 (before build 17, about 5 minutes on the Mac):** `spike/timing_recorder.py --radio`
  fetches three São Paulo 2026 race clips without the token, then with it, and reports each try's
  HTTP status, the size, format and duration. Clips stay in the private, git-ignored folder; only
  the report is shared.
- **T-R1 (before build 21):** on the São Paulo replay, play an onboard and list its audio options;
  listen to whether its team-radio track is continuous radio, clips only, or onboard sound (Q1).
- **T-B:** each build's zero-warnings build and a short simulator check.
- **T-C4:** the first live weekend after build 20: live radio and haptics on a live stream.
- **T-D, the exit test:** above.

## Open items (confirmed while building, not owner decisions)

- **O1.** Whether `SpeechAnalyzer` file transcription needs speech-recognition permission (Apple's
  pages read for this draft don't say).
- **O2.** Whether the simulator plays haptics (expected not), and whether Core Haptics plays with
  the app in the background, screen off with audio playing (expected not).
- **O3.** Whether a streamed (HLS) feed's audio can be panned per ear with AVFoundation (expected
  not; panning is limited to clips).
- **O4.** Whether transcription runs in the simulator (build 17's probe). If not, the exit test's
  transcripts are checked on a real iPhone (Q2's phone, or the Duo in beta.7).
- **O5.** Whether radio files need the token (T-A4).
- **O6.** What the phone does closed with the screen off: the app in front on the outer screen, or
  in the background. Beta.2's probe O-B asked; its answer wasn't written down.
- **O7.** Whether `DictationTranscriber` (and any fallback) runs only on the phone, and whether
  `SpeechTranscriber` uses `contextualStrings`. Apple's pages read for this draft don't say.

## Risks

- **Too little radio.** About 30 clips a race from a handful of drivers: the Scanner, Rivals and
  the mixer will often be empty. The empty states carry it; Q1 may help.
- **Transcription quality** on noisy, compressed radio, with no server to lean on. Transcripts are
  always shown in quotes beside their audio.
- **Partly checkable in the simulator:** haptics, the mixer and a real unfold need a real phone
  (Q2, beta.7).
- **First transcript waits** on iOS downloading its speech model, possibly on mobile data.
- **Battery and heat:** transcription one clip at a time and only while radio is on screen; the
  Gap Thermometer at 2 Hz. Still to measure on a phone over a live race.
- **The unfold jump surprises.** A swiped-away card doesn't jump; "Back to where you were" undoes
  it.
- **F1 changes TeamRadio's shape or paths.** The parser takes both shapes seen, as Android's does.

## Questions for the owner

1. **Radio source.** F1's published clips everywhere (Android parity, about 30 a race), or also the
   onboards' own team-radio audio track if T-R1 shows it is continuous? **Recommendation:** clips
   everywhere in beta.4; if the track is continuous, it becomes the mixer's source when that
   onboard plays. Rivals stay on clips, which can be panned.
2. **Checking "haptics fire on flags" without haptics in the simulator.** **Recommendation:** the
   exit test reads "Show haptics on screen", which fires on the same path as the real haptic; the
   feel is checked on any iPhone you can install the build on, else on the Duo in beta.7. Do you
   have a non-Duo iPhone for this?
3. **Closed-phone navigation:** up/down between Picture, Radio Scanner and Gap Thermometer;
   left/right changes the feed, driver or pair. **Recommendation:** yes; closing opens the page
   last used (Picture the first time).
4. **Radio playing by itself.** Android is tap to hear. **Recommendation:** auto-play in the Radio
   Scanner and Ear-Matched Rivals (listening modes), tap everywhere else, and one switch, "Play
   radio as it happens", to turn auto-play off.
5. **Unfold to See: which events, how far back.** **Recommendation:** the cards in feature 3,
   position changes only for your driver, 5 s back (as the Scrub Deck's marker tap).
6. **Hinge mixer defaults.** **Recommendation:** off by default, book and laptop only, more closed
   means more radio, experiment-grade until the Duo in beta.7.
7. **Haptic list and frequency.** **Recommendation:** the roadmap's four (yellow, safety car,
   your driver pits, purple sector) plus VSC, red flag and the chequered flag;
   yellow at most once a minute; purple only for your driver; nothing faster than every 2 s. Add
   or drop any?
8. **Transcripts on the phone only** (Android falls back to a server). A phone without an
   on-device English engine shows clips without text. **Recommendation:** on device only; it keeps
   the README's promise of nothing in between.
9. **The opening-screen intro** (roadmap: beta.4 or a polish build, your choice).
   **Recommendation:** a small polish build after beta.4, so this beta stays on radio and the
   closed phone; its images need your credit approval anyway.
10. **Closed with the screen off.** If the app goes to the background then, cards and haptics stop
    until you look. **Recommendation:** accept it for beta.4, record what the simulator does (O6),
    and leave lock-screen alerts to beta.6's Dynamic Island work.

## Sources

- Repo: `docs/roadmap.md`; the beta.1–beta.3 specs and rulings; `README.md`; `CHANGELOG.md`;
  `DuoApp/Fold/`; `DuoApp/Multiview/MultiviewLayout.swift`; `Packages/DuoCore/Sources/LiveTiming/`
  (`SignalR.swift`, `Backfill.swift`, `TimingArchive.swift`, `StreamLine.swift`); the São Paulo
  2026 TeamRadio files in `spike/beta3-fixtures/` (the counts and timings above were measured from
  them).
- Android (`og-android`, 0.99.9): `Radio.kt`, `Transcriber.kt`, `AppState.kt` (playback, ducking,
  the transcription loop), `LiveTiming.kt` (`parseRadio`, `addRadio`, `lapAt`), `LiveFeed.kt`.
- Apple developer documentation: `SpeechAnalyzer`, `SpeechTranscriber`, `AnalysisContext`,
  `CHHapticEngine`.
- FastF1's documentation site couldn't be reached from the cloud session; the TeamRadio shape comes
  from F1's own files in the repo and Android's parser.
