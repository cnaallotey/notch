# Notch

An interactive, Dynamic-Island-style notch for macOS 13 Ventura and later. It works on MacBooks
with a hardware notch, and draws a matching virtual notch on Macs and displays without one.

## Features

- **Hover or click to expand.** The notch springs open with a haptic tap and closes when the pointer leaves.
- **Now Playing.** Shows artwork, title, artist and a seekable progress bar, with previous, play/pause and
  next controls. Works with Music, Spotify, browsers and anything else that reports to Now Playing.
  Click the artwork to jump to the source app.
- **Live activities.** While music plays, the closed notch shows the artwork and animated bars tinted
  to match the album. Plugging in or unplugging the charger, and adding files to the shelf, also flash briefly.
- **Calendar.** A week strip with dots on busy days. Tap a day to see its events, in your calendar colours.
  Today hides events that have already ended, and a meeting in progress is highlighted. A **Join** button
  appears for Zoom, Meet, Teams, Webex, Whereby and FaceTime links. Click an event to open Calendar.
  The first time, click **Show my events** to grant access.
- **File shelf.** Drag files onto the notch to park them, then drag them back out into any app.
  Double-click to open, right-click for Show in Finder or AirDrop, or AirDrop everything at once.
- **Header bar.** Battery level and charging state, the clock, and a settings menu.
- **Menu bar icon.** Open the notch, toggle settings, set Launch at Login, or quit.

## Build & run

You only need the Xcode Command Line Tools (`xcode-select --install`).

```bash
scripts/build.sh --run
```

This produces a universal (Apple Silicon + Intel) `build/Notch.app`. Copy it to `/Applications` to keep it,
which **Launch at Login** also needs. A release build takes a few minutes; for quick iteration use:

```bash
DEBUG=1 scripts/build.sh --run
```

> `swift build` currently fails with the Command Line Tools alone (an `xcrun PlatformPath` error), so the
> script calls `swiftc` directly. `Package.swift` is kept so the project opens in Xcode.

## Notes

- Now Playing uses Apple's private `MediaRemote` framework. It works on macOS 13 and 14. Apple restricted
  it for third-party apps in macOS 15.4, so media info may not appear on newer systems.
- The shelf stores references to your files, not copies. A file that is moved or deleted drops off the shelf.
- On a Mac without a notch, the virtual notch sits on the built-in display (or the main display if the lid
  is closed) and matches the menu bar's height.

## Layout

```
Sources/Notch/
  main.swift                 app entry (accessory app, no Dock icon)
  App/                       AppDelegate, NotchPanel (window), NotchController (hover + layout), NotchViewModel
  Services/                  MediaController, BatteryMonitor, ShelfStore, LoginItem
  Views/                     NotchView, NotchShape, HeaderView, HomeView, ShelfView, LiveActivityView
```
