# ClipShelf 1.00

[日本語](README.md) | English

A lightweight clipboard history app for Mac, inspired by the Windows clipboard history experience. Built with SwiftUI and AppKit.

## Features

- Press **Ctrl+V** to open your history near the text insertion point. The shortcut is customizable.
- **Select with ↑/↓ and press Enter to paste into the original app.** Clicking a card works too.
- Text and image history, search, pinning, and individual item deletion.
- Menu bar access and launch at login.
- Light and dark themes, with Liquid Glass on macOS 26 and later.
- History limited to 80 items / 48 MiB, with a thumbnail cache of up to 12 MiB.
- No network access or account required. Your history stays on your Mac.

## Requirements

An Apple Silicon Mac running macOS 13 or later. Earlier versions of macOS than 26 use a standard translucent appearance. No Intel build is provided. Hardware testing was performed on macOS 27.0.1.

## Installation

1. Download `ClipShelf-1.00-macOS-arm64.zip` from [Releases](https://github.com/jiig6tyg1/ClipShelf/releases) and extract it.
2. Move `ClipShelf.app` to Applications and open it.
3. From the app's settings, grant ClipShelf Accessibility permission in macOS.
4. Focus the destination text field and press Ctrl+V.

**The distributed binary is ad-hoc signed. It is not signed with a Developer ID or notarized by Apple.** macOS may block it from opening. You can also build the app from source.

## Usage

| Action | Result |
| --- | --- |
| Ctrl+V | Show or hide clipboard history |
| ↑ / ↓ | Select an item |
| Enter / click a card | Paste into the original input field |
| Esc | Close the popup |
| ⌘, | Open settings |
| Left-click the menu bar icon | Show or hide clipboard history |
| Right-click the menu bar icon | Settings and Quit |

If the app cannot determine the insertion point, it opens near the mouse pointer. You can enable launch at login in settings.

### If pasting fails despite granting permission

Check the Accessibility (「アクセシビリティ」) and key event sending (「キー送信」) status indicators in settings.

1. Remove the existing ClipShelf entry from macOS Privacy settings, then add `/Applications/ClipShelf.app` again and enable it.
2. **Quit and reopen ClipShelf.** Key event permission changes may not take effect until the app restarts.

Because the app uses a development signature, updating or rebuilding it may require granting permission again. Without permission, ClipShelf copies the item to the clipboard and displays guidance.

## History and privacy

- History is kept in memory by default. Enabling “Keep history after quitting” (「終了後も履歴を保存」) saves it to `~/Library/Application Support/ClipShelf/history.plist`.
- Saved history is not encrypted. Disabling persistence deletes both current and legacy history files.
- Known confidential and temporary clipboard formats are excluded, but this cannot identify every password or sensitive item.
- When a history limit is reached, older unpinned items are removed. Up to 20 items can be pinned.
- Each text item is limited to 1 MB; each image is limited to 8 MB and 40 million pixels. Images are displayed as thumbnails, but the original is used for pasting.
- The clipboard is checked every 0.6 seconds. Very rapid consecutive copies may be missed.
- The 48 MiB limit applies to history data, not the app's total memory usage.

## Building and testing

Requires Xcode with the macOS 26 SDK or later and Swift. No external packages are used.

```sh
zsh build.sh
zsh test.sh
zsh benchmark.sh
```

The build produces `ClipShelf.app`. Tests and benchmarks use a dedicated clipboard and do not modify the general clipboard. The GUI test harness, `Tests/PasteHarness.swift`, is an exception: it writes test text to the general clipboard.

In a history-processing benchmark with 160 image insertions, memory usage decreased from 290.5 MiB before optimization to 72.1 MiB afterward. This was a single-run comparison excluding UI rendering and persistent storage. See the [measurement report](MEMORY-REPORT.txt) and [Benchmarks](Benchmarks/) for conditions and raw data.

## Limitations

- File history and rich text formatting preservation are not supported.
- Insertion point detection and pasting support vary by app.
- Enter-to-paste was verified in a dedicated AppKit text field with Accessibility permission enabled. This does not guarantee compatibility with every editor.
- The binary is not notarized. Hardware testing on older macOS versions, Intel support, and a stable distribution signing identity remain future work.

## License

[MIT](LICENSE)
