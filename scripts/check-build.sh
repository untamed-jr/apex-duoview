#!/bin/bash
# Builds Apex DuoView for the Mac's iPhone simulator, to check new code compiles, without touching
# the phone. Prints the errors (if any) and the warning count, ready to paste back to Claude.
#
# Run:  bash ~/apexview-duo/scripts/check-build.sh
#       bash ~/apexview-duo/scripts/check-build.sh --shots   (also runs the app in the "iPhone Duo"
#       simulator and saves screenshots of the opening to build/shots/, flat and laptop shapes)
#
# Nothing is installed on the phone and nothing is signed. Output has no personal values in it.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="build/sim"
SIM="${DUO_SIM:-iPhone Duo}"

say()  { printf '\n==> %s\n' "$*"; }
fail() { printf '\nStopped: %s\n' "$*" >&2; exit 1; }

command -v xcodegen >/dev/null 2>&1 || fail "XcodeGen isn't installed. Run:  brew install xcodegen  and then this again."

say "Code: $(git rev-parse --short HEAD) ($(git log -1 --format=%s | cut -c1-70))"
xcodegen generate --quiet

say "Building for the simulator…"
mkdir -p "$OUT"
if ! xcodebuild -project DuoApp.xcodeproj -scheme DuoApp -configuration Debug \
      -destination "generic/platform=iOS Simulator" -derivedDataPath "$OUT" \
      CODE_SIGNING_ALLOWED=NO DUO_COMMIT="$(git rev-parse --short HEAD)" \
      build > "$OUT/build.log" 2>&1; then
  echo
  grep -E "error:" "$OUT/build.log" | sed -e "s|$PWD/||g" -e "s|$HOME|~|g" | sort -u | head -40
  fail "The build failed (lines above; full log: $OUT/build.log). Copy the lines above to Claude."
fi
WARNINGS="$(grep -E ": warning:" "$OUT/build.log" | grep -v "appintentsmetadataprocessor" | sed -e "s|$PWD/||g" | sort -u || true)"
COUNT="$(printf '%s' "$WARNINGS" | grep -c . || true)"
say "BUILD OK. Warnings: ${COUNT:-0}."
[ "${COUNT:-0}" = "0" ] || printf '%s\n' "$WARNINGS" | head -20

[ "${1:-}" = "--shots" ] || exit 0

APP="$OUT/Build/Products/Debug-iphonesimulator/DuoApp.app"
BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
UDID="$(xcrun simctl list devices available | grep -F "$SIM (" | head -1 | grep -oE '[0-9A-F-]{36}')" \
  || fail "No simulator called \"$SIM\". Set DUO_SIM to one from: xcrun simctl list devices"
xcrun simctl boot "$UDID" 2>/dev/null || true
open "$(xcode-select -p)/Applications/Simulator.app" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP"
mkdir -p build/shots
for t in 1.4 2.0 2.8 3.6; do
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  sleep "$t"
  # The Duo simulator has two screens; DUO_DISPLAY picks which one (default 1).
  xcrun simctl io "$UDID" screenshot --display="${DUO_DISPLAY:-1}" --type=png "build/shots/opening-${t}s.png" >/dev/null \
    || printf 'Screenshot at %ss failed (try DUO_DISPLAY=internal).\n' "$t"
done
say "Screenshots saved in build/shots/ (at 1.4, 2.0, 2.8 and 3.6 s after launch: the opening, then the tour on a first launch)."
