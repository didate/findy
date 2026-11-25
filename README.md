# Findy

A free, open-source, native file manager for macOS. It runs alongside Finder and focuses on speed and reliability.

> Early development. Findy can browse folders today; file operations are not implemented yet.

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

- `App/`: app entry point.
- `Packages/FindyCore/`: file system logic, no UI.
- `Packages/FindyUI/`: SwiftUI views and AppKit controllers.

## License

[MIT](LICENSE)
