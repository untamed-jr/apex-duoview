# Beta.4 — decisions made while building, and what was left for later

Kept from the build ledger (2026-11-18 to 2026-11-21) and the plan, so nothing decided on the owner's behalf is lost. Each line says what it costs if wrong.

## Rulings from the plan (Global Constraints and Task 2)

Clocks

- Ruling: picture time decides what a viewer may see: a radio clip, card, haptic, tick or transcript exists only once the picture has reached it; "Show the whole race" shows every clip — cost if wrong: a spoiler, or a missing clip.
- Ruling: wall-clock time (not picture time) spaces the buzzes: at most one haptic every 2 s — cost if wrong: buzzes feel too close or too far apart.
- Ruling: picture time (not wall time) spaces the yellow flag: at most one yellow haptic per 60 s of picture time — cost if wrong: yellow nags in a busy session, or a real yellow is skipped.
- Ruling: after a seek or a scrub, nothing fires for 2 s of picture time; a backward step, a step over 10 s, or the first step only sets the baseline (a backward step under 500 ms is a normal step, see the ledger rulings) — cost if wrong: an event at the exact edge of a rewind is lost or repeated.
- Ruling: transcription may run up to 2 minutes ahead of picture time, but its text shows only when its clip does — cost if wrong: text a moment late, or a spoiler if the gate is wrong.
- Ruling: the "Back to where you were" chip lasts 15 s; the jump goes to 5 s before the event (3, 5, 10 or 15 s in Settings) — cost if wrong: one number.
- Ruling: the Gap Thermometer refreshes twice a second — cost if wrong: battery use, or a jumpy bar.
- Ruling: the hinge mixer smooths each reading by a factor of 0.3, ignores changes under 5° (dead zone) and shows its bar for 2 s — cost if wrong: a steppy or sluggish mix.
- Ruling: the hinge mixer's ends are 70° (all radio) and 160° (all commentary), a straight line between — cost if wrong: where the mix feels right on the real Duo.

Priority

- Ruling: when two haptics come close, the stronger waits for its turn and the weaker is dropped; the order is red flag, safety car, virtual safety car, chequered, yellow, your driver's pit stop, purple sector — cost if wrong: a weaker feel may be lost.
- Ruling: radio, "out" and "passed" events make cards but no haptic — cost if wrong: one missing feel.

Dead zone and clip sound

- Ruling: while a clip plays, the feeds are silent (the Android app's way) unless the hinge mixer is on — cost if wrong: the commentary stays audible under a clip, or goes silent when you wanted it.
- Ruling: the gap colour is cool blue at 3 s or more, amber at 2 s and red at 1 s or less — cost if wrong: where the colour turns.

Pit-cycle passes

- Ruling: "{CODE} passes {CODE2} for P4" is shown only for a one-place change between your driver and the car they swapped with, and neither car may be in the pit lane at either end of the step; bigger changes (pit cycles, retirements) give no card — cost if wrong: a missing overtake card, or a false one after a stop.

Lap-label formats

- Ruling: a lap reads "Lap n"; before lights out "Before the start"; after the flag "After the flag"; qualifying "Q2 · 8:12 left" ("Qualifying" with no part, "Q2" with no time left); practice "m:ss", or "h:mm:ss" from an hour; an unknown lap shows no label — cost if wrong: a label.
- Ruling: the Radio list shows a header whenever a row's label differs from the row above, so lapped drivers can repeat a header (the driver's own lap, as on Android) — cost if wrong: a repeated header.
- Ruling: track events carry the leader's lap, car events that car's lap (count plus 1); both are blank outside races and before lights out, so the pre-race yellows read "Yellow flag", not "Lap 1" — cost if wrong: a wrong lap on a card.

Card groups

- Ruling: Settings › Closed phone › "Event cards" has four groups: "Flags", "My driver's stops and radio", "My driver's position changes", "Chequered flag"; older cards stack ("+2") — cost if wrong: how the switches are grouped.
- Ruling: radio cards and haptics for "your driver" need a driver picked (Settings › Multiview › My driver); the Radio Scanner's and Rivals' drivers also count for radio events — cost if wrong: a viewer with no driver picked sees fewer cards.

Other plan rulings

- Ruling: the closed layout applies wherever the multiview's is used (narrower than 600 pt, or posture closed), so also on any iPhone in portrait; the outer screen's measured size (466 × 678 pt) is for mockups, never hard-coded — cost if wrong: a closed page looks odd on a different screen.
- Ruling: clips download from F1 without the F1 TV sign-in first, and only on a refusal once more with it, to that address only; a refusal never signs you out; clips are kept 7 days — cost if wrong: an extra download, or a clip that needs the token.
- Ruling: the hinge mixer, the feel of haptics, the outer screen and a real unfold are checked on the Duo in this beta, not left to beta.7 — cost if wrong: a later round of changes.

## Rulings from the build ledger

Before the weekend freeze (Tasks 0 to 7)

- Ruling: weekend freeze — Tasks 1–7 (DuoCore and the spike script, additive only, no change to the app) merge before the Las Vegas race; Tasks 8–14 merge only after Sunday 22 Nov, because the owner wants build 16 stable for the weekend — cost if wrong: beta 4 lands a few days later.
- Ruling: Tasks 3, 4 and 7 run in parallel in isolated worktrees (the owner asked for parallel work; they touch different files) — cost if wrong: a merge conflict at cherry-pick time.
- Ruling: for a car with no lap count after the start, keep "Lap 1", but only while no car has a count of 2 or more at the clip's time; after that the car reads as unknown (F1 sends no count during lap 1, so Android's blank is a data gap; the refinement stops a lap-1 retiree reading "Lap 1" all race) — cost if wrong: one label on a few clips.
- Ruling: fix the radio probe's two small faults now (a printed save path in a "shareable" report, and one network error stopping the whole probe) — the first breaks the privacy rule for text the owner pastes back, the second defeats a one-shot weekend probe — cost if wrong: one small extra round.
- Ruling: the merged groundwork code is the authority over the plan's "expected" queue names, and timeouts skip a clip but don't count toward the three-failure wait (Android parity, checked by the reviewer) — cost if wrong: test names differ from the plan.
- Ruling: for the gap pair, a car that is out counts before a car in the pits for both cars, with the copy "{CODE} is out — swipe for another pair" — cost if wrong: one ordering line.
- Ruling: a held hinge end (exactly 160° or 70°) must reach the end levels; 0.94 at a held end would be visible — cost if wrong: one small change.
- Ruling: a duplicate race-control line is the same time and the same text, first kept; there is no beta.3 duplicate code to match (checked by search) — cost if wrong: a repeated line in the logbook.
- Ruling: Task 6 starts before Task 2's review clears, because it only uses the haptic kinds — cost if wrong: a rebase onto a fixed Task 2.
- Ruling: one fix wave runs now, before the weekend, on DuoCore, the spike script and the plan only, so build 16 is untouched — cost if wrong: none to build 16.
- Ruling: a race-control entry gains the raw F1 category and flag, because the logbook needs a blue-flag filter and text matching is brittle — cost if wrong: two unused optional fields.
- Ruling: a gap pair of a car with itself gives no reading rather than "before the first lap" (misleading copy) — cost if wrong: one case.
- Ruling: a backward step under 500 ms is a normal step, not a seek, because live picture-time jitter must not drop 2 s of events — cost if wrong: an event at the exact rewind edge.

After the freeze (Tasks 8 to 14)

- Ruling: the owner moved Tasks 8–14 to now ("start beta 4 now if it won't affect the race weekend"); the phone isn't rebuilt from main until after the race — cost if wrong: none to the race build.
- Ruling: Tasks 8 and 9 run in parallel in isolated worktrees (as Tasks 3, 4 and 7; different DuoCore files) — cost if wrong: a merge conflict at cherry-pick.
- Ruling: app tasks (10 and later) are checked by a syntax check here and by the owner's build check on the Mac after each, since this container has no iOS compiler — cost if wrong: build errors land on main between Mac builds.
- Ruling: the app offers the book layouts Logbook and Rivals from Task 9 on, drawn blank until Task 14 (they had to be drawn before any phone install, and are) — cost if wrong: two blank layouts in the simulator meanwhile.
- Ruling: three gaps from the build 17 review enter its fix round: live radio counts as a timing reader, a time-jump notice in normal play counts as a seek only when the time moved more than a second, and the clip's pan goes through a submixer before the speed control — cost if wrong: a slightly bigger round.
- Ruling: the new copy "Show team radio", "Choose a driver" and the Settings footer stand, as needed labels the spec doesn't fix — cost if wrong: three strings to reword.
- Ruling: the speech calls (`SFSpeech*`) sit behind one or two helpers, so a likely iOS 27 deprecation is a one-place fix after the Mac build — cost if wrong: a few extra lines.
- Ruling: the footer the build 19 implementer invented in Settings › Closed phone is dropped (copy comes verbatim from the spec) — cost if wrong: one line the owner may want back.
- Ruling: closed → unknown posture no longer counts as an unfold (a jump the viewer didn't ask for), and "Gaps start after the first lap." no longer shows when there is no picture time — cost if wrong: two tiny changes. (Build 22 later made closed → unknown → book or flat count as an unfold again.)
- Ruling: Task 14's mixer is clips only until owner check T-R1 says whether the radio track is continuous — cost if wrong: a continuous-radio crossfade comes in a later build.
- Ruling: the hinge mixer works in multiview only in build 21 (the single-feed player isn't in Task 14's files); the single player keeps silencing the feeds under a clip; revisit after T-R1 — cost if wrong: the single player in book pose has no mixer.
- Ruling: leaving Rivals keeps its two onboards at the front of the feeds and remembers them as the last used; undoing would restart replaced feeds — cost if wrong: the viewer re-picks feeds after Rivals.
- Ruling: the Logbook's stale model after a rewind (it briefly showed Stops and Race control past the picture time) and the mixer bar sitting on the fold are fixed in round 1, because the picture-time and fold rules are binding — cost if wrong: two small changes.

Final fix wave (build 22)

- Ruling: the "Transcribe a test clip" probe stays in build 22 and is removed in a separate commit after the owner runs it on the Duo (O4, O7), because the reviewer showed it is the only way to read them (the plan had it removed in build 22) — cost if wrong: one extra small commit, and a debug row in the beta.4 build.
- Ruling: a clip does not move ears when headphones go in or out; it ends and the next clip plays in its ear (or centred), because the spec doesn't pin "at once"; the code was left alone and the doc and CHANGELOG corrected — cost if wrong: a clip ends on a headphones change instead of moving ears.

## Left for later (from the final review)

Open choices for the owner

- The Radio panel's "Driver" chip label: keep "Driver" or change it.
- "Hinge mixer" shows twice in Settings (both are the spec's strings).
- The Logbook's empty state gives nothing to tap (a design change).
- Race Engineer's radio spot (122 pt) overflows when a notice line shows (rare: three clips plus a failed load); judge it on the phone.

Not fixed in build 22

- A kept Unfold to See card has no timeout: if the hinge sits part-open with an unknown posture for a long time and then opens, the jump goes to that older card. Any known posture clears it.
- After a tap-jump, old events can come back, and the "Back to where you were" chip can be overwritten (closed layout only).
- Rivals' pair is taken before a picture time exists (`placeRivals` logic; too risky to change uncompiled).
- The Radio Scanner ignores a hidden timing: its clips are right, only the swipe order may be stale.
- "Getting the speech model ready…" can show a long time if the model never installs; it recovers once a retry works.
- A live multiview feed that F1 TV keeps refusing for a real reason (HDCP, for example) costs one extra PLAY and licence a minute while it sits in a slot.
- Leaving picture in picture for one feed needs the others lined up again; the order of stopping and restoring picture in picture when the same feed is picked needs the phone to judge.
- The welcome tour's card pictures are placeholders until the screenshots are taken after the race.
- The lock-screen entry has no title (as in beta.3).
- A radio clip keeps playing while the video is paused (the reviewer graded it acceptable).
- A stall's end can read as a seek in the time-jump check (nothing fires early; live check T-C4).
- A queued haptic that was switched off still uses up its 2 s slot (harmless).
- Yellow's haptic plays again after an Unfold to See jump back to t − 5 s; this matches "haptics follow the picture", and the owner confirms the feel.

How the work was organised (parallel builds, review rounds) isn't listed; it changed no behaviour.
