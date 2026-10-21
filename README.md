# Notch Island

A Dynamic Island for the MacBook notch. It holds your files while you move them, shows what's playing, and gives you a heads-up when you plug in or a meeting is about to start. Native AppKit, no dependencies.

## Features

- **Shelf.** Drag files toward the notch and drop them. Later, drag them out anywhere: Finder moves them on the same disk and ⌥ copies. "Drag all" takes the whole stack.
- **AirDrop and more.** While you drag a file in, drop it on **AirDrop** to send it straight away. Right-click a shelf file (or use **⋯** for all of them) to AirDrop, share, compress, copy its path or show it in Finder.
- **Downloads.** Safari and Chrome downloads show a progress ring beside the notch, and finished files land on the shelf.
- **Now playing.** Works with any app that reports to macOS (Spotify, Music, browsers): artwork, progress, play/pause, skip and seek. Swipe two fingers across the open island to skip; scroll over the progress bar to scrub.
- **Meetings.** Your next meeting (from any calendar on your Mac, including Google), a heads-up 5 minutes before, and a **Join** button for Meet, Zoom and Teams calls. Declined meetings are skipped.
- **Focus timer.** Right-click → Start Focus Timer for 25 minutes of focus and a 5-minute break, counting down beside the notch.
- **At a glance.** "Charging" when you plug in; the open island shows network speed and battery.
- **A tiny robot.** It lives around the notch on magnet boots: it walks the menu bar, climbs the notch's walls, hangs underneath, sits and dozes. It sleeps when nothing's going on, dances to music, rides the progress bar when the island is open, types at a desk during focus time, waves when your cursor comes near, gets sluggish on low battery, and wears a seasonal hat.

Hover over the notch to open it. Right-click the open island for the focus timer, **Settings** (open at login, and switching the robot, meetings or network speed off) and Quit.

## Requirements

- macOS 14 or later
- A MacBook with a notch. Every other display (or the only one, with the lid closed) gets its own island, a notch-sized pill at the top centre
- Xcode's Command Line Tools (`xcode-select --install`); full Xcode isn't needed

## Build

```sh
./build.sh        # builds build/NotchIsland.app
./build.sh run    # builds, then (re)launches it
```

On first launch Notch Island asks for calendar access, which it uses to show your next meeting.

## How now playing works

Since macOS 15.4, the system's MediaRemote framework only answers Apple-signed processes. Notch Island runs `/usr/bin/perl` (Apple-signed), which loads Notch Island's own small helper library, [`Sources/NowPlayingHelper`](Sources/NowPlayingHelper). The helper streams now-playing updates as JSON lines and takes play/pause/skip/seek commands. The approach comes from [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter); Notch Island's helper is written from scratch.

If a future macOS removes perl or closes this gap, now playing disappears and everything else keeps working.

## Project layout

```
Sources/NotchIsland/        the app
  main.swift                entry point
  Hub.swift                 shared state, and one island per display
  IslandController.swift    one display's island: states, sizes, mouse and drag handling
  ExpandedView.swift        the open island: player, header, shelf
  Mascot.swift              the pixel robot and its behaviour
  ShelfActions.swift        AirDrop, share, compress and other shelf actions
  Downloads.swift           browser download progress
  Focus.swift               the focus timer
  Settings.swift            preferences and the Settings window
  Views.swift               small reusable views
  Helpers.swift             layout, animation and shape helpers
  NowPlaying.swift          now-playing client and smoothing
  SystemInfo.swift          battery, calendar, network speed
Sources/NowPlayingHelper/   MediaRemote helper loaded by perl
Resources/Info.plist
build.sh                    SwiftPM build + .app bundling
```

`NotchIsland --snapshot <dir>` renders every island state to PNGs, which is handy for checking layout changes.

## License

Not chosen yet.
