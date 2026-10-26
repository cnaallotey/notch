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
- **Widgets.** Weather for where you are (current temperature, conditions and today's high and low, from
  Open-Meteo), a countdown timer with quick presets, and live CPU, memory and disk usage. While a timer runs
  the closed notch shows the time left, and it chimes when it's done. The first time, click
  **Show local weather** to grant location access.
- **iOS-style notification alerts.** Notifications from other apps (Messages, Mail, Slack, Calendar…) and
  Focus changes drop out of the notch as a banner with the app's icon, title and message. Click one to open
  the app; rest the pointer on it to keep it up. Turn it off with **Show App Notifications** in settings.
  macOS still shows its own banner too; to see only Notch's, set an app's alert style to **None** in
  System Settings › Notifications (keep "Show in Notification Centre" on).
- **Notices.** The closed notch briefly shows when AirPods or other Bluetooth devices connect or disconnect,
  when the battery drops to 20% and 10%, and five minutes before a calendar event starts.
- **Quick toggles.** On the Controls tab: Keep Awake (stops the display sleeping), Dark Mode, mute the
  microphone, hide desktop icons (relaunches Finder), take a screenshot, and turn the display off. Dark Mode
  asks for permission to control System Events the first time.
- **Display brightness.** Also on the Controls tab, a slider for every connected display, built-in and mirrored ones included, using
  software dimming (inspired by MonitorControl Lite). Regular displays are dimmed through their gamma table;
  AirPlay, Sidecar and DisplayLink screens get a click-through dimming overlay instead. Right-click a display
  to reset it or switch method. Levels are remembered per display and reapplied after wake or reconnecting,
  and the normal colours come back as soon as Notch quits.
- **Clipboard history.** The last 20 pieces of text you copied. Click one to copy it again. History is kept
  in memory only, and anything a password manager marks as concealed is never recorded.
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
- Display brightness is software dimming only: it darkens the picture but doesn't change the monitor's
  backlight. Apps that also change gamma (f.lux, some calibration tools) will conflict with it.
- App notification alerts work by reading Notification Center's database on this Mac; nothing leaves
  the machine. On macOS 15 and later that database is protected, so Notch needs Full Disk Access there.
- There's no Do Not Disturb toggle: macOS has no public API for switching Focus.
- The shelf stores references to your files, not copies. A file that is moved or deleted drops off the shelf.
- On a Mac without a notch, the virtual notch sits on the built-in display (or the main display if the lid
  is closed) and matches the menu bar's height.

## Layout

```
Sources/Notch/
  main.swift                 app entry (accessory app, no Dock icon)
  App/                       AppDelegate, NotchPanel (window), NotchSpace, NotchController (hover + layout), NotchViewModel
  Services/                  MediaController, BatteryMonitor, ShelfStore, CalendarStore, TimerStore,
                             ClipboardStore, SystemStats, WeatherStore, DisplayBrightness,
                             QuickToggles, BluetoothMonitor, NotificationWatcher, LoginItem
  Views/                     NotchView, NotchShape, HeaderView, HomeView, WidgetsView, ControlsView, ClipboardView, AlertView,
                             ShelfView, CalendarCard, LiveActivityView
```
