# v1.0-beta.6 — Between races: design

**Status: DRAFT for the owner, 2026-11-20. Nothing here is approved.** The decisions page is
`docs/design/beta6-questions.html`; each "Question for the owner" below is on it in plain words.
Until the owner answers, every recommendation is only a proposal. Choices the controller made are
marked **(controller's call)**; features beyond the roadmap are **(added)**.

## Goal and exit test

The beta for the days without a race, and for the phone when it isn't in your hands. A calendar in
your own time with reminders that fire. The phone stood on a table as a big timing board that
turns yellow or red with the track, or as a lamp counting down to the next session. An atlas of
every race at a circuit since 1981. A one-minute recap on the outer screen when you shut the phone
after the flag. The flag, lap and position in the Dynamic Island and on the Lock Screen. And the
last three Android features still missing: the season calendar with reminders, Driver of the Day
and "what to watch next".

**Exit test (roadmap):** "Calendar shows local times and a reminder fires; Kitchen Board, Countdown
Lamp, Archive Atlas, recap and Dynamic Island work".

**As steps (owner, iPhone Duo simulator, São Paulo 2026 replays unless stated):**
1. **Calendar and a reminder.** Race Weekend › Calendar: the season by month, the next weekend's
   sessions in the simulator's time. Change the simulator's time zone (Settings › General › Date &
   Time): the times move, the days follow. Turn reminders on and allow notifications when asked.
   The repo doesn't hold the remaining race dates; if no session is coming up when this is built,
   Settings › Debug › "Test reminder in 1 minute" schedules one for a made-up session through the
   same path **(controller's call)**; lock the simulator; it fires; tapping it opens the Calendar.
   A real reminder is then checked at the next session F1 TV lists (O3).
2. **Kitchen Board.** On the race replay, tap "Kitchen Board" (Q4). The board fills the screen in
   large type; at the yellow flags on laps 17 and 20 it turns yellow and back. On the qualifying
   replay, the two red flags turn it red.
3. **Countdown Lamp.** Race Weekend › "Countdown Lamp": the next session (or, with nothing listed,
   "Next season's calendar isn't on F1 TV yet"). Settings › Debug › "Pretend the next session is in 6
   minutes": the five lights come on one a minute and go out at the start.
4. **Archive Atlas.** Archive › Atlas: pick Interlagos. Every race there since 1981 is listed (with
   Q8's source), those F1 TV has with "Watch"; one plays.
5. **Recap.** On the race replay, drag past the chequered flag and close the simulator (Settings ›
   Debug › Simulate fold › Closed): the 60-second recap plays on the outer screen.
6. **Dynamic Island.** Play the race replay and go to the Home Screen: the flag, lap and your
   driver's position show in the Dynamic Island (in a simulator of an iPhone with one, if the Duo
   simulator has none; O1) and on the Lock Screen; at the lap 17 yellow the ring turns yellow.

Driver of the Day is live only (6 laps to go in a live Grand Prix): Settings › Debug › "Show the
Driver of the Day note" checks the note and the sheet; the real moment waits for the next live Grand Prix after the build. "Up next"
shows at the top of Race Weekend (feature 9).

## Why

The roadmap gives beta.6 the Duo ideas 5 (fold-shut recap), 10 (Island Flag Ring, "needs device
test"), 14 (Archive Atlas), 22 (Kitchen Board) and 23 (Countdown Lamp), and says the Android app's
features are carried over in betas 1 to 6. Checked against the code on 2026-11-20, three are not in
yet:
- **Calendar and reminders.** The app has each season's weekends (`SeasonView`) and the latest
  weekend's schedule in local time (`RaceWeekendRoom`'s `ScheduleView`), but no season calendar
  with "Upcoming" and no reminders (no `UserNotifications` anywhere in `DuoApp/`). Android:
  `Calendar.kt`, `Reminders.kt`.
- **Driver of the Day.** Android 0.99.9 offers F1's vote near the end of a live Grand Prix
  (`AppState.offerVote`, `Viewer.kt`). Nothing in the iOS app.
- **What to watch next.** Android's home carousel (`AppState.suggestions`, up to 7 picks, each with
  a reason). The iOS Race Weekend room has Continue watching, Live now and the weekend, not the
  picks.

Beta.4's Q10 (approved) also left "lock-screen alerts" to this beta's Dynamic Island work.

## Goals

1. **Calendar** with your local times, and **reminders** that fire before sessions, as Android.
2. **Kitchen Board** and **Countdown Lamp** for the phone standing on a table (Q3).
3. **Archive Atlas:** circuit first, then every race there since 1981, playable where F1 TV has it.
4. **Fold-shut recap** on the outer screen after a session.
5. **Island Flag Ring:** a Live Activity for the Dynamic Island and the Lock Screen, with alerts for
   the biggest flags.
6. **Android carry-overs:** Driver of the Day and "what to watch next" (Q12).
7. **Added:** a countdown widget for the Lock Screen and StandBy (Q7), since the widget extension
   exists for the Live Activity anyway.

## Non-goals (this beta)

- **Push updates to the Live Activity.** Updating it while the app isn't running needs Apple's push
  service and a server to send them; the project has no server (roadmap: "No paid services or
  servers"). The Flag Ring updates while the app runs (feature 7).
- **Recording live timing by alarm, or reminders that move when F1 changes a time while the app is
  closed.** iOS can't wake the app on time; reminders are refreshed whenever the app opens.
- **Adding sessions to the iPhone's Calendar app** (it needs calendar permission); reminders do the
  job **(controller's call; the owner can ask)**.
- **Race results or Driver of the Day winners for the current season beyond what timing shows.**
- **Detecting the standing pose automatically** in this beta (Q4); experiment for beta.7.
- **The Race Table** (idea 12) and the other experiments: beta.7.

## Anti-goals (a failure even if it technically works)

- **Spoilers.** The Kitchen Board, recap, Flag Ring and Lock Screen follow the picture, never the
  timing as it arrives. The Atlas hides results until asked (feature 4). "Up next" never names a
  result.
- **Nagging:** reminders only for what you chose; Lock Screen alerts only for a red flag and a
  safety car (Q11); one Driver of the Day note per race.
- **A board that burns the screen or the battery:** the board dims after the session and lets the
  screen sleep 10 minutes after the flag **(controller's call)**.
- **A new website contacted without the owner's OK.** Only F1's Driver of the Day page is new (Q12).
- **Tokens, signed URLs, the owner's account** in logs, files, notifications, widgets or commits.

## Constraints

Beta.5's constraints still hold (Swift 6 strict concurrency, iOS 27.1, no third-party dependencies,
DuoCore Foundation-only and tested on Linux, the layout and privacy rules), with
`BETA_LABEL = beta.6`, build numbers continuing from beta.5's last.

New:
- **A widget extension target** (`project.yml`, XcodeGen: a WidgetKit app extension embedded in the
  app). It holds the Live Activity's views and, if Q7 is B, the countdown widget. The app's
  Info.plist gains `NSSupportsLiveActivities`. The Live Activity's attributes type sits in a small
  source folder compiled into both targets, because DuoCore can't import ActivityKit
  **(controller's call)**; the state it carries is plain values computed in DuoCore.
- **An App Group**, only if Q7 is B: the widget reads the next sessions the app saved. It is set in
  the signing configuration the owner keeps locally (`Config/Signing.local.xcconfig`), never in the
  repository.
- **Apple frameworks in the app (not DuoCore):** UserNotifications (reminders), ActivityKit and
  WidgetKit (Island and widget), SafariServices (the vote sheet, if Q12 keeps it). CoreMotion only
  if the owner picks automatic standing detection (Q4 C).
- **Apple limits quoted from memory are to be rechecked against Apple's documentation while
  building (O5):** a few dozen pending local notifications per app (64 is the figure usually
  quoted), a Live Activity's maximum run (about 8 hours, then a while on the Lock Screen), and a
  budget for frequent updates.

## Data sources

### What the app already has (verified in the repo)

- **The calendar:** `Catalogue.calendar(season:)` returns the season's meetings (key, round, name,
  place, start, end, F1 TV page); `weekend(_:)` returns a weekend's schedule (sessions and live
  shows with their start, `LIVE_EVENT` until they begin). `CatalogItem.subtitle` already formats a
  start in a given calendar's time zone; `ScheduleView` already shows times in the phone's zone.
- **Live now and next live:** `liveNow()`, and beta.3's next-live offer.
- **Seasons back to 1981:** the Archive room's first season and `seasonVideos(season:)` (flat lists
  before 2018), `raceReplays(season:)`; whether F1 TV really has every race is beta.5's O4.
- **Everything the board, recap and island show:** the loaded session's tower rows, track flags,
  lap count, race events, pit stops, fastest laps, retirements, your driver (`DriverChoice`), the
  battle rule; live timing through the shared SignalR connection; picture time.
- **A session's time-zone offset:** the timing archive's sessions carry a GMT offset
  (`SessionLookup` reads `gmtOffsetSeconds`), but only for sessions in F1's timing index.
- **Watch history:** `WatchHistory.isFinished` and watched time per video, as Android's history.
- **Race history by circuit:** beta.5's Q7 (F1DB bundled, recommended). The Atlas uses the same
  index.

### What is not known yet

- **How early F1 TV lists a weekend's sessions with times, and when next season's calendar appears (O3).**
  The reminders and the lamp read whatever F1 TV lists; nothing is guessed.
- **Which circuit an upcoming weekend is at (O4),** for the lamp's outline. F1 TV's meeting items
  may not carry a circuit key before the weekend; with the F1DB index (beta.5 Q7) the round and
  season give the circuit.
- **Whether the Duo has a Dynamic Island on either screen (O1),** and what the closed phone does
  with the screen off (beta.4's O6, still open). The recap and the Island both depend on it.

## Features

Each feature gives: **Sees**, **Data**, **Copy**, **Replay / live** and **Duo**.

### 1. Calendar with local times (Android carry-over)

- **Sees:** a "Calendar" button with a bell in Race Weekend's top bar. The season by month; in the
  current season the weekends still to come under "Upcoming", the one under way or next marked,
  with its sessions listed under it in your time (Q1): "Fri 21 Nov · 9:30 PM  Practice 1". The page
  opens scrolled to Upcoming (Android). A season picker goes back to 1981: from 2018 the season's
  weekends, before that its full races and other videos, as `SeasonView` (which the Calendar
  replaces for the current season; Archive keeps its season pages) **(controller's call)**. Tap a
  weekend to open it.
- **Data:** `calendar(season:)`, `weekend(_:)` for the weekend in focus, the phone's time zone
  (`TimeZone.current`), refreshed when the app comes to the front and when the zone changes.
- **Copy:** "Calendar"; "Upcoming"; "Your time"; "{weekday} {day} {month} · {time}"; "Times in
  your time zone ({zone})"; "Next season's calendar isn't on F1 TV yet".
- **Replay / live:** nothing live-specific.
- **Duo:** in book and flat, the month list on the left screen and the focused weekend on the right
  **(controller's call)**.

### 2. Reminders (Android carry-over)

- **Sees:** the bell opens a sheet (Q2, recommended): "Session reminders" (off by default, as
  Android); "Only qualifying, sprints and races"; "How early": 5, 15 (default), 30 or 60 minutes.
  Turning reminders on asks iOS's notification permission then, never at launch. A reminder:
  title "{Session} starts in 15 minutes", body "{Weekend}" (Android's words); tapping it opens the
  app on that weekend, or on the live session once it is live.
- **What is scheduled (Android's scope):** the sessions of the weekend under way and the next one,
  replacing what was scheduled each time the calendar is refreshed (the app coming to the front,
  the Calendar opening). That stays well under iOS's pending limit (O5).
- **Data:** the schedule items' starts; `UNUserNotificationCenter` with calendar-date triggers;
  identifiers from the content ID so a moved session replaces its own reminder.
- **Copy:** "Session reminders"; "Only qualifying, sprints and races"; "How early"; "Notifications
  are off for Apex DuoView — turn them on in Settings"; footer "Reminders follow F1 TV's schedule
  when you last opened the app."
- **Replay / live:** checked with the Debug test reminder; a real one at the next listed session (step 1).
- **Duo:** nothing specific.

### 3. Kitchen Board (standing)

- **How the phone stands (Q3):** the recommended reading of "standing on its edges" is the phone
  half-open and stood up like a book on a table, the hinge upright, the inner screen facing the
  room. iOS reports that as book (nothing in the SDK tells standing apart, beta.1 O3).
- **How it starts (Q4, recommended):** a "Kitchen Board" button in the player and multiview
  controls, and in Race Weekend while a session is live (board only, no video).
- **Sees (Q6, recommended layout):** the left screen is a large tower, P1 to P10 then your driver's
  row if lower: position, team bar, code, gap in big digits, a tyre letter. The right screen: the
  lap ("LAP 23/71") or session clock, the track state in one word ("GREEN", "YELLOW", "SAFETY CAR",
  "RED FLAG"), the leader, and your driver's position and gap. On a flag the whole background turns
  the flag's colour (yellow `#FFD60A` for yellow, SC and VSC; red `#FF3B30` for red; beta.3's
  colours) with dark type; it returns to black when the track clears. The screen stays on while
  the board shows; 10 minutes after the flag it dims and lets the screen sleep
  **(controller's call)**. A tap shows Close and the clock nudges.
- **Its clock (Q5, recommended):** with a video playing in the app, the board follows that
  picture. Without one (board from Race Weekend, beside a TV), it uses live timing with a "Match my
  TV" delay: picture time is now minus the delay, which moves in ±1 s and ±5 s steps and is
  remembered. Its starting value is how far F1 TV's own live picture runs behind live timing (its
  stream delay plus the −7 s offset), which the app can read off any live video it plays (O9);
  until that is measured it starts at 30 s, erring towards no spoilers **(controller's call)**.
- **Data:** tower rows, track flags, lap count and clock, your driver, at picture time; live timing
  through the existing connection for the board-only case.
- **Copy:** "Kitchen Board"; "GREEN", "YELLOW", "SAFETY CAR", "VSC", "RED FLAG", "CHEQUERED";
  "Match my TV"; "Timing {n} s behind live"; "Close"; "No live session — the board needs a session
  to follow".
- **Replay / live:** replay tests the board and colours; live adds the board-only clock (next live weekend).
- **Duo:** readability across a room, how the halves' angle looks, heat and battery over a race
  with the screen on (beta.7).

### 4. Countdown Lamp (standing)

- **Sees:** a calm, nearly black screen standing on the table: the next session's name and
  weekend, the circuit outline glowing softly (MultiViewer's outline for that circuit if one is
  cached, else the F1DB drawing if O6 of beta.5 allows, else none), and a large countdown
  ("2 d 4 h" → "4:12:09" under a day → "0:05:00"). In the last five minutes five red lights come on,
  one a minute, and go out at the start **(added)**; the lamp then shows "Live now" with a button to
  watch. Between seasons: "Next season's calendar isn't on F1 TV yet". Opened from Race Weekend (and
  from the Kitchen Board's menu); same standing pose and stay-awake rule as the board, with the
  screen dimmed to its lowest the user allows **(controller's call)**.
- **What it counts to (Q7, recommended):** the next session of any kind (practice included), with
  the race's date in small type; plus the same countdown as a Lock Screen and StandBy widget
  **(added)**.
- **Data:** the calendar (feature 1); the widget reads the next sessions the app saved to the App
  Group and draws the countdown with the system's own timer text, so it needs no updates.
- **Copy:** "Countdown Lamp"; "Next: {Session}"; "{Weekend}"; "Race {weekday} {day} {month}";
  "Lights out in"; "Live now"; "Watch"; "Next season's calendar isn't on F1 TV yet".
- **Duo:** the glow and the dim level in a dark room.

### 5. Archive Atlas (open flat)

- **Sees:** Archive › "Atlas". Open flat: the left screen picks a circuit (Q9, recommended: a grid
  of track drawings in the app's colours, grouped by country, with a search field); the right
  screen lists every race held there since 1981, newest first: year, the Grand Prix's name that
  year, the layout drawing for that era (if allowed, beta.5 O6), and "Watch" where F1 TV has the
  race, else "No video on F1 TV" with nothing to tap **(controller's call: results shown, never a
  video that isn't there)**. A switch, "Show results" (off), adds the winner, pole and fastest
  lap, so old races can be watched unspoiled **(controller's call)**. Each row with a video also
  has "Then and Now" (beta.5) when a current session at that circuit exists.
- **Data:** the race-history index (Q8, the same question as beta.5's Q7); F1 TV's catalogue for
  the videos, matched by season and name (beta.5's classic index). Without F1DB, the Atlas can only
  group F1 TV's own videos by Grand Prix name, not by circuit, and can't list races F1 TV doesn't
  have; it is then called "Races by Grand Prix" **(controller's call)**.
- **Copy:** "Atlas"; "Pick a circuit"; "Races at {circuit}"; "{n} races since 1981"; "Watch";
  "No video on F1 TV"; "Show results"; "Race history: F1DB, CC BY 4.0" in About.
- **Duo:** on the closed phone and other iPhones, the picker then the list as two pages.

### 6. Fold-shut recap (closed)

- **Sees (Q10, recommended):** when the phone is closed after the picture has passed the chequered
  flag (race or sprint; after Q3's flag in qualifying), the outer screen plays a 60-second recap
  once per session: six cards of about 10 s, swipe to skip, tap to pause:
  1. the podium, large, and P4–P10;
  2. your driver's race: start and finish places, stops and tyres, best lap (skipped with no
     driver);
  3. the fastest lap;
  4. the biggest gain (most places made);
  5. the race's story strip: lights out, safety cars, VSCs, red flags and the flag on one line;
  6. a radio moment **(added)**: the winner's last transcribed clip after the flag, if beta.4 has
     one.
  It ends on the closed Picture page. The video keeps playing (the podium) and its sound; the recap
  is silent.
- **Data:** the loaded session at picture time (tower at the flag, `RaceEvents`, pit stops, stints,
  TeamRadio with transcripts). Live: the same once the flag is reached in the picture.
- **Copy:** "Recap"; "Podium"; "{CODE}'s race"; "P{start} → P{finish}"; "{n} stops"; "Fastest
  lap"; "Most places gained"; "Team radio"; "Swipe to skip".
- **Screen off (beta.4 O6):** if closing turns the screen off and the app goes to the background,
  the recap waits and plays the next time the outer screen shows the app, within 30 minutes
  **(controller's call)**.
- **Duo:** the real outer screen (466 × 678 pt, measured).

### 7. Island Flag Ring (Dynamic Island and Lock Screen)

- **Sees:** while a session plays and you leave the app (Home Screen, another app, locked), a Live
  Activity shows:
  - **compact:** on the left, a ring in the track's colour (green, yellow, red; yellow with "SC" for
    a safety car) around your driver's number (the leader's with none picked); on the right "P4"
    or "L23/71";
  - **minimal** (when another app also has an activity): the ring alone;
  - **expanded and Lock Screen:** the session name, "Lap 23/71", the flag in words, your driver's
    position and the gaps ahead and behind.
- **When it runs (Q11, recommended):** it starts by itself when you leave the app during a live
  session or a replay with timing, and ends when you stop watching, at the session's end plus 10
  minutes, or when iOS ends it (O5). Settings › "Dynamic Island" turns it off.
- **Alerts (Q11):** a red flag and a safety car light the Lock Screen with a short alert (an
  activity update with an alert), which is beta.4 Q10's promised lock-screen alert. Nothing else
  alerts.
- **Updates:** from the app only, while it runs (the audio background mode keeps it running while a
  video plays). Only on a change (flag, lap, position), at most every 2 s **(controller's call)**,
  and always at picture time, so the island never runs ahead of the video. With the video paused in
  the background for long, iOS may suspend the app; the activity then shows "Paused" and its last
  state (O6).
- **Data:** track flags, lap count, your driver's tower row and battle gaps, at picture time.
- **Copy:** "Lap {n}/{total}"; "GREEN", "YELLOW", "SAFETY CAR", "VSC", "RED FLAG", "CHEQUERED";
  "P{n}"; "{gap} to {CODE}"; "Paused"; alert "Red flag · Lap {n}" / "Safety car · Lap {n}".
- **Duo:** whether either screen has a Dynamic Island (O1); the Lock Screen view works either way.

### 8. Driver of the Day (Android carry-over)

- **Sees:** with 6 laps to go in a Grand Prix watched live (not a sprint), or just after the flag
  if within 15 minutes of it, a small note: "Driver of the Day — vote on F1's site" with "Vote" and
  "Not now"; the first note ever also offers "Don't ask again". Once per race. "Vote" opens F1's
  vote page in an in-app Safari sheet over part of the screen while the race plays on (Q12,
  recommended). Settings › "Driver of the Day reminder" (on).
- **Data:** live session, Grand Prix, lap count and total laps, the flag time; Android's numbers (6
  laps, 15 minutes).
- **The page:** Android's address, `https://www.formula1.com/en/page/vote`. It is a website the app
  hasn't opened before, so it needs the owner's OK (Q12). In an in-app Safari sheet the app sees
  nothing of the page; it may ask you to sign in to F1 there (O8).
- **Copy:** "Driver of the Day"; "Vote on F1's site"; "Vote"; "Not now"; "Don't ask again";
  "Driver of the Day reminder".
- **Replay / live:** live only; the Debug note for the simulator.

### 9. What to watch next (Android carry-over)

- **Sees:** an "Up next" row at the top of Race Weekend, above Continue watching: up to 7 large
  tiles, each with its reason (Q12, recommended: Android's order):
  1. "Live now";
  2. what F1 TV features at the top of its home page ("Featured on F1 TV");
  3. after the latest session: "In case you missed it" (under 2 days) or "Catch up" if you haven't
     watched it, else what follows it ("After the race": the post-race show, press conference,
     highlights);
  4. within 7 days of the next weekend: its build-up videos ("Before the {Weekend}") and last year's
     race there ("Last year in {place}");
  5. the next weekend's schedule card ("Next: {Session} · {time}" or "Next race weekend · {dates}");
  6. "Pick up where you left off" (a bookmark under 3 days old);
  7. one race from the archive, a different one each day ("From the archive").
  Anything watched to the end is left out. Android's carousel turns by itself; here it is a
  normal row **(controller's call: a row matches the rest of the iOS rooms)**.
- **Data:** `liveNow()`, `home()` featured items, the latest and next weekend, watch history,
  bookmarks, `archiveRaces()`.
- **Copy:** Android's reasons, quoted above.

## Settings

- **Calendar:** "Session reminders", "Only qualifying, sprints and races", "How early".
- **Standing:** "Kitchen Board": "Match my TV" delay with Reset; "Keep the screen on" (on).
- **Closed phone:** "Recap after the flag" (on).
- **Dynamic Island:** "Show on the Lock Screen and Dynamic Island" (on); "Alerts for red flags and
  safety cars" (on).
- **Driver of the Day reminder** (on).
- **Debug:** "Test reminder in 1 minute"; "Pretend the next session is in 6 minutes"; "Show the
  Driver of the Day note"; "Play the recap now".
- **Remembered:** the Atlas's last circuit and "Show results"; the TV delay.

## Logic library (DuoCore, tested on Linux)

- **Calendar:** months and Upcoming from meetings and a time zone; the focus weekend; the day
  labels across a time-zone change.
- **Reminder plan:** which sessions (main-only rule from Android's titles), the lead, what is still
  ahead, stable identifiers; the test reminder.
- **Countdown:** the text at each scale, the five lights' state, "Live now".
- **Board:** rows, the flag colour state and its words, the TV-delay picture time, the sleep rule.
- **Recap script:** the six cards from a session at the flag, with skips when data is missing.
- **Island state:** ring colour, lap, position and gaps as plain values; the change-only, 2 s rule;
  the alert rule.
- **Up next:** Android's `suggestions` order and rules, ported.
- **Driver of the Day:** Android's `offerVote` rule.
- **Atlas:** races by circuit from the beta.5 index, since 1981; with no index, by Grand Prix name.

## App (built and checked by the owner in the simulator)

- The widget extension target (Live Activity views, the countdown widget if Q7 is B), its
  `project.yml` entry, `NSSupportsLiveActivities`, the shared attributes folder.
- A reminders service around `UNUserNotificationCenter`; the Calendar screen and bell sheet.
- Kitchen Board and Countdown Lamp views, with the idle timer handled while they show.
- The Atlas screens; the recap on the closed layout; the Live Activity controller; the vote note
  and sheet; the "Up next" row.
- The README's Status and Privacy sections.

## Privacy

- **Hosts:** no new host for data. The only new address is F1's Driver of the Day page, opened in an
  in-app Safari sheet only when you tap "Vote" (Q12); the app sends it nothing and reads nothing
  from it.
- **Notifications** are local: the app schedules them on the phone; nothing goes to Apple's push
  service or any server.
- **The Live Activity and widget** show race data only (flag, lap, codes, positions), never your
  account; they are visible on the Lock Screen, which Settings says.
- **Kept on the phone:** the reminder choices, the TV delay, the next sessions for the widget (in
  the App Group, if Q7 is B).
- **README line:** "Reminders, the Lock Screen and the Dynamic Island are handled on your phone.
  The app has no server and sends nothing to Apple's push service."

## Testing

- **DuoCore:** the calendar grouping across time zones (including a weekend that crosses midnight
  in the phone's zone), the reminder plan (main-only, lead, replacing a moved session), the
  countdown and lights, the board's flag states on the São Paulo race and qualifying fixtures, the
  recap script on the race fixture, the island state and its 2 s rule, Up next against Android's
  rules, the vote rule, the Atlas grouping on a small committed F1DB sample. Zero warnings.
- **App:** each build checked by the owner; anything unchecked goes into the CHANGELOG's "Untested —
  check later".

## Work order (builds handed to the owner)

1. **Calendar and reminders,** with the Debug test reminder. Exit test step 1.
2. **Kitchen Board and Countdown Lamp.**
3. **Archive Atlas** (needs beta.5's index).
4. **The widget extension:** Island Flag Ring, alerts, the countdown widget (Q7).
5. **The recap, Driver of the Day and Up next.**
6. **Fixes from the beta.6 review.**

Each build is pushed as it lands, tested or not. Build numbers follow on from beta.5's last.

## Owner checks

- **T-S (before build 2, two minutes, any time):** stand the Duo on a table the way you would for a
  board, and tell Claude which drawing on the decisions page matches (Q3). If it shows the outer
  screen, the board moves there.
- **T-I (when the Duo is next at hand):** look for a Dynamic Island on each screen, open and closed
  (O1); close the phone during a replay and note whether the outer screen stays on with the app in
  front (beta.4 O6).
- **T-B:** each build's zero-warnings build and a short simulator check.
- **T-C6 (the first live weekend after the build):** a real reminder, the board-only live clock, the Flag Ring live,
  Driver of the Day.
- **T-D, the exit test:** above.

## Open items (confirmed while building or on the device, not owner decisions)

- **O1.** Whether the Duo has a Dynamic Island on either screen, and whether the Duo simulator
  shows one. If neither, the exit test's island step uses another iPhone simulator, and the Duo
  shows the Lock Screen view only.
- **O2.** What the closed phone does with the screen off (beta.4 O6, still unanswered): the recap
  and the island depend on it.
- **O3.** How early F1 TV lists a weekend's sessions with times, and when it lists next season.
- **O4.** Whether an upcoming meeting carries a circuit key in F1 TV's data (for the lamp's outline
  without F1DB).
- **O5.** Apple's limits, rechecked in Apple's documentation: pending local notifications, a Live
  Activity's longest run, the update budget, and Live Activities in the simulator.
- **O6.** Whether the app keeps timing and Live Activity updates going in the background while a
  video plays, and what happens when it is paused there.
- **O7.** Screen burn-in, heat and battery with the board on for a race (beta.7, on the Duo).
- **O8.** Whether F1's vote page in an in-app Safari sheet asks you to sign in (it doesn't share
  Safari's cookies).
- **O9.** How far F1 TV's live picture runs behind live timing on the owner's connection (the
  Kitchen Board's starting "Match my TV" delay): the gap between now and a live feed's program
  date-time, plus the timing offset, read at the first live weekend after the build.

## Risks

- **No session to test against** if the season is over when this is built: every live part waits; the Debug paths carry the exit
  test.
- **Stale reminders** if F1 moves a session and the app isn't opened: the footer says so; Android
  has the same limit after a restart.
- **The Live Activity stops** when iOS suspends the app (paused video): it shows "Paused" rather
  than a wrong state.
- **Standing pose guesswork:** T-S settles it before the board is built.
- **The widget extension** is the project's first second target: signing and XcodeGen changes are
  done in build 4 only, and checked by the owner's build before anything else depends on them.

## Questions for the owner

1. **Calendar times.** Your time only; your time with the circuit's time in small type; or a switch.
   **Recommendation:** your time only. The circuit's time needs a source F1 TV doesn't give for
   future sessions.
2. **Reminders.** One switch for every session 15 minutes before (Android); that plus "only
   qualifying, sprints and races" and a choice of how early; or a bell on each session.
   **Recommendation:** the second: Android's two switches plus 5, 15, 30 or 60 minutes.
3. **How you stand the phone for the board and lamp.** Half-open like a book stood on the table;
   like a laptop with the top half upright; or closed and propped up. **Recommendation:** like a
   book, the inner screen facing the room.
4. **How the Kitchen Board starts.** A button; by itself when the phone stays still half-open; or
   both. **Recommendation:** a button now; the automatic start as a beta.7 experiment.
5. **The Kitchen Board's clock.** Only with a video in the app; only live timing with a "match my
   TV" delay; or both. **Recommendation:** both: it follows the app's video, and without one it
   follows live timing held back to match your TV.
6. **The Kitchen Board's layout.** One big board across both halves; the tower on the left and the
   lap, flag and your driver on the right; or one half only. **Recommendation:** tower left, the
   big facts right; nothing crosses the fold.
7. **Countdown Lamp.** Next session, in the app only; next session plus a Lock Screen and StandBy
   widget; or next race only. **Recommendation:** next session, and the widget.
8. **Race history from 1981 (also beta.5's Then and Now).** F1 TV's own lists only; a free, open
   record of every race (F1DB) copied into the app with credit; or a hand-made list.
   **Recommendation:** F1DB inside the app, no new website contacted, credited in About.
9. **Archive Atlas: picking a circuit.** A list by country; a grid of track drawings; or a world map
   (Apple Maps, which loads from Apple). **Recommendation:** the grid of drawings, which needs no
   network.
10. **The recap.** By itself when you close after the flag; only when you tap "Recap"; or off.
    **Recommendation:** by itself, once per session, silent.
11. **Dynamic Island and Lock Screen.** By itself when you leave the app during a session, with
    alerts for red flags and safety cars; by itself without alerts; or only when you ask.
    **Recommendation:** by itself, with those two alerts only.
12. **Two Android extras: Driver of the Day and "Up next".** Both as on Android (the vote page opens
    in a sheet beside the race: a new website, F1's own); only Up next; only Driver of the Day; or
    neither. **Recommendation:** both.

## Sources

- Repo: `docs/roadmap.md` (Duo ideas, the Android carry-over list, the research notes); the beta.1
  spec (beta.6's carry-overs, posture O3), beta.2's postures, beta.3's colours and offsets,
  beta.4's Q10 and O6; `README.md`; `DuoApp/Rooms/` (`RaceWeekendRoom.swift`, `SeasonView.swift`,
  `ArchiveRoom.swift`); `DuoApp/Fold/FoldState.swift`; `DuoApp/Info.plist` (audio background
  mode); `project.yml` (one target today); `Packages/DuoCore/Sources/F1TV/` (`Catalogue.swift`,
  `Models.swift`, `Schedule.swift`); `Packages/DuoCore/Sources/LiveTiming/SessionLookup.swift`;
  `Packages/DuoCore/Sources/Library/WatchHistory.swift`.
- Android (`og-android`, 0.99.9): `Reminders.kt` (15-minute lead, main-only rule, the weekend under
  way and the next), `Calendar.kt` (Upcoming, local times), `AppState.kt` (`suggestions`,
  `offerVote`, the vote page, `MAX_PICKS = 7`), `Viewer.kt`, `Sheets.kt`.
- `docs/research/open-source-f1-data.md` (F1DB, f1-circuits).
- The beta.5 draft, `docs/superpowers/specs/2026-11-20-beta5-showpieces-design.md` (the race
  history index, O4–O6).
