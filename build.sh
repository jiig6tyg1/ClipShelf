#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p ClipShelf.app/Contents/MacOS ClipShelf.app/Contents/Resources
swiftc Sources/*.swift -o ClipShelf.app/Contents/MacOS/ClipShelf -target arm64-apple-macosx13.0 -framework AppKit -framework SwiftUI -framework Carbon -O
cp Info.plist ClipShelf.app/Contents/Info.plist
if [[ -f AppIcon.icns ]]; then cp AppIcon.icns ClipShelf.app/Contents/Resources/; fi
codesign --force --deep --sign - ClipShelf.app
echo 'Built ClipShelf.app'
