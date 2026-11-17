# Changelog

Versions follow the standard in [docs/roadmap.md](docs/roadmap.md).

## Unreleased

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
    beta.3" placeholder is gone (without timing, the bottom half stays empty).
  The map and tower in these layouts are the same as the floating panels (tap a car, the Battle
  chip, −1 s / +1 s, turning the map); a floating panel the layout already shows hides while it
  does. Layout changes and folds glide, as in beta.2. Without timing (loading, unavailable, or no
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
  Map button while both are in the layout (it switches the floating panels, which stay hidden).
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
