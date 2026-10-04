#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
sed '/^struct ShelfButtonStyle:/,$d' Sources/main.swift > "$test_tmp/main.swift"

cat Tests/StoreTests.swift >> "$test_tmp/main.swift"
swiftc Sources/ClipboardStore.swift Sources/InputAnchor.swift Sources/LoginItemSettings.swift "$test_tmp/main.swift" -o "$test_tmp/tests" -framework AppKit -framework SwiftUI -framework Carbon
"$test_tmp/tests"
