#!/bin/bash
# Puts Apex DuoView on the iPhone plugged into this Mac, in one go:
#   1. finds your signing team (from the Apple ID you signed in to Xcode with),
#   2. saves it, with a bundle ID, in Config/Signing.local.xcconfig (git-ignored, never committed),
#   3. regenerates the Xcode project, builds the app for the phone, installs it and opens it.
#
# Run:  bash ~/apexview-duo/scripts/install-on-duo.sh
#
# Done by hand, once, before the first run:
#   - Xcode > Settings… > Accounts: your Apple ID is listed (a free "Personal Team" works).
#   - On the phone: Settings > Privacy & Security > Developer Mode on (the phone restarts).
#   - Phone plugged in with a cable, unlocked, and "Trust" tapped.
#
# It prints no team ID, bundle ID or other personal value, so its output can be shared.
set -euo pipefail

cd "$(dirname "$0")/.."
LOCAL="Config/Signing.local.xcconfig"
OUT="build/device"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say()  { printf '\n==> %s\n' "$*"; }
fail() { printf '\nStopped: %s\n' "$*" >&2; exit 1; }

command -v xcodegen >/dev/null 2>&1 || fail "XcodeGen isn't installed. Run:  brew install xcodegen  and then this again."
xcrun --find devicectl >/dev/null 2>&1 || fail "Xcode's device tools weren't found. Open Xcode once (let it finish installing), then run this again."
xcrun --find xcodebuild >/dev/null 2>&1 || fail "xcodebuild wasn't found. Open Xcode once, then run this again."

# --- 1. Bundle ID: keep yours; make one if there is none yet. ------------------------------------
[ -f "$LOCAL" ] || cp Config/Signing.local.xcconfig.example "$LOCAL"
BUNDLE_ID="$(sed -n 's/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER[[:space:]]*=[[:space:]]*//p' "$LOCAL" | tail -1 | tr -d '[:space:]')"
case "$BUNDLE_ID" in
  ""|com.example.*)
    USERPART="$(id -un | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
    BUNDLE_ID="com.${USERPART:-me}.apexduoview"
    sed -i '' '/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER[[:space:]]*=/d' "$LOCAL"
    printf 'PRODUCT_BUNDLE_IDENTIFIER = %s\n' "$BUNDLE_ID" >> "$LOCAL"
    say "Set a bundle ID of your own in $LOCAL."
    ;;
  *) say "Using the bundle ID already in $LOCAL." ;;
esac

# --- 2. Signing team. ---------------------------------------------------------------------------
TEAM="$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*//p' "$LOCAL" | tail -1 | tr -d '[:space:]')"
case "$TEAM" in ""|YOURTEAMID) TEAM="" ;; esac
if [ -z "$TEAM" ]; then
  # The team Xcode knows from your Apple ID.
  for KEY in IDEProvisioningTeamByIdentifier IDEProvisioningTeams; do
    TEAM="$(defaults read com.apple.dt.Xcode "$KEY" 2>/dev/null | sed -n 's/.*teamID = "\{0,1\}\([A-Z0-9]\{10\}\)"\{0,1\};.*/\1/p' | head -1 || true)"
    [ -n "$TEAM" ] && break
  done
fi
if [ -z "$TEAM" ]; then
  # Or the team of an Apple Development certificate on this Mac (its OU field).
  TEAM="$(security find-certificate -c "Apple Development" -p 2>/dev/null \
          | openssl x509 -noout -subject 2>/dev/null \
          | sed -n 's/.*OU[[:space:]]*=[[:space:]]*\([A-Z0-9]\{10\}\).*/\1/p' | head -1 || true)"
fi
[ -n "$TEAM" ] || fail "No signing team found. In Xcode: Settings… > Accounts > + > Apple ID, sign in, close Settings, then run this again."
sed -i '' '/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=/d' "$LOCAL"
printf 'DEVELOPMENT_TEAM = %s\n' "$TEAM" >> "$LOCAL"
say "Saved your signing team in $LOCAL."

# --- 3. The phone. ------------------------------------------------------------------------------
say "Looking for your phone…"
xcrun devicectl list devices --json-output "$TMP/devices.json" >/dev/null 2>&1 || true
[ -s "$TMP/devices.json" ] || fail "Couldn't list devices. Is the phone plugged in and unlocked?"
PICK="$(/usr/bin/python3 - "$TMP/devices.json" <<'PY'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
best = None
for d in devices:
    hw, conn, dev = d.get("hardwareProperties", {}), d.get("connectionProperties", {}), d.get("deviceProperties", {})
    if hw.get("platform") != "iOS" or not hw.get("udid"):
        continue
    if hw.get("reality") == "virtual":
        continue
    score = (conn.get("transportType") == "wired") * 2 + (conn.get("tunnelState") == "connected")
    if best is None or score > best[0]:
        model = (hw.get("marketingName") or hw.get("productType") or "iPhone").replace(" ", "_")
        best = (score, hw["udid"], dev.get("developerModeStatus", ""), conn.get("pairingState", ""), model)
if best:
    print(best[1], best[2] or "-", best[3] or "-", best[4])
PY
)"
[ -n "$PICK" ] || fail "No iPhone found. Plug it in with a cable, unlock it, tap Trust, then run this again."
read -r UDID DEVMODE PAIRED MODEL <<<"$PICK"
[ "$PAIRED" = "unpaired" ] && fail "The phone isn't paired with this Mac yet. Unlock it, tap Trust, then run this again."
say "Found your phone: ${MODEL//_/ }. If that is not your iPhone Duo, unplug the other phone and run this again."
if [ "$DEVMODE" = "disabled" ]; then
  # iOS only shows the Developer Mode switch after a Mac has tried to put an app on the phone,
  # so carry on: this attempt is what makes it appear.
  printf '\nDeveloper Mode is off on the phone. This run will try anyway, which makes the switch appear.\n'
  printf 'Afterwards: on the phone, Settings > Privacy & Security > Developer Mode (at the bottom) > on,\n'
  printf 'let it restart, tap Turn On, then run this script again.\n'
fi

# --- 4. Project, build, install, open. -----------------------------------------------------------
say "Regenerating the Xcode project…"
xcodegen generate --quiet

say "Building for the phone (the first time takes a few minutes)…"
mkdir -p "$OUT"
if ! xcodebuild -project DuoApp.xcodeproj -scheme DuoApp -configuration Debug \
      -destination "id=$UDID" -derivedDataPath "$OUT" \
      -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
      build > "$OUT/build.log" 2>&1; then
  echo
  grep -E "error:|failed|Provisioning|signing|Signing" "$OUT/build.log" | grep -v "^note:" | sort -u | head -25 \
    | sed -e "s|$TEAM|<team>|g" -e "s|$BUNDLE_ID|<bundle id>|g" -e "s|$UDID|<phone>|g" -e "s|$HOME|~|g"
  fail "The build failed (lines above; the full log is $OUT/build.log). Copy the lines above to Claude."
fi
WARNINGS="$(grep -c ": warning:" "$OUT/build.log" || true)"
say "Built. Warnings: ${WARNINGS:-0}."

APP="$OUT/Build/Products/Debug-iphoneos/DuoApp.app"
[ -d "$APP" ] || fail "The build finished but the app wasn't where expected ($APP)."

say "Installing on the phone…"
xcrun devicectl device install app --device "$UDID" "$APP" > "$TMP/install.log" 2>&1 \
  || { sed -e "s|$UDID|<phone>|g" -e "s|$BUNDLE_ID|<bundle id>|g" "$TMP/install.log" | tail -15; fail "Installing failed (lines above)."; }

say "Opening Apex DuoView…"
if ! xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID" > "$TMP/launch.log" 2>&1; then
  cat <<'TXT'

The app is installed but the phone wouldn't open it yet. That is normal the first time with a free
Apple ID. On the phone: Settings > General > VPN & Device Management > tap your Apple ID under
"Developer App" > Trust. Then tap the Apex DuoView icon on the home screen.
TXT
  exit 0
fi

cat <<'TXT'

Done: Apex DuoView is open on your phone.
With a free Apple ID it stops opening after 7 days; just run this script again.
TXT
