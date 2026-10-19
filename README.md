# Notch Island

A Dynamic Island for the MacBook notch. It holds your files while you move them, shows what's playing, and gives you a heads-up when you plug in or a meeting is about to start. Native AppKit, no dependencies.

## Features

- **Shelf.** Drag files toward the notch and drop them. Later, drag them out anywhere: Finder moves them on the same disk and ⌥ copies. "Drag all" takes the whole stack.
- **Now playing.** Works with any app that reports to macOS (Spotify, Music, browsers): artwork, progress, play/pause, skip and seek.
- **Heads-ups.** "Charging" when you plug in, and your next meeting 5 minutes before it starts.
- **At a glance.** The open island shows your next meeting, network speed and battery.
- **A tiny robot.** It lives around the notch on magnet boots: it walks the menu bar, climbs the notch's walls, hangs underneath, sits and dozes. It bobs to your music, watches files you drag, hops when you plug in, and yawns before meetings. With nothing going on it sleeps; with music it dances. Open the island and it rides the progress bar along with the song. Turn it off with right-click → Show Mascot.

Hover over the notch to open it. Right-click the open island to quit.

## Requirements

- macOS 14 or later
- A MacBook with a notch (other displays get a basic pill for now)
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
  IslandController.swift    island states, sizes, mouse and drag handling
  ExpandedView.swift        the open island: player, header, shelf
  Mascot.swift              the pixel robot and its behaviour
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
