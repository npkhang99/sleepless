# Sleepless

A lightweight macOS menu bar app with separate open-lid and closed-lid sleep prevention modes.

## Features

- **Lid Open mode** — Prevents display and idle system sleep using a temporary IOKit assertion
- **Lid Closed mode** — Keeps the Mac running even after its lid is closed
- **Preserves session state** — Sleepless does not lock or unlock the Mac when the lid closes
- **One-click toggle** — Left-click toggles Lid Open mode on/off
- **Mode selection** — Right-click to select Off, Lid Open, or Lid Closed mode
- **Menu bar only** — No Dock icon, no windows, just a simple menu bar utility
- **Single instance** — Only one instance of the app can run at a time
- **Native** — Built with Swift and IOKit, no dependencies

## How it works

Lid Open mode uses `IOPMAssertionCreateWithName` with `kIOPMAssertionTypeNoDisplaySleep`. It is temporary, requires no administrator authorization, and is automatically released when Sleepless exits.

macOS handles lid-close sleep separately from ordinary idle sleep. Lid Closed mode uses a privileged background helper to toggle the system-wide `pmset disablesleep` setting. macOS asks you to approve the helper once; subsequent Lid Closed mode changes do not require another administrator password. Turning Sleepless off or quitting the app restores normal lid-close sleep behavior. `disablesleep` is an undocumented macOS setting, so a future macOS update may change its behavior.

This setting does not change the login session: an unlocked Mac remains unlocked, and a locked Mac remains locked. macOS can still force sleep for critical battery or thermal conditions.

> [!WARNING]
> Do not put the MacBook in a bag while Sleepless is active. A running Mac can generate heat and drain its battery with the lid closed.

## Menu bar icon

| State | Icon |
|-------|------|
| Off | cup.and.saucer |
| Lid Open | cup.and.saucer.fill |
| Lid Closed | laptopcomputer |

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

## Releasing

Use the `Release` workflow in GitHub Actions and run it manually.

Required inputs:

- `tag` such as `v1.0.0`
- `title` for the GitHub release

Optional inputs:

- `notes` to override auto-generated release notes
- `prerelease` to mark the release as a prerelease

The workflow builds the app, packages a DMG, creates a GitHub Release, and attaches:

- `Sleepless-<tag>.app.zip`
- `Sleepless-<tag>.dmg`

## License

MIT
