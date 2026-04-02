# Sleepless

A lightweight macOS menu bar app that keeps your Mac awake.

## Features

- **One-click toggle** — Left-click the menu bar icon to toggle sleep prevention on/off
- **Right-click menu** — Right-click for status info and quit option
- **Menu bar only** — No Dock icon, no windows, just a simple menu bar utility
- **Single instance** — Only one instance of the app can run at a time
- **Native** — Built with Swift and IOKit, no dependencies

## How it works

Sleepless uses `IOPMAssertionCreateWithName` with `kIOPMAssertionTypeNoDisplaySleep` to create a power assertion that prevents both display sleep and system sleep while active.

## Menu bar icon

| State | Icon |
|-------|------|
| Awake | cup.and.saucer.fill |
| Sleep allowed | cup.and.saucer |

## Requirements

- macOS 14.0+
- Xcode 15.0+

## Building

Build a production `.app` bundle:

```bash
make build
```

Package the app into a `.dmg`:

```bash
make package
```

Outputs:

- `build/Build/Products/Release/Sleepless.app`
- `dist/Sleepless.dmg`

You can still open `sleepless.xcodeproj` in Xcode and build with Cmd+B.

## License

MIT
