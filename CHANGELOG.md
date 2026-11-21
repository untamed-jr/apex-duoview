# Changelog

Versions follow the standard in [docs/roadmap.md](docs/roadmap.md).

## Unreleased

### Live multiview (not on the phone yet)

Asked as one multiview PLAY, F1 TV sends a live session's multiview as Widevine, which no iPhone
plays ("Multiview can't play this live session yet"). Asked one feed at a time, the way Safari
asks, each feed comes as FairPlay, and several play side by side (owner's probes and FP1). So a
live multiview now plays each feed on its own FairPlay session.

- Opening a live multiview: when the one multiview PLAY comes back protected, each slot's feed
  is asked for on its own (the remembered four at once); a feed picked later in Feeds is asked
  for when it is picked. Every feed the session lists can be picked. The main INTERNATIONAL
  feed is asked without a channel, as F1 TV's own link is.
- Each feed has its own FairPlay keys, for as long as the feed plays.
- A feed that F1 TV won't play shows the reason on its tile; the others play on. If the main
  feed can't play, the multiview ends with the reason and offers "Watch the main feed".
- An expired link asks for that one feed again, not every feed (at most once a minute per feed).
- Replays are unchanged: one multiview PLAY, unprotected streams.
- DuoCore: `PlayCoordinator.playLiveFeed(contentId:channelId:playChannelId:refresh:)` (tested):
  one Safari-style PLAY per feed, kept by channel; asking again sends nothing; a single or
  multiview PLAY, or a stop, clears them.

Untested — check later (on the phone, during a live session: the simulator can't play FairPlay):
- everything above: four feeds play; the onboards are the right drivers; swapping a feed in
  Feeds plays it; 10 minutes without a stall; "Watch the main feed" still shows if F1 TV refuses;
- the first build on the Mac (only the syntax of the app files was checked here).

### Polish — the opening screen and the Apple design pass (in progress, not on the phone yet)

Moved forward from after beta.4 (owner, 2026-11-19), built while waiting for the race weekend.
The phone keeps the race build (commit `cc569d2`, the same app as `3073622`) until after the Las Vegas race. Each
change is its own commit so it can be kept or reverted on its own.

- **Opening screen** (direction A, "Night circuit"): the floodlit wet corner, red light trails
  drawn along the racing line, the neon APEX logo lighting up, "DuoView", "Every lap, every
  angle.", the version and the small print. About 1.6 s plus a short hold, once per launch; a
  tap skips it; Reduce Motion makes it a plain fade. The launch screen is now plain near-black
  (the old square logo is gone from it), so it hands over to the opening's first frame.
- **Apple design pass**, one commit each so any can be undone alone:
  - q6: the selected tab is white, not red.
  - q5: Apple's glass buttons (main actions stay red); the floating Live-now and sign-in
    banners are glass.
  - q2: feed name pills, speaker buttons and driver cards are clear glass; only SOUND is red.
  - q1: multiview's top bar and playback bar are clear glass, grouped; same touch areas.
  - q3: the floating map and tower are regular glass; docked they stay solid.
  - q7: tower rows, tyre letters, pit-circle labels and the Scrub Deck PIT grow with the text
    size (unchanged at the default size).
  - Waiting: q8 (44 pt touch areas) and q9 (VoiceOver for the map and pit circle, Move and Resize
    actions for panels), until the laptop-pose tap and drag problems are found. q4 is no change.
- **Welcome tour and first-time tips** (owner's picks, 2026-11-20): five swipeable cards on the
  first launch (Skip on each; Settings › Help › "How to use" plays them again), and tips the
  first time: try laptop pose (flat multiview), tap a car (the Map button), tap to bring the
  controls back, and closed it keeps playing. Settings › Help also has "Show tips" and "Reset
  tips". The card pictures are placeholders until the screenshots are taken after the race.
- **Clearing what you've watched** (owner request, FP1 night): touch and hold a Continue
  watching tile › "Remove from Continue watching"; "Clear all" beside the row's title (asks
  first); Settings › Watching › "Clear watch history" clears Continue watching and the watched
  marks (asks first). DuoCore: `RecentsStore.removeAll()`, `WatchHistory.removeAll()` (tested).
- **Single-feed player: the app's own controls** (owner's screenshots, FP1 night, option B):
  Apple's player is gone; the picture is the app's own, with the multiview's look: ✕ and mute,
  then Map, picture in picture and AirPlay at the top; at the bottom the scrubber, play/pause,
  back and forward 10 s, a LIVE that takes you live when tapped (red at the live point, outlined
  behind it), the speed, and one menu for the commentary language and subtitles (subtitles only
  if the video has any). They hide 4 s after the last touch; tap the picture to bring them
  back; they stay up while paused, loading or scrubbing. Mute and the subtitle choice stay when
  tapping a car switches feeds. Picture in picture also still starts by itself on leaving the
  app; the lock screen and Control Centre keep play, pause and the position; on AirPlay a line
  says "Playing on AirPlay". Fixes the doubled ✕ and Map, the LIVE that didn't go live, and
  Apple's controls that stayed stuck on screen. Not brought back: Apple's volume slider (the
  side buttons set the volume; mute is the app's) and its zoom-to-fill.
  Built in the simulator with 0 warnings (342b966, 2026-11-20). Untested: using it (simulator
  replay check next); live checks need the phone after the race.
- **Build check for the Mac** (`scripts/check-build.sh`): builds for the simulator without
  touching the phone; `--shots` also saves screenshots of the opening.

Built in the simulator with 0 warnings (opening screen and q1, q2, q3, q5, q6, q7; 2026-11-19).
Untested — check later: everything above on the phone (after the race).

## v1.0-beta.4 — Radio and the closed phone (not released yet)

Beta 4 is built (builds 17 to 22) and has not been tried on the phone. The phone keeps the race
build until after the Las Vegas race; then beta.4 is installed and the list below is checked.
Everything here was checked on a computer only: the DuoCore tests (706), the pure app files
against the São Paulo race data, and the syntax of every changed file. The owner's Mac build is
the first real compile of the app changes.

- **Team radio on replays** (build 17): a Radio panel, clips shown only once the picture has
  reached them, played while the feeds go quiet, with marks on the Scrub Deck and in Race
  Engineer.
- **Transcripts** (build 18): each clip turned into text on the phone by iOS's own speech
  recognition; never a server, never the microphone.
- **The closed phone** (build 19): the outer screen has three pages (Picture, Radio Scanner,
  Gap Thermometer), and Unfold to See: an event card slides in, and opening the phone jumps every
  feed to just before it.
- **Haptics** (build 20): one feel for each flag, your driver's stop and purple sectors, felt as
  the picture reaches them.
- **Book layouts and the hinge mixer** (build 21): Onboard and Logbook, Ear-Matched Rivals, and
  a hinge mixer for radio against commentary (clips only, until owner check T-R1).
- **Final fixes** (build 22): from the final review, including the mixer settling at the hinge's
  angle, Unfold to See through an unknown posture, nothing left on the lock screen after closing
  the player, and a live multiview tile that asks again with a fresh link.

### Untested — check later (all of beta.4)

One list for builds 17 to 22, with what a later build answered taken out. The lists under each
build below stay as they were written.

**First, in the simulator**
- **The close check** (tests the lock-screen teardown): play a replay in the single-feed player,
  close it, then tap a car in another one and close again; nothing crashes. If closing crashes,
  the suspect is the last line of `PlayerController.stopNowPlaying()` (`removePlayer` on the
  session's only player): remove that line.
- The zero-warnings Mac build (`xcodegen generate` first: new folders `DuoApp/Closed`,
  `DuoApp/Haptics` and `DuoApp/Book`, and new files in `DuoApp/Radio`; DuoCore gains
  `UnfoldWatch.swift`). Not compiled here: the Now Playing teardown's MediaPlayer calls, the
  mixer's settling task, the Speech calls and Swift 6 isolation in `Transcriber`, the Core Haptics
  calls, the audio route and headphone calls, the views and gestures. (Build 17's own build was
  checked on the Mac at 15424b1: 0 warnings.)
- São Paulo race replay, laps 17–23: clips appear only as reached, under their lap; ANT has 8
  over the race ("Show the whole race", My driver or ANT's chip).
- Radio and transcripts: a clip plays while the feeds go quiet, at the feeds' speed (try 2×), and
  the sound comes back at its end, on a second tap, on a rewind past it and on closing the player;
  moving the sound to another tile during a clip; the soft flash only in normal play (also check
  a speed change while a clip is due); transcripts (if the probe shows the simulator can
  transcribe, O4); text only once the picture reaches its clip, also after a rewind and with
  "Show the whole race"; closing the panel mid-clip then opening it does the same clip again;
  "Transcripts" off and on; speech recognition denied and allowed again.
- Exit-test step 2 with Settings › Debug › Simulate fold › Closed: the Scanner on ANT plays his
  clips on laps 19, 20 and 22 as the picture reaches them; the Thermometer's colour follows the
  gap; a yellow flag (laps 17 and 20) brings a card, unfolding jumps every feed to 5 s before it,
  and "Back to where you were" returns.
- Exit-test step 3 with "Show haptics on screen": the race's yellow flags and the two red flags
  in the São Paulo qualifying replay each show "Haptic: …" as the picture reaches them; nothing
  on a scrub across one, nor in the 2 s after it.
- Both book options with a replay (⟳ in book with timing loaded); the Logbook follows a tap on
  the car ahead or behind; Rivals' header menu; the mixer with Simulate fold's angle slider (the
  bar, the levels, 70° and 160°).
- The Gap Thermometer swiping from a pair with a car that never ran; a remembered driver filter
  in a session without that car.
- Panning with headphones on the Mac running the simulator; centred without.

**On the phone**
- **Owner check T-R1 is still open:** play an onboard and list its audio options; is its
  team-radio track continuous radio, clips only, or onboard sound? The mixer is built for clips
  only; T-R1 decides whether a continuous-radio crossfade is added later.
- **Transcribe a test clip** (Settings › Debug) on the Duo, for O4 and O7: whether iOS can
  transcribe, the engine it picked, the locale, the seconds. It stays in this build until you
  have run it. If iOS wants a speech-recognition reason for this and the app closes when you tap
  it, that is the O1 answer, not a bug to chase.
- Transcripts: seconds per clip over 10 clips; the "Getting the speech model ready…" line the
  first time; whether a speech-recognition prompt appears (O1) and which engine ran (O7);
  warmth over 20 minutes of radio on screen; nothing transcribed with the app in the background
  (picture in picture, or the screen off with sound).
- **Lock screen:** play a single feed, close it, lock the phone and open Control Centre: no Apex
  DuoView entry. Tap a car twice, then close: still none. Close the player, or tap a car, while
  picture in picture shows: no window is left behind.
- The Radio panel on the Duo: the Scrub Deck's radio ticks (taller for your driver; none past the
  picture) and a tap on one; Race Engineer's spot for the top onboard (the mini map above it is a
  little shorter; with a notice line showing, its 122 pt may overflow); the multiview's top bar
  with the Radio button still fits closed and in book pose; a clip download that F1 refuses shows
  "Couldn't load this clip", the video plays on and nobody is signed out; a call, an alarm or
  Siri while a clip plays ends the clip and brings the feeds' sound back; tapping a car in the
  single-feed player while a clip plays stops the clip and empties the list for a moment.
- **The closed phone:** the outer screen's size (Settings › Debug › "Screen"); readability at
  arm's length; how the swipes feel (on a tile, on the black around it, on a page; the tower
  scrolls rather than changes the page); closed with the screen off (O6, Q10); two stacked feeds
  (tap to swap, hold and drag to trade, swipe left or right for the main feed; their quality
  caps); the Gap Thermometer's battery use at 2 Hz over a race.
- **Unfold to See on the Duo:** with a card up while closed, unfold to book and to flat, slowly
  and quickly; each time the feeds jump, the jump lands before the layout changes and the card
  goes. If one doesn't, record the posture order in the Debug log.
- **Haptics:** each "Feel it", and each event in a replay; whether the seven feel distinct;
  whether yellow nags through a busy session; Settings › Haptics shows on the phone; every
  "Show haptics on screen" label comes with a feel, also the first one after a long quiet spell;
  with the screen off or the app in the background (O2) Core Haptics is expected to stop, and the
  next haptic after coming back should still play; a yellow's haptic plays again after an Unfold
  to See jump back (it matches "haptics follow the picture"; say if the feel is wrong).
- **Book on the Duo:** the real book halves (the strips are as wide as their onboard, which in
  book is the whole half); AirPods panning; headphones going in or out while a clip plays end
  that clip and the next one plays in its ear.
- **The hinge mixer on the Duo:** fold quickly and stop; the bar settles at the hinge's angle
  within about 1.5 s; holding still doesn't make the mix waver; the feel of angle noise, how
  often the angle comes, and whether the 5° dead zone feels steppy.

**On a live weekend**
- **A live multiview:** four feeds play; the onboards are the right drivers; swapping a feed in
  Feeds plays it; a tile that stops comes back by itself once (a fresh PLAY); picking it again
  later than a minute after its last link tries again. Removing a stopped feed and adding it
  back, Clear all, Reset or a preset first try the link it had; only if that fails does it ask
  afresh (once a minute).
- New radio clips arrive with only the Radio panel open (the radio keeps the live timing being
  rebuilt while a player is open, as the map and tower do).
- In Rivals, a live feed starts only once its own PLAY answers, so the left rival may take a
  moment (or the next change of the feeds) to reach the left screen.
- On a live programme, haptics, Rivals' auto-play and the radio land with the picture, not the
  timing (T-C4); a card's jump back from the live edge, "Back" to the edge, and LIVE.

### v1.0-beta.4, build 22 — final fixes

Not on the phone yet. The fixes from the final review of beta.4. Checked on a computer only
(syntax of every changed file; the DuoCore tests; the closed phone's and the radio's pure files
against the São Paulo race data with a stand-in player); the first real compile is the owner's
Mac build.

- **The hinge mixer reaches where the hinge stops.** The hinge reports an angle only when it
  moves, so the smoothed mix used to stop short once the hinge was still (one quick fold from
  160° to 90° left it at about 139°). After each reading it now keeps stepping, every 100 ms,
  until it lands on the resting angle. A small wobble inside the 5° dead zone still changes
  nothing. DuoCore: `HingeMixer.settle()` and `isSettled` (tested with one reading at a time, as
  the app gets them).
- **Unfold to See keeps its jump through an unknown posture.** If the hinge reports part-open
  before the fold is known, closed → (unknown) → book or flat is still an unfold, and the card
  showing is jumped to, also when the window reaches the inner screen first. An unknown reading
  on its own still never moves the video. DuoCore: `UnfoldWatch` (tested).
- **Closing the single-feed player leaves nothing on the lock screen.** Closing it (or new
  content, such as tapping a car) ends its lock-screen and Control Centre entry: nothing is
  published any more, play, pause and the position go, and the player leaves the session.
  Picture in picture already ended there.
- **A live multiview tile that stopped asks again with a fresh link and licence.** For any
  reason, not only an expired link: a new PLAY for that feed, at most once a minute per feed;
  failing again sooner, the tile says why. Picking a stopped live feed again also asks afresh
  (after that minute), never with the old link. The main feed keeps beta.1's rule (it ends the
  multiview and offers "Watch the main feed") unless its link expired.
- "Watch the main feed" after the main feed stops mid-session starts where the feeds were (the
  live edge on live), not where the multiview opened.
- Clear all, Reset or a preset on a live multiview keeps the spinner while a new feed's PLAY is
  still out.
- A seek's two quiet ticks wait for picture time to come back (the companion and the radio), so
  a short seek landing is never taken for normal play.
- Without a transcript, the Rivals strip and the Radio Scanner show the driver's code, not the
  lap label a second time under its header.
- The Radio Scanner holds its leader only once there is a picture time (before it, the order is
  by racing number).
- The Gap Thermometer's swipe works when one of the pair has no timing; it reads from the other
  car's place. DuoCore: `GapPair.shifted` (tested).
- The Gap Thermometer shows the timing's own note (as the tower does) while the timing is
  hidden on a rewound live programme, not "Gaps start after the first lap."
- A remembered radio filter for a driver this session doesn't have shows every clip.
- A haptic waiting its turn doesn't play once its switch (or Haptics) is off.
- Settings › Debug's "Haptic: …" label is clear glass, like the rest over the video.
- Rivals: headphones going in or out while a clip plays end that clip; the next clip plays in
  its ear. Build 21's note said it moved at once; that line is corrected. No change in the app.
- Settings › Debug's "Transcribe a test clip" stays in this build: the owner runs it on the Duo
  (O4, O7) before it is removed in a later commit.
- Version: 1.0-beta.4 (build 22).

### Untested — check later (build 22)

- **First, in the simulator:** play a replay in the single-feed player, close it, then tap a car
  in another one and close again; nothing crashes. If closing crashes, the suspect is the last
  line of `PlayerController.stopNowPlaying()` (`removePlayer` on the session's only player):
  remove that line.
- The zero-warnings build. No new app files; DuoCore gains `UnfoldWatch.swift` (the package
  picks it up). Not compiled here: the Now Playing teardown's MediaPlayer calls (in particular
  removing the session's only player), the mixer's settling task.
- **Lock screen:** play a single feed, close it, lock the phone and open Control Centre: no
  Apex DuoView entry. Tap a car twice, then close: still none.
- Close the single-feed player, or tap a car, while picture in picture shows: no window is left
  behind.
- **The hinge mixer on the Duo:** fold quickly and stop; the bar settles at the hinge's angle
  within about 1.5 s; holding still doesn't make the mix waver.
- **Unfold to See on the Duo:** with a card up while closed, unfold to book and to flat, slowly
  and quickly; each time the feeds jump. If one doesn't, record the posture order in the Debug
  log.
- **A live multiview:** a tile that stops comes back by itself once (a fresh PLAY); picking it
  again later than a minute after its last link tries again. Removing a stopped feed and adding
  it back, Clear all, Reset or a preset first try the link it had; only if that fails does it ask
  afresh (once a minute).
- In the simulator: Gap Thermometer swipes from a pair with a car that never ran; a remembered
  driver filter in a session without that car.

### v1.0-beta.4, build 21 — Onboard and Logbook, Ear-Matched Rivals, the hinge mixer

Not on the phone yet. Checked on a computer only (syntax of every changed file; the book's words,
the Rivals slot rules and the mixer's levels in the radio against the São Paulo race data with a
stand-in player); the first real compile is the owner's Mac build.

- **Onboard and Logbook** (book, ⟳ with timing): one onboard on the left screen, chosen as Race
  Engineer chooses (the main feed if it's an onboard, else your driver's, else the first); that
  driver's logbook on the right, in one column:
  - a header: position, the tyre and its laps, the last lap, and the cars ahead and behind;
    tapping one switches both screens to that car (tap-a-car's rules);
  - **Radio**: their clips so far with transcripts, tap to play ("No radio from {CODE} yet.");
  - **Laps**: newest first, with sector colours;
  - **Stops**: lap, pit-lane time, tyres off and on ("No stops yet.");
  - **Race control**: penalties, investigations and track limits naming the car, each with its
    lap; blue flags are left out ("Nothing from race control about {CODE}.").
  - Everything stops at the picture; with no onboard on the left, "Tap a car to pick an onboard".
- **Ear-Matched Rivals** (book, ⟳ with timing and two feeds or more): the two rivals' onboards,
  one per screen, each with a strip under it: "Left ear · {CODE}" / "Right ear · {CODE}", their
  last clip's words and ▶. With headphones the left screen's driver is in the left ear and the
  right's in the right; commentary stays in both. Without headphones clips play centred and the
  left strip says "Put on headphones to hear each driver in one ear".
  - The first pair: in a race your driver and the nearer rival; elsewhere your driver and the car
    next to them in the running order (or the first two). Tap a strip's header to change that
    screen's driver (picking the other screen's driver swaps the two). The pair is kept for the
    session.
  - The two onboards go in the first two spots. A feed makes way for them only if it doesn't
    have the sound; the feed with the commentary keeps playing out of sight.
  - With "Play radio as it happens" on, a clip plays by itself as the picture reaches it (never on
    a seek or a scrub), in the ear of the screen its driver is on. Headphones going in or out
    while it plays end that clip (corrected in build 22); the next clip plays in its ear, or in
    the middle without headphones.
  - **Leaving Rivals keeps its two onboards** at the front of the feeds (and remembered as the
    last used); the main feed from before isn't put back.
- **The hinge mixer** (Settings › Team radio › "Hinge mixer — fold to hear more radio, open for
  more commentary", off): in book and laptop, while a clip plays, the hinge sets the balance:
  70° all radio, 160° all commentary, in between a straight line; smoothed, with a 5° dead zone.
  A bar shows for 2 s when the mix changes, "Commentary ◀━━●━━▶ Radio", or "No radio to mix yet"
  before the first clip. With it off (or in other postures) a clip silences the feeds, as before.
  Without a clip the feeds are at full level. In book the bar sits in the main feed's half, off
  the fold. **The hinge mixer is multiview-only in this build** (controller ruling): the
  single-feed player keeps silencing the feeds under a clip.
- A tap in the Logbook (or a rival put in) that adds a feed keeps the book layout, as the laptop's
  data layouts are kept.
- Version: 1.0-beta.4 (build 21).

### Untested — check later (build 21)

- The zero-warnings build (`xcodegen generate` first: a new folder, `DuoApp/Book`). New audio
  calls not compiled here: the route-change notification, `currentRoute.outputs` and the
  headphone port types, the player node's volume.
- In the simulator: both book options with a replay (⟳ in book with timing loaded); the Logbook
  follows a tap on the car ahead or behind; Rivals' header menu; the mixer with Simulate fold's
  angle slider (the bar, the levels, 70° and 160°).
- Panning with headphones on the Mac running the simulator; centred without.
- On the Duo: the real book halves (the strips are as wide as their onboard, which in book is the
  whole half); AirPods panning; the hinge mixer's feel (angle noise, how often the angle comes,
  whether the 5° dead zone feels steppy).
- **T-R1** (an onboard's team-radio audio track: continuous radio, clips only, or onboard sound)
  is still open. The mixer is built for clips only; T-R1 decides whether a continuous-radio
  crossfade is added later.
- A live multiview in Rivals: a live feed starts only once its own PLAY answers, so the left
  rival may take a moment (or the next change of the feeds) to reach the left screen.
- A live programme: Rivals' auto-play lands with the picture, not the timing (T-C4).

### v1.0-beta.4, build 20 — haptics

Not on the phone yet. Checked on a computer only (syntax of every changed file; the haptic
vocabulary and the companion's haptic schedule against the São Paulo race data with a stand-in
player); the first real compile is the owner's Mac build.

- **A haptic for each event**, felt as the picture reaches it, in either player (the multiview,
  and the single-feed player, which has no closed-phone pages):

  | Event | Feel |
  |---|---|
  | Yellow flag | two short soft taps (at most once a minute of picture time) |
  | Safety car | three firm pulses |
  | Virtual safety car | three soft pulses |
  | Red flag | one long strong buzz, 0.8 s |
  | Your driver pits | a rising ramp |
  | Purple sector | one crisp tick (your driver) |
  | Chequered flag | a slow triple |

- At most one haptic every 2 s; when two come close together the stronger waits for its turn
  (red, safety car, VSC, chequered, yellow, pits, purple) and the weaker is dropped. Only normal
  play counts: never data arriving, a seek or a scrub, nor the 2 s after a seek, and a seek
  forgets a haptic waiting. Your driver's haptics need a driver picked (Settings › Multiview ›
  My driver).
- **Settings › Haptics:** "Haptics" (on), then one switch per event, each with "Feel it"; footer
  "Haptics follow the picture, so they never come before what you see." A haptic plays only
  when "Haptics" and its own switch are both on. "Feel it" plays it whatever the switches say.
  Hidden on a phone that can't play haptics (the simulator).
- **Settings › Debug › "Show haptics on screen"** (off): "Haptic: Yellow flag" at the top of
  either player for 2 s each time one plays, from the same place as the real haptic, so it also
  works in the simulator.
- Core Haptics, haptics-only patterns, one engine for the app, made on the first haptic. It
  restarts after a reset or an interruption, sleeps between haptics, and starts again with the
  next one after the app was in the background.
- Version: 1.0-beta.4 (build 20).

### Untested — check later (build 20)

- The zero-warnings build (`xcodegen generate` first: a new folder, `DuoApp/Haptics`). The
  Core Haptics calls are checked against a stand-in only.
- Exit-test step 3 in the simulator with "Show haptics on screen": the race's yellow flags and
  the two red flags in the São Paulo qualifying replay each show "Haptic: …" as the picture
  reaches them; nothing on a scrub across one, nor in the 2 s after it.
- On the Duo: each "Feel it", and each event in a replay; whether the seven feel distinct;
  whether yellow nags through a busy session; Settings › Haptics shows on the phone.
- On the Duo with "Show haptics on screen" on: every label comes with a feel, also the first
  haptic after a long quiet spell (the engine sleeps between haptics).
- With the screen off or the app in the background (O2): Core Haptics is expected to stop; the
  next haptic after coming back should still play.
- A live programme: the haptic lands with the picture, not the timing (T-C4).

### v1.0-beta.4, build 19 — the closed phone and Unfold to See

Not on the phone yet. Checked on a computer only (syntax of every changed file; the closed
phone's models and its controller against the São Paulo race data with a stand-in player); the
first real compile is the owner's Mac build.

- **The closed phone has three pages:** Picture, Radio Scanner and Gap Thermometer. Swipe up or
  down between them (dots on the right edge, which also take a tap); left or right changes what
  the page shows. Closing opens the page used last (Picture the first time). The first time:
  "Swipe up or down for Picture, Radio and Gap". The feeds keep playing, with sound, on every
  page. This is wherever the multiview uses its closed layout, so also on any iPhone in portrait.
- **Picture fills the outer screen** (owner, 2026-11-18): with two or more feeds, two of them
  stacked full width, the main one on top (left and right still change the main one); with one
  feed, the timing tower fills the space below it. DuoCore: `closed.stack` in `LayoutEngine`.
- **Radio Scanner:** one driver's code, team colour, position and lap; their clips so far in
  large type, the newest at the bottom; one big ▶ / ■. A clip plays by itself when the picture
  reaches it ("Play radio as it happens"); with that off, "New radio — tap to play". Left and
  right change the driver in race order; the default is your driver, else the leader (kept when
  the lead changes). "No radio
  from {CODE} yet. Swipe for another driver." Transcripts are made while the Scanner shows.
- **Gap Thermometer:** two drivers' codes at either end of a tall bar, the gap in large digits,
  ▼ closing or ▲ growing; the bar goes from cool blue (3 s or more) through amber (2 s) to red
  (1 s or less). Twice a second. Left and right move the pair along the race order; touch and
  hold to pick both drivers. The default pair is your driver and the nearer car ahead or behind,
  as found when the page first shows (it doesn't flip as the gaps move).
  "The Gap Thermometer works in races and sprints.", "Gaps start after the first lap.",
  "{CODE} in the pits", "{CODE} is out — swipe for another pair".
- **Unfold to See:** while closed, an event slides in as a card at the top of any page, older
  ones stacked behind ("+2"): "Yellow flag · Lap 23", "Safety car · Lap 23", "Virtual safety car
  · Lap 23", "Red flag", your driver's stop, radio, passes and retirement, "Chequered flag", each
  with "Unfold to see". Cards come only when normal play reaches the moment: never on data
  arriving, a seek or a scrub, nor for 2 s after a seek; a seek back takes away the cards it
  passes. Open the phone while a card shows and every feed jumps to 5 s before it (the Scrub
  Deck's seek), with "Rewound to … — Back to where you were" for 15 s. Swipe a card away and
  opening simply carries on. On a phone without a fold, or on the Duo while closed, a tap on the
  card makes the jump. On a live programme, "Back" from the live edge returns to it, and LIVE
  still does. The moment jumped to brings no second card as the picture plays past it again.
- **Settings › Closed phone:** "Event cards" ("Flags", "My driver's stops and radio", "My
  driver's position changes", "Chequered flag") and "Rewind when opening" (3, 5, 10 or 15 s;
  5). Settings › Debug shows "Screen" in points, for measuring the outer screen.
- The single-feed player follows the same events (for build 20's haptics), with no pages or
  cards.
- Version: 1.0-beta.4 (build 19).

### Untested — check later (build 19)

- The zero-warnings build (`xcodegen generate` first: a new folder, `DuoApp/Closed`). The views
  and their gestures are checked by eye only.
- Exit-test step 2 in the simulator (Settings › Debug › Simulate fold › Closed): the Scanner on
  ANT plays his clips on laps 19, 20 and 22 as the picture reaches them, the transcript scrolls;
  the Thermometer's colour follows the gap; a yellow flag (laps 17 and 20) brings a card,
  unfolding jumps every feed to 5 s before it, and "Back to where you were" returns.
- On the Duo: the outer screen's size (Settings › Debug › "Screen"); readability at arm's
  length; how the swipes feel (up and down on a tile, on the black around it, on a page; the
  tower scrolls rather than changes the page); what a real unfold does (the app still in front?
  how fast the posture changes?); closed with the screen off (O6, Q10).
- Two stacked feeds on the outer screen: tap to swap, hold and drag to trade, swipe left or
  right for the main feed; their quality caps.
- A card at the moment the phone opens: the jump lands before the layout changes, and the card
  goes.
- A live programme: a card's jump back from the live edge, "Back" to the edge, and LIVE.
- The Gap Thermometer's battery use at 2 Hz over a race.

### v1.0-beta.4, build 18 — team radio transcripts

Not on the phone yet. Checked on a computer only (syntax of every changed file, and the
transcripts' logic and the radio controller against the São Paulo race data with a stand-in
transcriber); the first real compile is the owner's Mac build.

- **Transcripts on the phone.** Each clip is turned into text by iOS's own speech recognition,
  on the phone only: never a server, never the microphone (the app reads the clip files). Up to
  two lines show under the clip, in quotes; "Transcribing…" while it's being done; "(no words
  recognised)" when nothing was. Only once the picture has reached the clip: transcription may
  run up to 2 minutes ahead so the text is ready, but it never shows early.
- **One clip at a time, and only while the Radio panel is open** with Settings › Team radio ›
  "Transcripts" on: nearest the picture first; a clip not done in 45 s is skipped; three failures
  in a row wait 2 minutes. Closing the panel, or the app going to the background (picture in
  picture, audio only), stops the clip being transcribed (it is picked up again next time). With
  "Transcripts" off, none are made and none are shown.
- **Kept per session** beside the clips (`transcripts.json` in Caches, deleted with them after 7
  days), so a replay isn't transcribed twice.
- **The engine:** `SpeechTranscriber` (British English, else American), its model downloaded by
  iOS if missing; if it isn't available, `DictationTranscriber`; then `SFSpeechRecognizer` only
  where it runs on the phone. It leans toward the session's driver names, teams and common radio
  words ("box box", "copy", "lift and coast", …).
- **The panel's line** while transcripts can't run: "Getting the speech model ready…",
  "Transcripts aren't available on this iPhone — clips still play", or "Allow speech recognition
  in Settings to see transcripts". Clips play either way.
- **Speech recognition reason** in Info.plist: "Team radio clips are turned into text on this
  iPhone. The app never listens to you."
- Race Engineer's spot keeps its three clips without their words (no room).
- Settings › Debug › "Transcribe a test clip" now goes through the same transcriber, and also
  shows the engine it picked.
- README: the Privacy section says how clips become text, and that iOS may download its speech
  model the first time.
- Version: 1.0-beta.4 (build 18).

### Untested — check later (build 18)

- The zero-warnings build (`xcodegen generate` first: three new files in `DuoApp/Radio`). The
  Speech calls are checked against Apple's documentation, not compiled; Swift 6 isolation in
  `Transcriber` (the `@concurrent` engine functions, the `SFSpeechRecognizer` callbacks) is
  checked by eye only.
- Transcripts in the simulator, if the build 17 probe showed it can transcribe (O4).
- On the Duo: seconds per clip over 10 clips; the "Getting the speech model ready…" line the
  first time; whether a speech-recognition prompt appears (O1: with `SpeechTranscriber` or
  `DictationTranscriber` the app asks only if a transcription fails saying it wasn't authorized,
  then tries that clip again if allowed; a denial stops them only once one fails while denied;
  the `SFSpeechRecognizer` fallback asks before its first clip); which engine ran (O7: the
  probe's "Engine").
- Text appears only once the picture reaches its clip, also after rewinding and with "Show the
  whole race".
- Closing the panel mid-clip, then opening it: the same clip is done again, nothing is skipped.
- "Transcripts" off: no line, no text; on again: they come back.
- Speech recognition denied in Settings: the line; allowed again: transcripts carry on.
- Warmth over 20 minutes of radio on screen; and that nothing is transcribed with the app in the
  background (picture in picture, or the screen off with sound).

### v1.0-beta.4, build 17 — team radio on replays

Not on the phone yet: the phone keeps the race build until after the Las Vegas race. Checked on a
computer only (syntax of every changed file, and the radio's logic and controller against the São
Paulo race data); the first real compile is the owner's Mac build.

- **Team radio panel.** A "Radio" button beside Map (multiview's top bar and the single-feed
  player's) opens "Team radio", a floating panel like the map and the tower: moved, resized and
  remembered per fold posture, closed with its ✕ ("Hide team radio"). Oldest clip at the top,
  newest at the bottom, a small lap header ("Lap 23", "Before the start", "After the flag",
  "Q2 · 8:12 left", or the practice time) whenever the lap changes, and the list follows new clips.
  Chips: All · My driver (when you have one) · a driver. Before any clip: "Radio shows up here as
  it happens."; for one driver: "No radio from {CODE} yet."
- **Only what the picture has reached.** A clip appears once the picture reaches the moment F1
  published it; rewinding takes later clips out again, and stops a clip playing past it. "Show the
  whole race" shows every clip.
- **Playing a clip.** Tap a row to play it; the feeds go silent until it ends (or tap again to
  stop), and it plays at the feeds' speed. A clip crossed while the video plays flashes once,
  softly; one reached by a seek or a scrub never does.
- **Downloads.** A clip downloads the first time it is played, from F1's archive without the
  F1 TV sign-in; only if F1 refuses is it asked once more with it, to that address only. A
  refusal never signs you out: "Couldn't load this clip". Clips are kept on the phone for 7 days
  (Caches), then deleted at launch. A clip that won't play: "Couldn't play that radio clip".
- **Race Engineer's spot** (laptop pose): the top onboard's last three clips, each with ▶,
  instead of "Saved for beta.4: team radio".
- **Scrub Deck:** a small blue tick per clip along the top of the strip, a taller one for your
  driver, only up to the picture (under the fog); tap one to jump 5 s before it. "Radio" in the
  legend.
- **Settings › Team radio:** "Transcripts" and "Play radio as it happens" (both on). They are
  stored now; transcripts arrive with build 18, and "Play radio as it happens" is for the Radio
  Scanner and Rivals (builds 19 and 21).
- **Settings › Debug › "Transcribe a test clip"** (owner check O4; removed before release): turns
  the first clip you played into text on the phone and shows whether iOS's transcriber is
  available, the locale, whether the speech model was installed or had to download, the seconds
  it took, and the text.
- Version: 1.0-beta.4 (build 17).

### Untested — check later (build 17)

- ~~The zero-warnings build~~ checked on the Mac 2026-11-21: BUILD OK, 0 warnings at 15424b1 (the
  first build, at 3cb8d80, had 5 iOS 27 deprecation warnings in `RadioAudio`, now fixed).
- São Paulo race replay, laps 17–23: clips appear only as reached, under their lap; ANT has 8 over
  the race (Show the whole race on, My driver or ANT's chip).
- A clip plays while the feeds go quiet, at the feeds' speed (try 2×); the sound comes back at the
  clip's end, on a second tap, on a rewind past it, and on closing the player.
- In multiview, moving the sound to another tile while a clip plays: that tile stays quiet until
  the clip ends.
- The soft flash: once for a clip crossed in normal play; never after a seek, a scrub, ±10 s or a
  Scrub Deck tap. The video's own time-jump notice counts as a seek only when the time moved more
  than a second from where it should be, so a notice in normal play (a speed change, the end of a
  stall) no longer stops the flash; check a speed change while a clip is due.
- The radio ticks on the Scrub Deck (taller for your driver; none past the picture) and a tap on
  one; Race Engineer's spot for the top onboard (the mini map above it is a little shorter now).
- The multiview's top bar with one more button (Radio): that it still fits closed and in book
  pose, the title shortening first.
- A clip download that F1 refuses: "Couldn't load this clip", the video plays on, nobody is
  signed out.
- Headphones plugged in or out while a clip plays: the clip ends and the next one plays.
- A call, an alarm or Siri while a clip plays: the clip ends and the feeds' sound comes back.
- The probe in the simulator **and on the Duo** (O4): available, locale, model, seconds, text.
  The speech-recognition reason in Info.plist only arrives with build 18: if iOS wants it for
  this kind of transcription, tapping the probe closes the app (that is the O1 answer, not a bug
  to chase here).
- Live (next live weekend): new clips arrive with only the Radio panel open (the radio now keeps
  the live timing being rebuilt while a player is open, as the map and tower do).
- Tapping a car in the single-feed player while a clip plays: picture time is missing while the
  new feed loads, so the clip stops and the list empties for a moment.
- Pan for later builds (Rivals' one ear each): the clip now goes through a stereo submixer
  before the speed control, so pan on the clip's player applies; not yet heard.

### v1.0-beta.4 groundwork — radio and the closed phone (not in the app yet)

The shared logic for beta.4 is in, ahead of the app builds (17 to 21, after the Las Vegas
weekend). None of it is wired into the app, so build 16 is unchanged. Tested on a computer only
(637 tests, against the São Paulo race and qualifying data); nothing here has run on a phone yet.

- **Team radio:** reads F1's radio clips, shows only the ones already heard at the picture's
  moment, labels each with its lap (or the qualifying part, or the practice time), and queues
  transcripts nearest-first, made on the phone only.
- **Flags and buzzes:** spots yellow, safety car, virtual safety car, red and chequered flags,
  your driver's pit stops and purple sectors as the picture passes them, and spaces the buzzes
  (yellow at most once a minute, never more often than every 2 s).
- **Closed phone:** the three outer-screen pages (picture, Radio Scanner, Gap Thermometer), the
  gap between two drivers with its trend, and the hinge sound mixer (off by default).
- **Logbook:** each driver's laps, stops, tyres, radio and race-control messages up to the
  picture's moment.
- **Settings** for all of the above, with the agreed defaults.
- **Radio check for your Mac** (`--radio`, owner check T-A4): untested against F1's servers; its
  first run is the real test (checklist row b4-radio).

## v1.0-beta.3 — Live data (2026-11-20)

Released as commit `cc569d2`, the app on the phone for the Las Vegas weekend (built 2026-11-17, with
the fixes found on the Duo on Nov 18–19 in build 16).

Builds 11 to 16. In short:

- **Replays:** a track map (floating or docked), the timing tower, driver cards and race marks on
  the timeline follow the picture and never run ahead of it. Tap a car on the map or the tower to
  bring up its onboard.
- **Data layouts for the fold:** Director's Desk when flat; half-open like a laptop, Race
  Engineer (an onboard above, the engineer's console below) or Scrub Deck (the video above, a touch
  timeline of flags, overtakes, stops and laps below).
- **Races get a pit circle** that shows where each car would come out after a stop.
- **Live sessions** use F1's live timing, recorded on the phone so you can rewind, catch up from
  F1's archive when you join late, and offer the next live programme when one starts.
- Each build below lists what it changed and what is still to check. The live parts can only be
  tried on a live weekend (next: Las Vegas, November 19–22).

### v1.0-beta.3, build 16 — final fixes from the beta.3 review

- **Live timing stays light late in a race.** Each rebuild now reads only what arrived since the
  last one: about 20 ms at the end of a full race instead of over 4 s (measured on a computer,
  not yet on the phone). A top-up from F1's archive or a reconnect still rebuilds in full once.
- **Nothing from after the moment you joined shows before it.** On a live race you joined
  part-way, rewinding more than 90 s before the join hides the tower, header, cards, console,
  deck, pit circle, flags and marks behind "Timing catching up" until F1's archive fills that part
  in. Within 90 s of the join the state on joining shows, with the same label on every panel, not
  only the map. ("Show the whole race" doesn't override this: that timing isn't there yet.)
- **Joining live after the start** no longer puts lights out at the start of what the stream
  keeps; the real one comes with F1's archive.
- **Leaving a single feed for multiview** on a live session keeps the live connection: it stays up
  15 s after nothing uses it.
- **When F1 keeps refusing the account,** the note says so after three tries: "F1 isn't letting
  this account into live timing — trying again every minute".
- The tower and the laptop and multiview data regions show the same loading line as the map
  ("Connecting to live timing…" on a live session).
- **Rewinding** clears the console, deck and pit circle built for a later moment at once, and
  picking another car clears the console at once.
- A live map made before enough cars crossed the line gets its start/finish line later on.
- A live feed for another session no longer rebuilds in the background.
- The map stops redrawing while the picture is paused (battery).
- **Sturdier against bad data from F1:** a 0 ms lap no longer crashes the pit circle; positions
  outside 1–99, laps outside 0–999, temperatures outside −50 to 100 °C and wild map coordinates
  are ignored.
- **Tiles in a row are all the same height** (found on the Duo, 2026-11-18): a row whose first tile
  had no second line, such as Replays starting with "Race", cut the text off the tiles after it.
  Every tile now keeps room for two title lines and the line below.
- **Closed, the feed uses the outer screen's full width** (found on the Duo, 2026-11-18): it lost a
  strip on the right. Settings › Fold now also shows the screen's safe edges.
- **Races whose main feed is INTERNATIONAL play again** (found on the Duo, 2026-11-18: Abu Dhabi
  2021 showed "Couldn't load F1 TV: error 404" in every view). F1 TV's own play link for that
  feed names no channel, and asking for its channel number gets a 404. Each feed now plays exactly
  as F1 TV's link says. Checked against F1 TV's public feed list for that race; not yet on the phone.
- **"From the start" / "Watch live" points at the button you tapped** (found on the Duo,
  2026-11-19): on iOS 26 it is a bubble, and hung on the whole page it pointed at the picture.
- **Live sessions play (FairPlay)** (found on the Duo, 2026-11-19: the Las Vegas warm-up said
  "This session is protected"). F1 TV sends live video protected with Apple's FairPlay when asked
  Safari-style, as the app does. The single-feed player now gets each key from F1 TV's licence
  service the way F1 TV's own web player does (its certificate, then the phone's key request),
  and Apple's video engine plays it; nothing is decrypted or stored by the app. Replays are clear
  and take the same path as before. If a key can't be had, "This feed stopped: couldn't unlock
  this live stream: …" says which step failed. Built from F1 TV's web player settings; not yet
  tested on the phone.
- **Live multiview says "Multiview can't play this live session yet"** and offers "Watch the main
  feed": asked the app's multiview way, F1 TV sends live multiview as Widevine, which iPhones
  can't play. Whether the Safari-style request gives all live feeds is checked at FP1.
- **"Watch the main feed"** on multiview's "Not available for this race" (owner request,
  2026-11-19): closes the multiview and plays the race's main feed in the normal player, from
  where the multiview would have started. Close stays as the second button.
- **Settings › About shows which code a build came from** (e.g. "build 16 · 785255d"), when
  installed with `scripts/install-on-duo.sh`, so builds with the same number can be told apart.
- **Older races without multiview say "Not available for this race"** instead of failing: F1 TV
  answers the multiview request for races on its older video system with one plain stream.
- **"Couldn't load F1 TV" now says why** (found on the Duo, 2026-11-18: Abu Dhabi 2021 wouldn't
  play in any view): when F1 TV answers with an error, the message ends with its error number and
  its own words (links are never shown), so a failing race can be diagnosed from the screen.

### Untested — check later (build 16)

- The zero-warnings build (no new files; regenerate with XcodeGen anyway after pulling).
- ~~The same-height tiles~~ checked on the Duo 2026-11-19: the Race Weekend rows show every tile's text in full.
- Closed: the feed reaches both side edges of the outer screen. ("Safe edges" read 0, 0, 0, 0 closed on the Duo, 2026-11-19: the strip was not a safe-area inset.)
- ~~Live FairPlay~~ checked on the Duo 2026-11-19 (build 16 · 6564599): the Las Vegas warm-up played.
- ~~The live start choice~~ checked on the Duo 2026-11-19 (build 16 · 3073622): it points at the
  button tapped.
- A live session (FP1) › Watch: plays. If not, send the words after "This feed
  stopped:" (no build before this one can play live). The last build without FairPlay is d898169.
- A live session › Watch multiview: "Multiview can't play this live session yet" › "Watch the main
  feed" plays it live.
- Abu Dhabi 2021 › Watch multiview › "Watch the main feed": the INTERNATIONAL feed plays in the
  normal player, from the start (or the saved place).
- ~~Abu Dhabi 2021 › Watch plays the INTERNATIONAL feed~~ checked on the Duo 2026-11-19 (build 16 ·
  58a89f4); its multiview says "Not available for this race", as F1 TV sends one feed.
- São Paulo 2026: switching to the INTERNATIONAL feed plays (it had the same 404 problem).
- Live, joined part-way (Las Vegas): "From the start" or a rewind more than 90 s before the join
  shows empty panels with "Timing catching up"; within 90 s the state on joining with the label;
  the Scrub Deck's lap axis stays empty until F1's archive arrives.
- Live: single feed → multiview without "Connecting to live timing…" again.
- Live: the refused-account note (only if F1 refuses; unlikely with a working account).
- The map pausing with the picture: it may take up to half a second to move again after play,
  and buffering counts as paused; the flying-lap ring's pulse freezes while paused.
- How warm the phone gets and how smooth the feeds stay late in a long live race (the rebuild
  figures above come from a computer).
- Data use when joining late: each top-up try downloads the archive topics whole (up to about
  17 MB late in a race), on mobile data too.
- Small things the review left: a step back (even −1 s) blanks the console, deck and pit circle
  until they are rebuilt, about a second; the console area is blank, not "Tap a car to pick an
  onboard", while a session loads; a paused map may keep old car positions until play or a seek.
- Known, not fixed: after a reconnect, a lap count that rose while disconnected may be read as a
  line crossing at the reconnect, so that car's lap clock and lap window can be off until its next
  crossing.

### v1.0-beta.3, build 15 — Live timing, recording, pit circle, next live programme

- **Live timing.** A live session's map, tower, cards, header, console and deck now come from F1's
  live timing (SignalR at livetiming.formula1.com) instead of the archive, through one connection
  shared by the whole app and closed when nothing uses it. It subscribes to 14 topics, pings
  every 15 s and reconnects 5 s after a drop (after three refusals in a row, every 60 s; a
  refusal never signs you out). Your F1 TV sign-in goes only to F1's timing hosts, never to
  MultiViewer, and is never written down.
  - The map says "Connecting to live timing…" until the first data arrives, then, when needed,
    "Live timing dropped — reconnecting…" (the data in hand stays up) or "Live timing is
    connected, but F1 isn't sending car positions".
  - The session is rebuilt from live timing at most every 2 s, stretched to 4 times as long as
    a rebuild takes (up to 5 s); the 2 Hz views read the latest one in between.
  - **Live speed readouts:** the console's readouts and the cards' speed come from live car data.
    With "Speed readouts on mobile data" off, live car data isn't asked for on an expensive
    connection (13 topics then), and comes back once on Wi-Fi.
  - A live feed for another session than the one on screen shows "No timing for this session".
- **Rewinding a live session** works from the start of what was followed: the session's timing is
  recorded on the phone (Caches/live, one file per session, written every 2 s, appended to when
  you come back to the same session, deleted after 7 days) and played back to the views.
- **Catching up:** before the moment you joined, the views show the state on joining, labelled
  "Timing catching up", until F1's archive fills that part in. The app asks the archive at once,
  then every 2 minutes for up to 6 hours, until it reaches within 30 s of the join; a new session
  starts that over.
- **Pit circle** (races; the map panel's "Pit circle" / "Map" switch, floating or docked): the lap
  as a circle in time at the leader's pace, finish at the top, cars clockwise by their gap to the
  leader, cars in the pit lane on the inner ring.
  - Labels show the gap to the car ahead, or to the leader with "Gaps: car ahead" / "Gaps:
    leader". Lapped cars show F1's own text ("1L").
  - **Tap or hold a car** to measure every gap to it and see its pit window ("If HAM stops now,
    out 2.1 s behind NOR"), with the arc a stop costs drawn behind it; tap it again to let go.
    Holding a car on the map shows the same line for a few seconds.
  - Before the leader has finished a lap: "The circle starts once the leader has finished a
    lap."; after joining a live race part-way, until the leader's next crossing: "The pit circle
    appears when the leader next crosses the line."
  - The pit loss is this race's median clean stop; once three or more are measured it is kept
    for the circuit and used the next time before any stop is made there (else 22 s). The race
    that measured it never reads it back: rewound to before its stops, it shows what was kept
    before it (or 22 s).
- **Next live programme:** while you watch a live programme, F1 TV's "live now" list is checked
  every 60 s. A programme that has gone live since you opened yours (or any live one once yours
  has ended) is offered at the top of the video with "Switch" and "Not now"; "Switch" opens it at
  the live edge the same way you were watching (multiview or single feed), "Not now" isn't asked
  again for that programme. Never shown in picture in picture.

### Untested — check later (build 15)

- The zero-warnings build (regenerate the project with XcodeGen first: build 15 adds
  `DuoApp/Timing/LiveModels.swift`, `LiveConnection.swift`, `LiveRecorder.swift`,
  `PitCircleView.swift` and `NextLivePrompt.swift`).
- **T-C, the first live weekend after this build** (nothing of it can be tried without a live
  session):
  - live timing connects ("Connecting to live timing…" then the map), the map and tower match
    the picture, and the console's and cards' readouts move;
  - a dropped connection (airplane mode for 10 s) says "Live timing dropped — reconnecting…" and
    recovers without doubled laps, pit stops or race control messages;
  - rewinding a live session shows what was followed; closing and reopening the same session
    keeps the earlier part; "Timing catching up" before the join, gone once F1's archive has the
    session;
  - **first live weekend: seam/top-up with a real subscribe result** — the join between the
    archive and the live data has only been checked against snapshots built from the archive,
    never a real subscribe result. The recording file is the recording format, so the first
    weekend's `Caches/live/{sessionKey}.txt` can become a test fixture: please keep one;
  - "Live timing is connected, but F1 isn't sending car positions" if F1 sends none;
  - a live race showing "No timing for this session" while F1's live timing runs would mean F1
    TV's session key and live timing's differ (the app only shows live timing for the session
    on screen): note which session it was;
  - with "Speed readouts on mobile data" off on cellular, the readouts stay empty and come back
    on Wi-Fi;
  - the next-live prompt: offered when another programme goes live (or yours ends), "Switch"
    opening it the same way, "Not now" not asking again, never in picture in picture;
  - a live session moving on to another session (SessionInfo's path) reconnects and starts a new
    recording file.
- **T-D, the exit test** (São Paulo 2026 race replay): the map and timing match the picture, a
  tapped car brings up its onboard, Race Engineer and Scrub Deck work in laptop posture.
- The pit circle on the São Paulo race replay: cars spaced by their gaps, the finish at the top,
  the gap toggle, tap or hold a car for its window, the arc a stop costs, cars in the pits on the
  inner ring; the map's hold (a long press on a dot) showing the window; whether the long press
  ever steals a tap meant to open an onboard.
- The pit circle redraws at 2 Hz (the leader moves in small steps), built off the main thread;
  holding a car on the map still measures the race's stops once on the main thread (a short
  pause late in a long race).
- Smoothness late in a long live race: each rebuild parses every message so far again (off the
  main thread); the interval stretches with the cost.
- A rewind further back than 15 minutes on a live session shows no speed readouts (live car data
  is kept for the last 15 minutes only).
- Coming back to a live session after a break (or a reconnect after more than 3 s): the stretch
  between the earlier visit and the new join shows the earlier visit's last state labelled
  "Timing catching up". The archive top-up fills in only what came before the first join, so
  that stretch keeps the label.
- Resuming a bookmark saved during a live session opens it as live (live timing and the
  next-live check) only while F1 TV still lists it as live now, in the single player and the
  multiview. Once the session has ended, the same bookmark opens as a replay with archive
  timing. Untested: resuming while F1 TV's live-now list can't be read opens it as a replay.

### v1.0-beta.3, build 14 — Race Engineer and Scrub Deck

- **Race Engineer** (laptop, ⟳ with timing): the top screen shows an onboard — the main feed if
  it is one, else your driver's onboard, else the first onboard among the feeds — brought to the
  main spot without moving the sound. With no onboard among the feeds, "Tap a car to pick an
  onboard" shows over the main feed. Leaving Race Engineer puts the previous main feed back if
  nothing else changed; once you have tapped a car the arrangement is yours and stays. The
  bottom screen is the console:
  - speed (km/h or mph), gear, revs, and throttle and brake bars from F1's car data, holding the
    last value and greying after 5 s; a channel F1 doesn't send shows "—", never 0. The DRS or
    Aero light shows only when channel 45 carries something: São Paulo 2026 has no channel 45,
    so there is no light;
  - position, the car ahead and behind with the gap and whether it is closing or growing over the
    last 3 laps — tap either to make it the top onboard;
  - tyre and laps on the set, and "Pit now → P7 behind ALO" from the pit-circle maths (before the
    leader has finished a lap: "The circle starts once the leader has finished a lap."; joined
    late mid-race: "The pit circle appears when the leader next crosses the line.");
  - the last 5 laps with sector colours;
  - a mini map with only this car highlighted (tap a car there to pick it);
  - the drawn and labelled "Saved for beta.4: team radio" spot.
  In Race Engineer any car tapped (console, map, tower, Battle chip) becomes the top onboard;
  when no other spot can take it (the usual four feeds: an onboard, the world feed you hear, the
  tracker and the data feed), it takes the top onboard's place — never the feed you hear. The
  feeds remembered from Race Engineer (for next time, a preset, or "make these the default")
  keep the feed that was the main one before it first, even after a tap.
- **Scrub Deck** (laptop, the default with one feed): an event strip — lights out, pit stops
  (small ticks, a tall one for your driver), safety car, VSC and red flag bands, each new fastest
  lap, retirements, the chequered flag — and, for races and sprints, a lap chart with one line per
  driver and yours highlighted. Qualifying and practice show the strip by time.
  - **No spoilers:** both are drawn only up to the picture; the rest is a hatched, empty fog that
    fills in as the race plays.
  - **Drag** anywhere to preview a moment (its lap and time are shown); letting go moves every
    feed there, as the scrubber does. In the fog the moment is spread evenly over the rest of the
    video, so the lap there isn't shown.
  - **Tap a marker** to jump to 5 s before it; **tap a line** to highlight that driver and get
    "Open onboard".
- **Settings › Track map › "Show the whole race"** (was "Show the whole race on the Scrub Deck"):
  off by default; on, the Scrub Deck shows the whole race with no fog, and the timeline every flag
  period.

### Untested — check later (build 14)

- ~~The zero-warnings build~~ — checked 2026-11-17: build 14 built on the Mac with no
  warnings and runs on the iPhone Duo simulator.
- **T-B4, the exit test's laptop part** on the São Paulo 2026 race replay: in laptop posture,
  Race Engineer's console follows the top onboard, and dragging the Scrub Deck moves every feed
  to that moment.
- Race Engineer's top onboard: the main feed when it is an onboard, else My driver's, else the
  first onboard; the sound staying on the feed you were hearing; "Tap a car to pick an onboard"
  over the main feed with no onboard among the feeds; tapping the car ahead or behind (and a car
  on the mini map) making it the top onboard; the previous main feed coming back when you leave
  Race Engineer (⟳ or a fold change) without having changed anything.
- The readouts against the onboard picture (speed, gear, revs, throttle and brake), greying after
  5 s without data, and "—" for a channel F1 doesn't send; on a live session no readouts until
  live car data comes (build 15).
- **The active-aero light rule is provisional:** for 2026 the light shows (labelled "Aero") only
  if channel 45 changes in the car data, lit for any non-zero value. No 2026 data seen so far
  carries channel 45 (São Paulo 2026 has none, so no light there). Check it the first time a
  2026 session sends the channel.
- "The pit circle appears when the leader next crosses the line." shows only after a late join
  to a live session (up to a lap); it can't be seen on a replay.
- The Scrub Deck's fog: nothing past the picture before letting go of a drag; it fills in after
  the seek and as the race plays; with "Show the whole race" on, no fog. Dragging into the fog
  lands at an estimated lap (the video's time is spread evenly to its end).
- A marker tap landing 5 s before the event on the video (lights out, a pit stop, a band's
  start), after a −1 s / +1 s nudge too.
- Tapping a lap chart line and "Open onboard"; with one feed this adds a feed, and the Scrub
  Deck stays (it becomes the choice for the new feed count, unless it doesn't fit the screen).
- Whether the controls' bottom bar covers the console or the deck on the laptop's bottom screen,
  and the console's fit at 669 × 455 (and narrower).
- Qualifying and practice: the strip by time, with no lap chart.
- Tapping the car ahead or behind with the usual four feeds: it replaces the top onboard (the
  sound stays on the world feed). Closing the multiview from Race Engineer and opening it again,
  after a tap too: the world feed is the main feed with the sound, as before Race Engineer's
  swap; a preset saved or "make these the default" in Race Engineer keeps that order too. After a
  tap, leaving Race Engineer keeps the onboard as the main feed.
- A replay opened before lights out: the Scrub Deck is all fog until lights out (scrub past it
  with the timeline first); the pre-race part can't be reached from the deck.
- "Tap a car to pick an onboard" with only world, tracker and data feeds adds a feed, and Race
  Engineer stays for the new feed count.
- Smoothness late in a long race with the console or the deck open: both are now built off the
  main thread from the whole session so far (the test data has only 8 laps), and not again while
  paused. After a seek or a −1 s / +1 s, they catch up within half a second.
- VoiceOver on the Scrub Deck: the chart is one element (swipe up or down to move 30 s), and a
  highlighted driver's "Open onboard" button can be reached.

### v1.0-beta.3, build 13 — Duo data layouts and the tracker delay

- **Data layouts.** Once a session's timing has loaded, ⟳ offers each fold's data layout after
  its usual ones, remembered per posture and feed count like any other choice:
  - **Flat — Director's Desk:** the tower as a full-height column on the right, the main feed as
    large as fits beside it, and below it a row with up to two other feeds and the map. A fourth
    feed keeps playing out of sight.
  - **Book — Data screen:** the feeds on the left screen (one, two stacked, or a 2 × 2 grid), the
    map over the tower on the right. Nothing crosses the fold.
  - **Laptop — Race Engineer and Scrub Deck:** the main feed on the top screen, the bottom screen
    kept for the console or the deck, labelled "Race Engineer — next build" and "Scrub Deck — next
    build" until build 14. With one feed, Scrub Deck is now the default; beta.2's "Saved for
    beta.3" placeholder is gone. Without timing, the bottom half says "Loading timing…" or "No
    timing for this session" instead.
  The map and tower in these layouts are the same as the floating panels (tap a car, the Battle
  chip, −1 s / +1 s, turning the map); a floating panel the layout already shows hides while it
  does, and the Map button hides while the layout shows both. Layout changes and folds glide, as in beta.2. Without timing (loading, unavailable, or no
  timing for this session) a remembered data layout shows the fold's default instead, and comes
  back once the timing is there.
- **The tower fits its width:** narrower than its full set of columns (a resized panel, the
  Director's Desk column) it drops the interval, then the last lap (PIT then shows in the gap's
  place).
- **Tracker delay.** Settings › Multiview › "Tracker delay", in 0.5 s steps up to 20 s: the
  multiview keeps the TRACKER and DATA tiles that far behind the main feed. Made the main feed,
  TRACKER sets the pace and the others run level with it. It starts at 0 s until the lag has been
  measured.

### Untested — check later (build 13)

- ~~The zero-warnings build~~ — checked 2026-11-17 with build 14.
- **T-B3:** each fold's data layout on the São Paulo race replay — Director's Desk (flat, 1–4
  feeds), the book data screen (1–4 feeds), Race Engineer and Scrub Deck (laptop, 1–4 feeds) —
  and the glides between them and across folds, with the same views moving (no video restarts).
- The labelled placeholders on the laptop's bottom screen, and nothing drawn there on a screen
  too small for the deck.
- The map and tower in a layout: tapping a car or a row, the Battle chip, the header's controls
  fitting Director's Desk's 240 pt map slot, and the 200 pt tower column without the interval and
  last-lap columns.
- A floating panel hiding while the layout shows it, and coming back with a plain layout; the
  Map button gone while the layout shows both the map and the tower (Director's Desk, the book
  data screen) and back with any other layout.
- Laptop with one feed: "Loading timing…" in the bottom half while the timing loads, "No timing
  for this session" on a video without timing (a highlights video), and nothing there once the
  Scrub Deck takes over.
- An error over the multiview hides the layout's map and tower, as it hides the floating panels.
- A remembered data layout falling back to the fold's default on a video without timing, and
  coming back on a replay with timing.
- **The tracker delay default (T-B1):** still 0 s. Read how many seconds the TRACKER tile runs
  ahead of the world feed and set that as the default in the next build. Then check that with the
  delay set, TRACKER and DATA hold that far behind the world feed, with the main feed swapped
  (TRACKER as the main one: the others run level with it), after picture in picture, and on a
  live session.

### v1.0-beta.3, build 12 — tower, driver cards, tap a car

- **Timing tower.** The Map control's second panel is now the tower, twice a second at picture
  time: position, team colour, code, last lap (or PIT) in purple or green for pace, the gap
  ("Leader" in a race, "Fastest" otherwise), the interval and the tyre (a compound ring with its
  letter, and laps on the set). In qualifying the knockout zone is shaded and knocked-out cars
  are dimmed. Its header shows "Lap 23/71" in a race or the session clock otherwise, the track
  status, and the air and track temperature with a rain mark.
- **Battle.** In a race, when your driver (Settings › Multiview › My driver) is within 1.0 s of
  the car ahead or behind for two timing updates in a row, both rows glow and a "Battle" chip
  appears on the map's header; tapping it opens the rival's onboard. Off with no driver picked.
- **Driver cards** over every onboard, in multiview and in a single feed: position, number and
  surname in the team colour, the running lap clock (PIT in the pits), the lap time for 6 s
  after the line, three sector bars, the interval, and the speed in km/h or mph following the
  phone's region (hidden when its data is more than 5 s old). Long-press a card for "Hide card";
  a small button brings it back. On the map, a car on a flying lap in qualifying gets a yellow
  ring.
- **Tap a car** on the map or a row of the tower to open its onboard: in multiview it becomes
  the main feed if it is showing, else fills an empty spot, else replaces the least interesting
  onboard (never the main feed, the feed you hear, or the world feed, tracker or data); the new
  feeds are remembered as a swap's are. In a single feed the player switches to that onboard at
  the same moment. "No onboard for car 44 in this session." and "No free spot — change a feed in
  the editor." say when it can't.
- **Speed readouts** come from F1's car data, downloaded in the background once an onboard
  shows (byte ranges when F1 serves them), kept on the phone for 7 days, and paused on mobile
  data when "Speed readouts on mobile data" is off. For a session F1 hasn't closed yet, the
  download keeps asking for more every minute rather than stopping at what was there. Live
  broadcasts don't use it (their car data comes with live timing in a later build).

### Untested — check later (build 12)

- ~~The zero-warnings build~~ — checked 2026-11-17 with build 14.
- **T-B2:** tap a car on the map and on the tower; the card shows the lap time and the speed.
- Tap-a-car in multiview: a car already showing becomes the main feed; an empty spot fills; the
  least interesting onboard is replaced; the notices; the last-used feeds after it.
- Tap-a-car in a single feed: the onboard starts at the same moment as the feed before it.
- The card's long-press "Hide card" on a tile beside the tile's own press-and-hold drag; "Show
  card" afterwards; the card's size on a small tile and clear of the speaker button.
- The speed readout: units on a phone set to the US or UK region (mph) and elsewhere (km/h);
  hidden before the download reaches the picture and after a seek past it; the download pausing
  on mobile data with the switch off, and not fetched again after a seek back.
- The tower's columns fitting the panel's default width, the battle glow and chip during a race,
  and the knockout shading in qualifying.
- The yellow ring on a car's flying lap in qualifying (the trimmed fixtures stop before any).
- A replay watched soon after the session: the speed keeps coming as F1's car data grows, and the
  file isn't treated as complete until F1 marks the session finalised.
- The notices "Couldn't load this session's onboards…" (single feed, offline) and "Car N's onboard
  has stopped…" (multiview); cards only on the feeds the layout shows (e.g. closed, one tile).

### v1.0-beta.3, build 11 — data on replays

- **Track map on replays.** On a race, sprint, qualifying or practice replay, "Map" in the
  multiview controls (and beside Close in the single-feed player) shows the track map as a
  floating panel: every car in its team colour with its three-letter code, dimmed in the pits,
  the start/finish line, corner numbers, yellow sectors, and the outline in yellow under a safety
  car or VSC (red for a red flag), with a caption. It follows the picture: the stream's clock less
  7 s, with −1 s / +1 s on the panel and in Settings › Track map ("Reset to −7 s"). ⟲ ⟳ turn the
  map, remembered per circuit. Panels move by their header, resize from the corner or with a
  pinch, and remember their place per fold. The tower panel is a placeholder until build 12.
- **Timeline marks** under the multiview scrubber: lights out (session start outside races) and
  the chequered flag, plus safety car, VSC and red flag periods only as far as you've watched
  (all of them with "Show the whole race").
- Shows, highlights and press conferences get no data panels ("No timing for this session").
- Settings › Track map also has "Show the whole race on the Scrub Deck" (it also shows every
  flag period on the timeline) and "Speed readouts on mobile data" (used from a later build).

### Untested — check later (build 11)

- The map moving with the São Paulo replay within about a second (the zero-warnings build was
  checked 2026-11-17 with build 14);
  −1 s / +1 s; how far the TRACKER tile runs ahead of the world feed (owner check T-B1).
- The archive accepting the F1 TV token from the app; the retry line when offline.
- Dragging, resizing and pinching the panels, and their places per fold; AVKit's own controls
  in the single-feed player with the panels off and on.
- The timeline marks' positions against the scrubber's track.

## v1.0-beta.2 — Multiview and fold (2026-11-14)

- **Multiview.** On a session with two or more feeds, Premium accounts get a "Watch multiview"
  button: four feeds play at once, in step, from one F1 TV request. Other accounts see
  "Multiview needs F1 TV Premium".
- **Fit to the screen for every fold.** Flat, half-open like a book, half-open like a laptop and
  closed each get their own layouts for one to four feeds, using as much of the screen as the
  16:9 picture allows and keeping feeds out of the fold unless you pick the layout that spans it. "Switch layout" (⟳) goes through the
  other layouts for that fold and feed count, including one feed per screen when half-open, and
  remembers your choice. Folding and unfolding glides the feeds to their new places without
  restarting them. Closed, you swipe left or right to change the feed.
- **Arrange by hand.** Tap a small feed to swap it with the big one (tap again to swap back), or
  press, hold and drag a feed onto another to trade places.
- **Sound from any feed.** Each feed has a speaker button; the sound and the red SOUND badge move
  to that feed without moving it.
- **Choosing feeds.** The default four are the world feed, your driver's onboard, the tracker and
  the data feed. A "Pick your driver" sheet asks once after signing in (Premium accounts), and
  Settings › Multiview › My driver changes it. The feeds editor changes any spot, clears all,
  resets to default, and saves up to 8 named presets of feeds and layouts. The last feeds you
  used come back next time.
- **Fewer than four feeds.** When there are fewer than four (a feed removed, a remembered feed
  missing from this session, or a session with fewer feeds), the app asks once whether to keep
  four spots or fit the rest to the screen, and remembers the answer (Settings › Multiview › When a feed is missing).
- **Controls.** Play and pause, one timeline for every feed, speed from 0.5× to 2× (kept between
  videos; catching up to live goes back to 1× for that video), commentary language or Track FX for the feed with the sound, and LIVE during live
  sessions. They fade after a few seconds; tap "•••" or the space around the feeds to bring them
  back.
- **When the phone can't keep up,** the other feeds pause with "Paused to keep the main feed
  smooth" and come back in step. A speed that was too much is remembered while the app is open.
- **Picture in picture** for multiview (the feed you're listening to) and for a single feed.
- **Resume** reopens multiview at the same moment; its banner reads "Multiview · …".
- **Live sessions** ask "From the start" or "Watch live" before playing, and "From the start"
  starts at the start (Android 0.97–0.98).
- The multiview request identifies as the Android web player, which is how F1 TV returns every
  feed at once.
- The hidden test screen from beta.1 is removed.

### Untested — check later

Built and reviewed, but not yet tried by the owner:

- Builds 5 to 10 (controls, picture in picture, resume and live start, clean-up, final fixes):
  the simulator check for each (build 9 compiled on the Mac; build 10 only clears its one
  warning).
- Picture in picture: leaving the app, coming back by the window and by the app icon, the
  window's close button, and another app taking over picture in picture.
- Resume of a multiview session after closing the app, and the banner showing the right moment
  after a single feed's picture in picture is closed.
- Picture in picture for a single feed, started from the player's button (the player hides, the
  window brings it back), and "Watch multiview" pressed while that window is open.
- Picture in picture when the feed with the sound is hidden (closed phone, across the fold, one
  feed per screen).
- The commentary language menu and the timeline scrubber in multiview.
- Expired links: after a long pause (past the stream links' expiry), a swap or preset asks F1 TV
  once for fresh links and carries on. If it doesn't, the feed shows "This feed stopped" or
  multiview ends with an error; closing and resuming recovers.
- Speed kept between videos; a speed that struggled being remembered; the note it shows.
- The feeds editor's preset row (the menu and the tap sharing one row).
- VoiceOver on the feeds.
- Live-only: LIVE, the drop back to 1× at the live edge, "From the start" / "Watch live", and the
  multiview layouts on a live race (next live check: Las Vegas, Nov 19–22).
- The beta.2 exit test: four São Paulo feeds for 10 minutes without stalling, and every fold
  keeping the same feeds in step at the same moment.
- On the real iPhone Duo (beta.7): everything above on the hardware.

## v1.0-beta.1 — Foundation (2026-11-13)

- Approved roadmap to v1.0: seven betas, one release candidate, then launch.
- App named Apex DuoView: an iPhone app for watching F1 TV, built around the iPhone Duo's fold.
- Sign in with your F1 TV account on F1's own page, or paste a sign-in token instead. The app
  remembers it on your phone. If it expires you see a message with a Sign in button, and if F1 TV
  can't be reached when the app opens you can try again.
- Three rooms:
  - Race Weekend: live and upcoming sessions, the weekend's schedule and a Continue watching
    banner.
  - Paddock: rows of F1 TV's featured and recent content.
  - Archive: browse by season and race weekend, back to 1981.
- Open any session to see its feeds, including every onboard, and play one.
- The player plays one feed full screen, with a choice of commentary language or race sound
  without commentary (Track FX), and audio that keeps going when the screen is off. Picture in
  picture comes in a later beta.
- Bookmarks and resume: the app remembers where you stopped in each session, and picks up there
  when you reopen it, even after the app was closed.
- If your F1 TV account has no video plan, the app tells you so after sign-in.
- Settings shows the app version, for example "Apex DuoView v1.0-beta.1 (build N)".
- A fold adapter that reads the phone's hinge, with a readout in Settings and a simulated fold
  for testing without the hardware. The first thing that follows the fold: when the phone is
  half-open like a book, Settings sits on the right-hand screen instead of the left, and glides
  to the middle when you open the phone flat and back when you fold it again.
- A dark style with near-black backgrounds, silver text and racing red, and a new app icon,
  also shown on the launch screen, the sign-in screen and in About.
- A hidden test screen that checks how well two feeds stay in step, for the multiview work
  planned for later betas.
- DuoCore logic library: F1 TV request building, sign-in exchange and cookie decoding, resume
  bookmarks, watch history and the resume decision, with tests that run on every push.
- Throwaway stream check confirming F1 TV serves iPhone-playable streams for replays, with a
  live-session mode, a live timing recorder and fixture recording.

Known limits: no multiview yet, the dark style only, and live sessions are not yet verified.
