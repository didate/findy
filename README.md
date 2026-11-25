# Findy

A free, open-source, native file manager for macOS. It runs alongside Finder and focuses on speed and reliability.

> Early development (v0.1 in progress). The features below work; drag and drop is not there yet.

## Features

- Sidebar, tabs (⌘T) and an optional second pane (⇧⌘D)
- Path bar you can click or type in (⌘L)
- Type in the list to filter the current folder instantly
- Folder sizes, computed in the background
- Sort order and hidden files remembered per folder, without `.DS_Store` files
- Cut, copy, paste, rename, new folder, move to Trash
- Nothing is overwritten silently: Keep Both, Replace or Skip
- Undo and redo for every file operation
- The list follows changes on disk
- English and French

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

## License

[MIT](LICENSE)
