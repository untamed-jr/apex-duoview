# Beta.3 — decisions made while building, and what was left for later

Kept from the build ledger (2026-11-16/17) so nothing decided on the owner's behalf is lost. Each line says what it costs if wrong.

## Rulings

- Ruling: your raw race data files stay in a private folder that git ignores; tests read only small trimmed copies that are committed (the repo is public) — cost if wrong: a path in one script.
- Ruling: the tracker delay is only a saved setting; there is no separate clock feature for it — cost if wrong: none.
- Ruling: the "Aero" light (car data channel 45) was decided from the first 1 MiB of car data; São Paulo 2026 has no channel 45, so there is no light for now, and the build check decides later — cost if wrong: a missing "Aero" light until a later build.
- Ruling: car data is downloaded in byte ranges (measured: they work; the race file is 8.2 MB) — cost if wrong: none, the slower streaming path stays in the code anyway.
- Ruling: JSON reading got a faster path (a full race went from about 30 s to 3.5 s) with identical results — cost if wrong: a slower but correct load.
- Ruling: recordings longer than 24 hours (lines stamped with a day prefix, as Android reads them) are supported — cost if wrong: later lines of a very long recording would be lost.
- Ruling: the first car positions at (0,0) are kept as Android does, but the map skips them — cost if wrong: a stray dot on the map.
- Ruling: the header shows no clock before the first clock mark, even on a late live join — cost if wrong: no clock for the first seconds of a late join.
- Ruling: a loaded session also knows when it started and finished, for the "Lights out" mark — cost if wrong: one more field.
- Ruling: a video's details carry its timing reference, so bookmarks and resumed videos still find timing — cost if wrong: resumed replays show "No timing".
- Ruling: timing is shown only for real sessions (Race, Sprint, Qualifying, Sprint Qualifying/Shootout, Practice), not for shows or highlights such as "Pre-Race Show" — cost if wrong: a pre-race show gets no map.
- Ruling: the timeline mark says "Lights out" for races, but only when race control's RACE START agrees with the session start; otherwise it says "Session start" — cost if wrong: a label.
- Ruling: keep building through the end of beta.3 without waiting for your build checks; each build's check list goes into the CHANGELOG "untested" list — cost if wrong: compile errors in later builds stack up and are fixed together in one wave.
- Ruling: three small layout oddities are left as they are, because the real Duo fold is mid-screen (see "Left for later"); when a data panel has no room the app shows no panel — cost if wrong: a thin deck on odd screens, visible in your build.
- Commits show both the owner and Claude as authors (owner approved 2026-11-16); no history was rewritten — cost if wrong: author labels on past commits.
- Ruling: the lights-out and chequered-flag marks always show (they are session structure, as on Android, and the scrubber's length already shows as much); safety car, virtual safety car and red-flag bands show only up to the picture time, unless Settings "Show the whole race" is on, which now covers timeline bands as well as the Scrub Deck — cost if wrong: one setting's scope, or a chequered mark you may call a spoiler.
- Ruling: if the network fails while looking for a session, the load is retried; if a core topic (timing, track status, session status) fails, the whole load is retried; a failed optional topic is listed apart from "not published" and is not retried on its own — cost if wrong: a flaky optional topic leaves a gap until you reopen the video.
- Ruling: the knockout zone counts the cars still in (2026: 22 cars, 6 out per part), not a fixed 5 — cost if wrong: zone size.
- Ruling: tapping a car never replaces the main tile (as on Android; replacing what you watch is jarring) — cost if wrong: one filter.
- Ruling: a battle starts only after two timing updates that touch your driver or the rival, not any car's — cost if wrong: the battle chip flickers.
- Ruling: a card's lap-time flash without the finished lap's sectors is accepted — cost if wrong: a lap-time flash with no sector colours.
- Ruling: in qualifying, a car rising a lap count as it leaves the pits does not count as crossing the line — cost if wrong: the start/finish line position in qualifying.
- Ruling: if F1's reconnect snapshot leaves out a topic, the last known value stays (for example the last weather) — cost if wrong: a stale readout after an unusual reconnect.
- Ruling: a whole topic changing from a list to an object is read as a full new state — cost if wrong: none, F1 never does this.
- Ruling: a race-control message that appears both in the archive and live is shown once — cost if wrong: one duplicated message at the join.
- Ruling: tapping a car treats a car with unknown state like one on an out lap in races (as on Android; an out lap after a stop is live racing) — cost if wrong: which tile gets replaced.
- Ruling: the battle chip is shown in races only, because intervals in other sessions are lap-time gaps; it is mentioned in the release notes — cost if wrong: none.
- Ruling (replaced by the next head-start ruling below): accept Android's head start on live, so for the first minute the picture time trails the join by the stream's delay and seconds-old join state is shown, labelled "Timing catching up" — cost if wrong: a few seconds of join-time state shown early.
- Ruling: Claude is the committer of every commit, so GitHub shows them as Verified; the author is still credited as agreed, and commits already pushed unsigned stay as they are — cost if wrong: some older commits show as unverified.
- Ruling: after a late live join the pit circle can be missing for up to a lap; the app says "The pit circle appears when the leader next crosses the line" — cost if wrong: a lap without the circle.
- Ruling: the active-aero light is on for any non-zero channel 45 from 2026; it is provisional and on the untested list — cost if wrong: a wrong or missing light.
- Ruling: unfinished car-data downloads are kept and topped up until the session is known to be finished; live sessions skip the archive car data (live car data comes from the live feed) — cost if wrong: a short car-data file for a recently finished session.
- Ruling: the pit circle's reference lap follows the spec — the leader's average only after 5 green laps, before that their typical lap, then their last timed lap — cost if wrong: a slightly worse early estimate.
- Ruling: lapped cars ("1L", "+1 LAP") stay on the pit circle, placed by the gap between their line crossings and the leader's — cost if wrong: a lapped car off by a little on the circle.
- Ruling: the middle lap time uses the upper of the two middle values (as Android does); stop cost is measured against green laps; retired or stopped cars ahead are left out — cost if wrong: a slightly off pit-loss estimate.
- Ruling: where recorded live data meets the downloaded archive, two copies of a line count as the same if they are within 1 s of each other, and the extra safeguard against a wrong match is kept — cost if wrong: a lost or doubled change at the join.
- Ruling: the tracker delay stays at 0 until you measure it — cost if wrong: the tracker may run slightly ahead of the video.
- Ruling: a lapped car's label shows F1's own text ("1L" or "+1 LAP") when its gap is not a time; it is placed by the crossing gap — cost if wrong: a label.
- Ruling: on a laptop with no timing, the empty bottom half shows a quiet "No timing for this session" instead of nothing — cost if wrong: one label.
- Ruling: with the tracker as the main tile, picture time keeps following the main feed — cost if wrong: the map time follows a different feed than you expect.
- Ruling: the Map button is hidden or disabled when the layout already shows both panels — cost if wrong: a button that looks inert.
- Ruling: in Race Engineer a car tap replaces the top onboard (that is the engineered car; the sound never moves) — cost if wrong: one tap behaviour.
- Ruling: adding a feed while in a laptop data layout keeps that data layout if it still fits — cost if wrong: the layout jumps back to a plain list.
- Ruling: layout presets and "make default" saved in Race Engineer store the order with the swap undone, like closing — cost if wrong: a saved preset starts with the swap undone.
- Ruling: the 2 Hz rebuild cost late in a long race is not fixed now; it is on the untested list — cost if wrong: heat and battery late in a long race.
- Ruling: with "Speed readouts on mobile data" off on an expensive connection, 13 topics are subscribed without car data, which honours your data choice (it resubscribes when the setting changes) — cost if wrong: no speed readouts on mobile data.
- Ruling: if the live session's key differs from the video's, the app says "No timing for this session" — cost if wrong: a live video with no timing.
- Ruling: pit loss per circuit is stored only from at least 3 clean stops (the middle value, between 10 s and 45 s) — cost if wrong: a poorer pit-loss number early on.
- Ruling: if F1 refuses the live token, the app retries every 5 s, then every 60 s after three refusals, and never signs you out — cost if wrong: a long wait before live timing returns.
- Ruling: gaps in a live recording after you join stay labelled "Timing catching up"; only the stretch before your first join is filled in — cost if wrong: a labelled hole after a dropout.
- Ruling: a video counts as live only when a live-now signal says so (video details, the live-now list, or an open-ended duration), not because a bookmark was saved live — cost if wrong: a replay of a just-finished race opens in replay mode instead of live.
- Ruling: after a rewind, the pit circle may briefly show the previous (later) circle until the new one is ready — cost if wrong: a half-second of an already-seen circle.
- Ruling: head start narrowed — on live, when the picture time is before your join and beyond the archive: more than 90 s before the join shows nothing and says "Timing catching up" on every timing surface; within 90 s keeps the head start but labels it everywhere — cost if wrong: a viewer rewinding a live race sees empty timing until the archive arrives.
- Ruling: after three refusals the live-token line reads "F1 isn't letting this account into live timing — trying again every minute" (copy chosen on your behalf) — cost if wrong: one sentence.
- Ruling: the live connection stays open for 15 s after the last viewer leaves, so going from single feed to multiview keeps it; the app's 5 s rebuild cap stays — cost if wrong: a dropped and reconnected live link when switching.
- Ruling: the "Timing catching up" state also hides the Scrub Deck and the marks when "Show the whole race" is on, because the timing before the join is not there yet — cost if wrong: one line; you can ask.
- Ruling: the map pauses when the picture time stood still between two ticks, not by the player's play state; restarting can lag up to 0.5 s — cost if wrong: cosmetic.
- Ruling: after a late live join the Scrub Deck lap axis stays empty until the archive arrives; it is on the untested list — cost if wrong: an empty lap axis for a while.

How the work was organised (parallel builds, review rounds) isn't listed; it changed no behaviour.

## Left for later (from the reviews)

### Live

- After a reconnect, a lap that was completed during the gap is read as a line crossing at the reconnect moment, so the lap clock, pit-circle leader and lap window can be off until the next real crossing. Not done (bigger than ruled); on the untested list.
- Real F1 subscribe answer: a real one has not yet been captured to test the join between live and archive; on the untested list.
- Join between live and archive: a nearer earlier copy can push a newly seen topic to the fallback (a brief blip can be lost if the archive is about 1.85 s ahead), a copy more than 1 s behind can double, and the tolerance is unmeasured when Position's clock wins.
- A flaky optional topic has no retry of its own until you reopen the video.
- When the live session changes, the old history replays to a new listener until the new snapshot arrives.
- A bookmark saved while live and resumed after the session ended starts at 0 instead of the saved position (existed in beta.2).
- Gaps in a live recording after you join are labelled, not filled in; filling them is a later idea.
- Picture in picture keeps the timing ticking (battery only).

### Map and pit circle

- Lapped cars' angle on the circle is off while the leader runs slow laps (their rejoin order is right).
- The fixed "1L" label stays while a lapped car's gap grows.
- The rejoin forecast leaves out a car in the middle of a normal stop (as specified).
- Pit loss stored by an earlier unreleased build has no record of where it came from.
- A negative turn direction on the circuit outline is not covered by a test.

### Laptop views

- No minimum height for a laptop deck: a few points tall still counts as usable.
- The Director option is unavailable for 3 or 4 feeds on narrow screens.
- Cycling layouts during a load can overwrite the remembered data layout.
- The stepper row's style differs from the rest.
- The Map button stays hidden while an error hides the regions (cosmetic).
- VoiceOver cannot highlight a deck line to reach "Open onboard".
- In Race Engineer, the remembered former main can go stale if the editor changes the main.
- Background builds of the console and deck are not cancelled when no longer needed (CPU only).
- A new card appears one layout pass late after a feed is set.
- Some LayoutEngine code is no longer used and could be removed.
- The app's wiring is only lightly tested; the timing models are tested beyond marks only partly; re-attaching from multiview to the player clears the marks request (low risk).
- The battle chip counts any field change of the pair, which is looser than a gap-only test.

### Data

- Inflate reader: no test for a stored block after a non-aligned block; output size is unbounded; incomplete Huffman tables are accepted. The feed is trusted and fuzzing showed it is correct.
- Feed timestamps: an unreadable one drops the payload, a 31 February is accepted, and a few merge-path tests are missing.
- Race-control flags are walked in line order while sector flags are sorted by time; sort once in the build.
- The fixture trimming script's equality check covers merged JSON only; note it in the README.
- Reading a car's position at a time can overflow on remote, bad data; the countdown formatting uses a plain integer format.
- JSON doc wording misses the −0 sign; the panel frame key must not contain dots (document it).
- The archive session drops index entries that lack a key or start, and lap counts are only read for sessions typed "Race".
- Qualifying coverage on the committed test data is thin (no line crossings in the qualifying sample); the tower test does not cut Position after the picture time; shared formatting could move into one place; an empty three-letter code and tuple fields' hand-written equality are untidy.
- Car data: an old whole file reused for a now-finished session could be short (beta only); two downloads can race; cleanup timing; the per-tick reuse and repeated notice; a server that ignores byte ranges re-downloads 8 MB a minute.

## After the final review (build 16)

- Ruling: one round of fixes only, as for beta.2. What the check of that round found was small and is left as is: a step back (even −1 s) blanks the console, deck and pit circle for about a second; the console area is blank instead of "Tap a car to pick an onboard" while a session loads; a paused map may keep old car positions until play or a seek; one test's comment sits above the wrong test; each live rebuild still copies the cars' histories once (cheap, not measured on the phone); finding a live map's start/finish line is not measured; the "before the join" check never goes from shown to hidden in its test; the live rebuild speed-up was measured on the owner's full-race recording, which stays out of the repo — cost if wrong: a polish build.
- Not fixed: after a reconnect, a lap count that rose while disconnected can count as a line crossing at the reconnect (it needs a marker through the live data and a decision on lap windows).

## If build 15 or 16 doesn't compile

Nothing here could be compiled on Apple's tools before the owner's build (build 14 was the last: no warnings). Places to look first, from the reviews:

- Map and pit circle gestures: a long press followed by a drag (`LongPressGesture.sequenced(before:)` with `.second(true, let drag?)`), and state changed from a `Task` when the gesture ends (MapPanel, PitCircleView).
- MapPanel: `.task(id:)` on a private nested type with a `UUID` id; `TimelineView(.animation(minimumInterval: 1.0 / 30, paused:))`.
- PitCircleView: the Canvas calling a nonisolated drawing type; the `else if timing.timingHidden { Color.clear }` branch.
- RootView: `onChange(of:initial:)` with a private nested Equatable type.
- PlayerView and MultiviewView: `NextLivePrompt` with `.animation(value:)` on an optional id.
- LiveConnection: `NWPathMonitor` inside an actor (`#if canImport(Network)`); `URLSessionWebSocketTask` (`maximumMessageSize`, `@unknown default`); a cookie built from response headers; the 15 s linger task.
- AppModel: `guard let (offer, inMultiview) = nextLive.accept()`.
- TowerView: an `if`/`else` inside a `switch` case; ScrubDeck: `.overlay(alignment:)` with `if let` and an `else if …, let` branch, and `Theme.surface.opacity(0.9)` (check `Theme.surface` is a `Color`).
- DataRegionViews: `TimingQuietLine` (Theme colours, `.minimumScaleFactor`, `.allowsHitTesting(false)`); `LaptopTimingNote.text(_:loading:)` with a default that names a static of the same type.
- RaceEngineerConsole: the new `placeholder` property and reading `timing.consoleCar`.
- `LiveEvent.link` gained a third value: any `case .link` match in a view would need it (none found).
- CircuitLoader: `TrackMap`'s memberwise init in `withStartFinish`.
- XcodeGen: run `xcodegen generate` after pulling; build 15 added five files in DuoApp/Timing.
