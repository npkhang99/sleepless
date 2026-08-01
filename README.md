# Sleepless

A lightweight macOS menu bar app with separate open-lid and closed-lid sleep prevention modes.

## Features

- **Lid Open mode** — Prevents idle system sleep while allowing the monitor to turn off normally
- **Lid Closed mode** — Keeps the Mac running even after its lid is closed
- **Closed-lid monitor control** — Keeps the monitor on by default to avoid idle display-off and automatic locking, with a toggle to allow it to turn off
- **One-click cycle** — Left-click cycles Off → Lid Open → Lid Closed → Off
- **Mode selection** — Right-click to select Off, Lid Open, or Lid Closed mode
- **Automatic updates** — Checks GitHub Releases and can install signed updates automatically
- **Launch at login** — Optionally starts Sleepless when you sign in to your Mac
- **Version visibility** — Shows the installed app and build version directly above Quit
- **Menu bar only** — No Dock icon, no windows, just a simple menu bar utility
- **Single instance** — Only one instance of the app can run at a time
- **Native** — Built with Swift, IOKit, and Sparkle

## How it works

Lid Open mode uses `IOPMAssertionCreateWithName` with `kIOPMAssertionTypePreventUserIdleSystemSleep`. It keeps background work running while allowing the monitor to follow its normal display sleep timer. The assertion is temporary, requires no administrator authorization, and is automatically released when Sleepless exits.

macOS handles lid-close sleep separately from ordinary idle sleep. Lid Closed mode uses a privileged background helper to toggle the system-wide `pmset disablesleep` setting. It also keeps the monitor awake by default so an idle display-off does not trigger the configured automatic lock. Right-click the menu bar icon and turn off **Keep Monitor On** if you want the monitor to follow the normal display sleep timer while background work continues.

macOS asks you to approve the helper once; subsequent Lid Closed mode changes do not require another administrator password. Turning Sleepless off or quitting the app restores normal lid-close sleep behavior. `disablesleep` is an undocumented macOS setting, so a future macOS update may change its behavior. macOS can still force sleep for critical battery or thermal conditions.

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

Install the build into `/Applications` and restart the app:

```bash
make install
```

You can still open `sleepless.xcodeproj` in Xcode and build with Cmd+B.

### Code signing

The build is always signed, because `SMAppService` refuses to register the
background helper unless the app bundle seals the daemon plist with a signature.

`make build` picks the first Developer ID Application or Apple Development
identity in your keychain, and falls back to ad-hoc signing when there is none.
Override it with `make build CODESIGN_IDENTITY="..."`.

Ad-hoc builds work, but their signature changes on every build, so macOS asks you
to approve the helper again after each update.

## Updates

Right-click the menu bar icon to check for updates or toggle automatic
installation. Automatic updates install and relaunch Sleepless as soon as the
download finishes. Updates are delivered by Sparkle from the latest GitHub
Release and verified with the app's EdDSA public key before installation.

## Releasing

Publish from your own Mac so the assets carry your signing identity:

```bash
make release TAG=v0.0.7
```

This builds, signs, packages, and then creates the GitHub release, or uploads to
it when the tag already exists. It needs the `gh` CLI to be logged in.

It attaches `Sleepless-<tag>.dmg` and its signed `appcast.xml`. The appcast is
what installed copies use to discover and verify the latest update. The DMG
makes installing into `/Applications` the obvious path, which keeps the
background helper's location stable.

Releases are not built in CI. A GitHub runner has no signing certificate and can
only sign ad-hoc, which makes macOS ask for helper approval after every update.
The `Build` workflow only checks that the project compiles.

## License

MIT
