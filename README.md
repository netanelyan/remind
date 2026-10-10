<p align="center">
  <img src="icon.png" width="128" alt="Remind app icon: a sleepy raccoon">
</p>

<h1 align="center">Remind</h1>

<p align="center">
  A reminders app for iPhone with a fast quick-add bar and an interactive Home Screen widget.<br>
  Built entirely on Linux, without Xcode or a Mac.
</p>

## Features

- **Groups** with their own name, color and icon. Drag to reorder.
- **Two ways to see everything:** by group, or by urgency (Overdue, Today, Tomorrow, Next 7 Days, Later, No Date). In urgency mode you can drag reminders into your own order inside each level.
- **Quick add** that understands plain language: `gym tomorrow 7am !high #work` becomes a high-priority reminder in Work, due tomorrow at 7 AM. It also handles `in 20 min`, `next monday at 3:30pm`, `oct 15`, `*` for flagged, and more, with live chips showing what it understood.
- **Smart views:** Today, Scheduled, Flagged and All.
- **A hidden Done folder.** Finished reminders leave every list and wait in Done (under the ••• menu), where you can restore or clear them.
- **Home Screen widget** in small, medium and large sizes. Tap a circle to finish a reminder in place, flip between group and urgency layouts, see how many things you got done today, and tap + to jump straight into quick add.
- **Lock Screen widgets:** a progress gauge, the three most urgent reminders, and an inline count.
- **Notifications** when reminders are due.
- Swipe actions, a springy completion animation with haptics, Liquid Glass controls and full dark mode support.

## Built on Linux

The whole app is a Swift package, built and installed from Fedora on WSL with
[xtool](https://github.com/xtool-org/xtool), signed with a free Apple ID. A few problems had to be solved along the way:

- **Sharing data with the widget.** The app and widget share one JSON database through an App Group. Free accounts can't normally get App Groups under xtool, so this uses a build of xtool with [PR #284](https://github.com/xtool-org/xtool/pull/284) applied. Reads and writes go through `NSFileCoordinator`, because the app and the widget can both write.
- **An empty widget binary.** With Swift 6.4, xtool's extension setup links the widget with `-e _NSExtensionMain`, and dead stripping then removes all widget code. One linker flag in `Package.swift` keeps `_main` alive.
- **Widget buttons.** Interactive widget buttons need App Intents metadata (`Metadata.appintents`), which only Xcode generates, and iOS silently ignores them without it. A [GitHub workflow](.github/workflows/appintents-metadata.yml) builds the widget sources with Xcode on a macOS runner and commits the metadata to [`Metadata/`](Metadata). `xtool.yml` copies it into the widget bundle, so the Linux build gets real in-place buttons. The metadata refers to types by module and name, so it only needs regenerating when the intents change.

## Project layout

| Path | What it is |
| --- | --- |
| `Sources/ReminderKit` | Shared by the app and widget: models, storage, sectioning, the quick-add parser |
| `Sources/HelloApp` | The SwiftUI app |
| `Sources/HelloWidget` | WidgetKit extension and its App Intents |
| `ci/` | XcodeGen spec used only by the metadata workflow |
| `xtool.yml` | Bundle setup: icon, entitlements, widget extension |

## Building

You need [xtool](https://github.com/xtool-org/xtool) with an iOS SDK set up, plus a connected iPhone.

```sh
xtool dev build   # compile only, no signing
xtool dev         # build, sign and install on the connected device
```
