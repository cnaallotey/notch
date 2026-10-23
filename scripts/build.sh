#!/usr/bin/env bash
# Builds a universal (Apple Silicon + Intel) Notch.app into ./build.
#
#   scripts/build.sh            release build
#   scripts/build.sh --run      build, then (re)launch the app
#   DEBUG=1 scripts/build.sh    fast unoptimised build for the current Mac only
#
# Calls swiftc directly so it works with just the Command Line Tools (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="$(xcrun --sdk macosx --show-sdk-path)"
SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(find Sources -name '*.swift' | sort)
OUT=".build/manual"
mkdir -p "$OUT"

if [[ -n "${DEBUG:-}" ]]; then
  ARCHS=("$(uname -m)")
  FLAGS=(-Onone -g -DDEBUG)
else
  ARCHS=(arm64 x86_64)
  FLAGS=(-O -whole-module-optimization)
fi

SLICES=()
for arch in "${ARCHS[@]}"; do
  echo "Compiling $arch…"
  swiftc "${FLAGS[@]}" -sdk "$SDK" -target "$arch-apple-macos13.0" \
    -module-name Notch "${SOURCES[@]}" -o "$OUT/Notch-$arch"
  SLICES+=("$OUT/Notch-$arch")
done

APP="build/Notch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/Notch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/Notch"))"

if [[ "${1:-}" == "--run" ]]; then
  pkill -x Notch 2>/dev/null || true
  open "$APP"
fi
