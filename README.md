# MacSponge 🧽

A small, friendly Mac cleaner built with SwiftUI — with a dancing sponge mascot (animated with [Rive](https://rive.app)).

## Features
- **Trash** — see how much is in there and empty it (also handles root-owned leftovers via Finder's admin prompt).
- **System Junk** — user caches, logs, Xcode DerivedData / iOS DeviceSupport, simulator and npm caches. Pick what to delete.
- **Uninstaller** — remove an app together with its preferences, caches, containers and other leftovers in `~/Library`.
- **Space Lens** — drill into folders and see what takes up space (list + bubble chart), then move things to the Trash.
- **Large & Old Files** — find big files in your home folder you haven't touched in a while.

Deletions in *System Junk* and *Trash* are permanent; everything else goes to the Trash so you can restore it. Always look at the list before you confirm.

## Requirements
- macOS 14+
- Xcode 15+ / Swift 5.9+ (command-line tools are enough)

## Build & install
```bash
git clone https://github.com/Kseniaaiaia/MacSponge.git
cd MacSponge
./build.sh                       # produces build/MacSponge.app
cp -R build/MacSponge.app /Applications/
```
`build.sh` signs with your *Apple Development* certificate if you have one (this keeps the Full Disk Access permission across rebuilds). Otherwise it falls back to ad-hoc signing — then on first launch right-click the app → **Open**. You can force a certificate with `SIGN_IDENTITY="Apple Development: …" ./build.sh`.

## Permissions
- **Full Disk Access** — needed to read the Trash and some caches. System Settings → Privacy & Security → Full Disk Access → add MacSponge, then reopen it.
- **Automation (Finder)** — asked once, only when removing apps/files that need an admin password.

## Animation
The mascot is `Resources/sponge-dance.riv`. It is driven by the view-model boolean `isScanning` (`false` → Idle, `true` → Dance). Any `.riv` in `Resources/` is bundled by `build.sh`.

## Disclaimer
Personal project, provided as is — no warranty. It deletes files, so use it at your own risk.

The mascot artwork and animation are © the author and not covered by any open-source license.
