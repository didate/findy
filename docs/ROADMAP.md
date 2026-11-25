# Roadmap

## v0.1 (MVP)

- [x] Window with sidebar (favorites, volumes) and a fast file list
- [x] Back, forward and enclosing-folder navigation
- [x] Clickable and editable path bar (⌘L)
- [x] Tabs (⌘T)
- [x] Sort by column, folders first
- [x] Show or hide hidden files
- [x] Folder sizes computed in the background
- [x] Per-folder settings (sort, hidden files) stored in Findy's own database
- [x] Instant filter: type to filter the current folder
- [x] New folder, rename, move to Trash
- [x] Cut, copy, paste (⌘X, ⌘C, ⌘V) with conflict handling
- [x] Undo and redo of every file operation
- [x] Dual pane (⇧⌘D), copy and move to the other pane (F5, F6)
- [x] Live updates with FSEvents
- [x] Symbolic links to folders open like folders
- [x] App icon
- [x] Drag and drop in the list, between panes and with other apps
- [x] Drop on sidebar entries and on path bar segments
- [x] Real icons (apps, custom folders, previews of images and documents), loaded in the background
- [x] Open in Terminal (⌥⌘T), with the terminal app chosen in Settings
- [x] Release script: universal build packaged in a disk image, and a Homebrew cask
- [x] v0.1.0 published on GitHub, installable with `brew install --cask didate/tap/findy`
- [x] Progress of a copy or a move, with a Stop button that works in the middle of a file

## v0.2

- [x] Your own favorites in the sidebar: add a folder (File > Add to Sidebar, ⌃⌘T, or drop it between two favorites), remove it, reorder by dragging
- [x] Cloud storage folders under Locations (iCloud Drive, Google Drive and the other File Provider services)
- [x] Status bar: number of items, selection and its size, free space, and the Git branch of the folder (followed live)
- [x] Copy Path (⌥⌘C) for the selection or the current folder
- [x] Open in Editor (⌥⌘E): the selection, or the current folder as a project, in the code editor chosen in Settings
- [x] Git changes in the status bar: files changed, commits to push and to pull
- [x] Git state of each entry in the list: modified, added, renamed, untracked, in conflict; folders holding changes are flagged and ignored entries are dimmed
- [x] Quick Look on the space bar (⌘Y), following the selection
- [x] New File (⌥⌘N): an empty file, named on the spot
- [x] Git states follow the whole working tree, not only the folder shown
- [x] View > Folders First, remembered per folder
- [x] Cut files are dimmed until they are pasted
- [x] Re-sorting a folder of more than 2,000 entries no longer holds the main thread (76 ms before for 10,000 files, a few microseconds now)
- [x] View > Group by Date: sections like Finder's (Today, Yesterday, Previous 7 Days…), remembered per folder
- [x] v0.2.0 and v0.2.1 published on GitHub and in the Homebrew tap
- [x] Releases signed with a stable self-signed certificate, so macOS stops asking for the same permissions after each update

## v0.3 (in progress)

- [x] Open With, in the context menu of a file
- [x] Eject removable volumes, disk images and network shares from the sidebar; the sidebar follows volumes as they come and go
- [x] Duplicate (⌘D)
- [x] Show in Finder (⇧⌘R)

## Next

- [ ] Drop on tabs. The tabs are the system's own (see `docs/decisions/0002-native-window-tabs.md`) and AppKit offers no way to receive a drop on them: this needs either a custom tab bar or another gesture
- [ ] Group by Date Added, and by kind or size (today the groups follow the modification date)
- [ ] Use the current settings as the default for folders never customized
- [ ] Sign with a Developer ID and notarize (needs an Apple Developer account)
- [ ] Review the French strings on a French system

## Later

- Copy queue with pause, resume and conflict handling
- Batch rename with regex and preview
- Spotlight search scoped to the current folder
- Browse archives without extracting them
- Icon and column views
- SFTP and S3
- Recents and Tags in the sidebar (both need a Spotlight query)
- Trash in the sidebar (today the Trash is left to Finder; this needs a change of that rule first)

## Not planned

- Built-in terminal. Open in Terminal hands the folder to the user's own terminal app, which is enough.
