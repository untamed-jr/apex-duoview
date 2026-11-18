# Apex DuoView: Las Vegas Grand Prix weekend test plan (Nov 19-22, 2026)

This plan covers the checks marked "Live" on the beta 3 checklist (`beta3-test-checklist.html`). They only work while a real session is on in your F1 TV app, so each one is given to a session below. There are 18 in all.

## Schedule

Las Vegas time is PST (UTC-8). Note that the late sessions fall on the next calendar day in UTC.

| Session | Las Vegas time (PST) | UTC |
|---|---|---|
| FP1 | Thu 19 Nov, 16:30-17:30 | Fri 20 Nov, 00:30-01:30 |
| FP2 | Thu 19 Nov, 20:00-21:00 | Fri 20 Nov, 04:00-05:00 |
| FP3 | Fri 20 Nov, 16:30-17:30 | Sat 21 Nov, 00:30-01:30 |
| Qualifying | Fri 20 Nov, 20:00-21:00 | Sat 21 Nov, 04:00-05:00 |
| Race (50 laps) | Sat 21 Nov, 20:00 | Sun 22 Nov, 04:00 |

- This is **not** a sprint weekend: three practice sessions, qualifying and the race.
- F1 TV pre- and post-session shows: **I could not confirm any times.** Look in the "Race Weekend" tab or the F1 TV schedule on the day. Where a check below needs a show, it says what to do if there is none.
- "Nov 19-22" on the checklist is the weekend in UTC. In Las Vegas the race is on the evening of Saturday 21 Nov.
- Session times can change. Check the official F1 schedule before each session.
- Sources: official F1 page https://www.formula1.com/en/latest/article/formula-1-heineken-las-vegas-grand-prix-2026.1qmWzcBwKK5hkTbYbhVC22 and GPBlog https://www.gpblog.com/en/news/formula-1-las-vegas-gp-2026-all-session-times-and-full-weekend-schedule (found by web search; the pages themselves could not be opened from the build machine, so the times come from search summaries).

**Real iPhone Duo checks can be done in any session.**

## Before every session

- Mac and simulator on Wi-Fi (the phone too, except for the mobile data check).
- If there was a fix since last time: pull the code, regenerate the project, build with zero warnings, and run it (checklist group "Get it running"). Settings > About should say build 16.
- Open the checklist page and the notes ready to write in.
- Leave the simulator fold set to Flat unless a check says otherwise.

## FP1 (Thu 16:30 PST): connection and basics (5 checks)

Before it starts: pull and build if there was a fix; Wi-Fi on; be in the app 5 minutes early so you can join near the start.

1. **b15-connect — Live timing connects and follows the picture (T-C).** Why: nothing else works if live timing does not connect, so it goes first.
2. **live-basics — Live basics from beta 2.** Why: the LIVE badge, "Watch live" and the layouts are the base of every live check.
3. **b15-drop — A dropped connection says so and recovers cleanly.** Why: needs live timing already showing; turn Wi-Fi off on the Mac for about 10 seconds.
4. **b15-key — A live race shows its timing, not "No timing for this session".** Why: a quick look that costs nothing; repeat it in every session you watch live and write the session name if it fails.
5. **b15-keepfile — Keep one live recording file for the tests.** Why: do this last, at the end of FP1, while the simulator is still running.

## FP2 (Thu 20:00 PST): joining late (4 checks)

Before it starts: Wi-Fi on. Before FP2 begins (by about 18:30, within an hour of FP1 ending), open the FP1 replay for the first check below. Then **do not join FP2 until at least 15 minutes after it starts** (20:15 or later).

1. **b12-growing — A replay watched soon after a session keeps getting speed data.** Why: it needs a session that has just finished, and FP1 has. Check again later in the weekend that the speed shows to the end.
2. **b15-catchup — Joining late: "Timing catching up" until F1's archive fills in.** Why: it needs a join 15 or more minutes after the start. Note how long after the session the label went.
3. **b16-hidden — Rewinding before you joined shows nothing from later.** Why: same late join, so do it straight after the previous check.
4. **b15-return — Coming back to a live session after a break.** Why: watch 5 minutes, close, wait 5 minutes, reopen; it fits in the middle of the hour.

## FP3 (Fri 16:30 PST): connection handover and phone (3 checks)

Before it starts: Wi-Fi on for the Mac. Have the phone ready for the mobile data check.

1. **b16-keepconn — Single feed to multiview keeps live timing.** Why: needs a session that started 10 or more minutes ago, so start about 16:45.
2. **b15-mobile — Live speed readouts on mobile data with the switch off.** Why: phone only. Turn Wi-Fi off on the phone, open a car's onboard, then turn Wi-Fi back on.
3. **b15-resumelive — Resuming a live bookmark: live while F1 TV lists it, a replay after.** Why: watch live, tap "Resume" while FP3 is on, then tap "Resume" again after FP3 has ended (after 17:30) and check it opens as a replay.

## Qualifying (Fri 20:00 PST): rewind and "next live" (3 checks)

Before it starts: Wi-Fi on. Be ready from about 19:30 for the first checks if a pre-qualifying show is listed.

1. **b15-rewind — Rewinding a live session shows what was followed.** Why: watch live for 20 or more minutes from near the start, then rewind 10 and 15 minutes, close and reopen.
2. **b15-nextlive — The next live programme prompt.** Why: needs a programme going live while you watch another. Best: watch the pre-qualifying show (if there is one) as qualifying starts, or watch qualifying near its end. If there is no show, say so in the note.
3. **b15-nextpip — The next live prompt never shows in picture in picture.** Why: same set-up as the previous check; go to the home screen while the other programme goes live, then come back.

## Race (Sat 20:00 PST): race-only checks (3 checks)

Before it starts: pull and build if there was a fix; Wi-Fi on; Activity Monitor open on the Mac (or the phone in hand to feel how warm it gets).

1. **live-pitmsg — Late join: "The pit circle appears when the leader next crosses the line."** Why: join after lap 1 and switch the fold to laptop to see the console message.
2. **b15-livecircle — The pit circle on a live race after a late join.** Why: same late join; the circle shows after the leader's next crossing. Do it straight after the previous check.
3. **b16-warm — Late in a live race: smooth and not hot.** Why: from about lap 40, watch 10 minutes with the map, tower and pit circle open and compare the CPU with early in the race.

## After each session

- Open the checklist page and mark each check you did: pass, or a problem.
- Add a note with the time something happened (Las Vegas time and the session name), for example "FP2, 20:42: label went away".
- Write anything odd you saw even if the check passed.

## If something breaks

- Write down the session and the time it happened.
- Keep the app open and do not close or delete it; the recording is kept inside it.
- Copy the recording file as in **b15-keepfile**: on the Mac, open Terminal and run `open "$(xcrun simctl get_app_container booted <your bundle ID> data)/Library/Caches/live"` (your own bundle ID is in `Config/Signing.local.xcconfig`), then copy that session's `.txt` file somewhere safe.
- Send it to Claude with the note.

## Counts

FP1 5, FP2 4, FP3 3, Qualifying 3, Race 3. Total 18.
