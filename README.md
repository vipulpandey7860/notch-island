# Notch Island

A Dynamic Island for the MacBook notch. It keeps today's tasks and a scratch note, holds your files and what you copy, shows what's playing and what your coding agents are up to, and gives you a heads-up when a task is due, a timer rings, Claude Code needs your OK, you plug in or a meeting is about to start. Native AppKit, no dependencies, free and open source.

If it's useful to you, you can [sponsor it on GitHub](https://github.com/sponsors/vipulpandey7860).

## Features

- **Tasks.** Today's to-do list sits in the open island. Type the way you'd say it: "call mom tomorrow at 5pm" lands on tomorrow's list with a 5 PM reminder, and the line above the box shows what will be saved before you press ↩. Tick a circle to finish a task, double-click to edit it, or use **⋯** to set a reminder, move it to another day or delete it. ‹ › looks at other days. Unfinished tasks carry over to today until they're done; a missed reminder shows as overdue.
- **Due alerts.** When a task's time comes, the notch drops down with a chime and the robot waving: **5 min** snoozes it, **Done** ticks it off. Nothing goes to Notification Center or iCloud.
- **Notepad.** One note per day that saves as you type. ⌘↩ turns the line you're on into a task (a day or time in it works as above).
- **⌥N** from any app opens the island with the cursor in the task box. The app you were in stays in front, and Esc or a click elsewhere hands the keyboard back.
- **Timers.** Type "tea 4 min" (or "timer 90s", "pasta for 12 minutes") in the task box and press ↩. The countdown sits beside the notch, and when it's up the notch drops down with **+1 min** and **Done**. ("call mom in 20 min" is still a task with a reminder.)
- **Coding agents.** Connect Claude Code and Codex in Settings. While Claude Code works, the project and how long it's been at it sit beside the notch and the robot types at its desk. When it wants to run something, the notch shows what with **Allow**, **Deny** and **In terminal**; long turns end with a "Claude finished" heads-up. Codex says when it finishes a turn. They reach the app through a socket only you can open; if Notch Island isn't running, they carry on exactly as before.
- **Clips.** What you copy and the screenshots you take collect in the notepad card's **Clips** tab: click one to copy it again, or drag it out. It's kept in memory only, and anything password managers mark as secret is never kept.
- **Shelf.** Drag files toward the notch and drop them. Later, drag them out anywhere: Finder moves them on the same disk and ⌥ copies. "Drag all" takes the whole stack.
- **AirDrop and more.** While you drag a file in, drop it on **AirDrop** to send it straight away. Right-click a shelf file (or use **⋯** for all of them) to AirDrop, share, compress, copy its path or show it in Finder.
- **Downloads.** Safari and Chrome downloads show a progress ring beside the notch, and finished files land on the shelf.
- **Now playing.** Works with any app that reports to macOS (Spotify, Music, browsers): artwork, progress, play/pause, skip and seek. Swipe two fingers across the open island to skip; scroll over the progress bar to scrub.
- **Meetings.** Your next meeting (from any calendar on your Mac, including Google), a heads-up 5 minutes before, and a **Join** button for Meet, Zoom and Teams calls. Declined meetings are skipped.
- **Focus timer.** Right-click → Start Focus Timer for 25 minutes of focus and a 5-minute break (both lengths are in Settings), counting down beside the notch.
- **At a glance.** "Charging" when you plug in; the open island shows network speed and battery.
- **A tiny robot.** It lives around the notch on magnet boots: it walks the menu bar, climbs the notch's walls, hangs underneath, sits and dozes. It sleeps when nothing's going on, dances to music, rides the progress bar when the island is open, types at a desk during focus time, waves when your cursor comes near, gets sluggish on low battery, and wears a seasonal hat.

Hover over the notch (or press ⌥N) to open it. Right-click the open island for the focus timer, **Settings** (open at login, the switches, focus lengths, coding agents), **Check for Updates…** and Quit.

Tasks and notes stay on your Mac, as plain files in `~/Library/Application Support/Notch Island`: `tasks.json`, and `Notes/` with one text file per day.

## Install

1. Download `NotchIsland-<version>.zip` from the [latest release](https://github.com/vipulpandey7860/notch-island/releases/latest), unzip it, and move **NotchIsland.app** to Applications.
2. Open it. Notch Island isn't notarized by Apple (that needs a paid developer account), so the first time macOS says it can't check it. Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to Notch Island. Or, in Terminal: `xattr -dr com.apple.quarantine /Applications/NotchIsland.app`
3. It asks for calendar access, which it uses to show your next meeting.

You only do this once. After that Notch Island checks for updates once a day (you can turn that off in Settings), shows what's new, and **Install and Relaunch** updates it in place. Each update is checked against the release key before it's installed, so only releases published from this repo get in.

Needs macOS 14 or later. It's made for MacBooks with a notch; every other display (or the only one, with the lid closed) gets its own island, a notch-sized pill at the top centre.

## Build it yourself

Needs Xcode's Command Line Tools (`xcode-select --install`); full Xcode isn't needed. The app lives in `apps/mac`:

```sh
cd apps/mac
./build.sh        # builds build/NotchIsland.app
./build.sh run    # builds, then (re)launches it
.build/release/NotchIsland --selftest   # checks dates, timers, rollover, reminders, agent hooks and update signatures
```

## Releasing

```sh
cd apps/mac
./release.sh --setup              # once: your update signing key (in your login keychain) and signing certificate
./release.sh 0.2.0 [NOTES.md]     # builds, signs and zips the app, tags the commit, publishes the GitHub release
```

`--setup` puts the public half of the update key into `apps/mac/Resources/Info.plist`; commit it. Back up the secret half (`security find-generic-password -s "Notch Island update key" -w`): without it, copies already out there won't accept your updates. The certificate is self-signed, so it doesn't stop macOS's first-launch warning, but every release is signed the same way and keeps its permissions, like calendar access, across updates. Needs the [GitHub CLI](https://cli.github.com).

## How now playing works

Since macOS 15.4, the system's MediaRemote framework only answers Apple-signed processes. Notch Island runs `/usr/bin/perl` (Apple-signed), which loads Notch Island's own small helper library, [`apps/mac/Sources/NowPlayingHelper`](apps/mac/Sources/NowPlayingHelper). The helper streams now-playing updates as JSON lines and takes play/pause/skip/seek commands. The approach comes from [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter); Notch Island's helper is written from scratch.

If a future macOS removes perl or closes this gap, now playing disappears and everything else keeps working.

## Project layout

```
apps/mac/                   the Mac app; everything below is inside it
Sources/NotchIsland/        the app
  main.swift                entry point
  Hub.swift                 shared state, and one island per display
  IslandController.swift    one display's island: states, sizes, mouse and drag handling
  ExpandedView.swift        the open island: header, cards (tasks, notepad, player), shelf
  Planner.swift             tasks and daily notes, saving them, reading dates and timers out of text
  PlannerViews.swift        the tasks and notepad cards, and the heads-up that asks for an answer
  Agents.swift              Claude Code and Codex: the socket, what they're doing, connecting them
  Clips.swift               clipboard history and screenshots, and the Clips tab
  Updater.swift             checking GitHub Releases, verifying and installing updates
  Mascot.swift              the pixel robot and its behaviour
  ShelfActions.swift        AirDrop, share, compress and other shelf actions
  Downloads.swift           browser download progress
  Focus.swift               the focus timer and typed timers
  Settings.swift            preferences and the Settings window
  Views.swift               small reusable views
  Helpers.swift             layout, animation and shape helpers
  NowPlaying.swift          now-playing client and smoothing
  SystemInfo.swift          battery, calendar, network speed
Sources/NowPlayingHelper/   MediaRemote helper loaded by perl
Resources/Info.plist
build.sh                    SwiftPM build + .app bundling
release.sh                  signing key setup, and publishing a release
```

`NotchIsland --snapshot <dir>` renders every island state to PNGs, which is handy for checking layout changes.

## License

[GPL-3.0](LICENSE). You can use, change and share Notch Island; anything you build from it has to stay open source too.
