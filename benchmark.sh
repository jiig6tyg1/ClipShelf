#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
bench_tmp=$(mktemp -d)
trap 'rm -rf "$bench_tmp"' EXIT
bench_source=${1:-Sources/ClipboardStore.swift}
sed '/^struct Shortcut:/,$d' "$bench_source" > "$bench_tmp/main.swift"
cat Benchmarks/Memory.swift >> "$bench_tmp/main.swift"
swiftc "$bench_tmp/main.swift" -O -o "$bench_tmp/benchmark" -framework AppKit -framework SwiftUI -framework Carbon
"$bench_tmp/benchmark"
