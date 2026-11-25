# Findy

A free, open-source, native file manager for macOS. It runs alongside Finder and focuses on speed and reliability.

> Early development (v0.1 in progress). The features below work.

## Features

- Sidebar with your own favorites and your cloud folders, tabs (⌘T) and an optional second pane (⇧⌘D)
- Path bar you can click or type in (⌘L)
- Type in the list to filter the current folder instantly
- Folder sizes and real file icons, computed in the background
- Sort order and hidden files remembered per folder, without `.DS_Store` files
- Cut, copy, paste, rename, new folder, move to Trash
- Drag and drop that is predictable: a drag moves, Option-drag copies, on any volume
- Nothing is overwritten silently: Keep Both, Replace or Skip
- A copy shows its progress and can be stopped at any point, leaving nothing half-written
- Undo and redo for every file operation
- Open in Terminal (⌥⌘T) on the current or the selected folder, in the terminal app of your choice
- The list follows changes on disk
- English and French

## Install

Findy needs macOS 14 or later. It runs on Apple Silicon and Intel.

With Homebrew:

```bash
brew tap didate/tap
brew trust didate/tap
brew install --cask findy
```

`brew trust` exists in recent versions of Homebrew, which refuse casks from a third-party tap until it is trusted. If your Homebrew does not know the command, skip that line.

Or download `Findy-<version>.dmg` from the [latest release](https://github.com/didate/findy/releases/latest), open it and drag Findy to Applications.

**The first launch needs one extra step.** Findy is not notarized by Apple yet, so macOS refuses to open it at first. Open it once, dismiss the warning, then go to System Settings > Privacy & Security and click Open Anyway. Or run this once:

```bash
xattr -dr com.apple.quarantine /Applications/Findy.app
```

## Goals

1. **Never lose data.** Every destructive action is explicit and undoable.
2. **Never freeze.** The interface stays responsive on huge folders and slow volumes.
3. **Remember.** Per-folder view settings are kept reliably.

See [docs/ROADMAP.md](docs/ROADMAP.md) for what is planned.

## Build

Requirements: macOS 14 or later, Xcode 16 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open Findy.xcodeproj
```

## Test

```bash
swift test --package-path Packages/FindyCore
swift test --package-path Packages/FindyUI
```

## Layout

- `App/`: app entry point and assets.
- `Packages/FindyCore/`: file system logic, no UI.
- `Packages/FindyUI/`: SwiftUI views and AppKit controllers.
- `docs/`: roadmap and architecture decisions.
- `scripts/make-icon.swift`: regenerates the app icon.
- `scripts/release.sh`: builds the release disk image; see [docs/RELEASING.md](docs/RELEASING.md).
- `packaging/homebrew/`: the Homebrew cask.

## License

[MIT](LICENSE)
