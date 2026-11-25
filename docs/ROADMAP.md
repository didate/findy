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

## Before releasing v0.1

- [ ] Drop on the sidebar, on the path bar and on tabs
- [ ] Cancel a copy or a move while it runs, with progress
- [ ] File icons of the files themselves (app icons, thumbnails), loaded off the main thread
- [ ] Keep the main thread free when the user re-sorts a very large folder (76 ms for 10,000 files today)
- [ ] An option to choose whether folders come first
- [ ] Use the current settings as the default for folders never customized
- [ ] Dim the files that were cut
- [ ] Notarized DMG and Homebrew cask
- [ ] Review the French strings on a French system

## Later

- Copy queue with pause, resume and conflict handling
- Batch rename with regex and preview
- Built-in Quick Look
- Built-in terminal
- Spotlight search scoped to the current folder
- Browse archives without extracting them
- Icon and column views
- SFTP and S3
