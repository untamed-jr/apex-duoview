# Changelog

Versions follow the standard in [docs/roadmap.md](docs/roadmap.md).

## Unreleased

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
    for the circuit and used the next time before any stop is made there (else 22 s).
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
- The pit circle redraws at 2 Hz (the leader moves in small steps), and holding a car on the map
  measures the race's stops once on the main thread (a short pause late in a long race).
- Smoothness late in a long live race: each rebuild parses every message so far again (off the
  main thread); the interval stretches with the cost.
- A rewind further back than 15 minutes on a live session shows no speed readouts (live car data
  is kept for the last 15 minutes only).
- Coming back to a live session after a gap: the part between the earlier visit and the new join
  shows the earlier visit's last state, without the "Timing catching up" label (the label covers
  only times before the first join), until the archive fills it in.

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

- The zero-warnings build (regenerate the project with XcodeGen first: build 14 adds
  `DuoApp/Timing/RaceDataModels.swift`, `RaceEngineerConsole.swift` and `ScrubDeck.swift`).
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

- The zero-warnings build (regenerate the project with XcodeGen first: build 13 adds
  `DuoApp/Multiview/DataRegionViews.swift` and removes `DuoApp/Multiview/ReservedArea.swift`).
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

- The zero-warnings build (regenerate the project with XcodeGen first: build 12 adds four files
  to `DuoApp/Timing`).
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

- The zero-warnings build, and the map moving with the São Paulo replay within about a second;
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
