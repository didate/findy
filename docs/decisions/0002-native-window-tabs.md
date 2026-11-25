# 2. Tabs are native window tabs

## Context

The MVP needs tabs. They can be drawn by the app (a tab bar view and one model per tab in a single window) or be the system's window tabs, where each tab is an `NSWindow`.

## Decision

Tabs are native window tabs. New Tab opens a new `WindowGroup` window and attaches it to the frontmost one with `NSWindow.addTabbedWindow`. SwiftUI has no API for this, so `WindowAccessor` hands each view its `NSWindow` and `BrowserWindow` does the attaching.

## Alternatives set aside

- **A custom tab bar**: full control (pinned tabs, saved sessions), but a lot of code to reproduce what the system gives: drag a tab out into a window, Merge All Windows, the tab overview, the standard shortcuts and accessibility.

## Consequences

- Dragging tabs between windows, the + button and the Window menu commands work with no code of ours.
- Each tab has its own workspace, undo history included.
- Pinned tabs and saved sessions, if wanted later, need either a custom tab bar or state restoration work.
