#!/usr/bin/env bash
# Usage: shot_simulator.sh "<device type name>" <language>
# Prints the UDID of a screenshot-only simulator, booted with that system language.
#
# The share sheet is drawn by the system, in the system language, whatever the app
# is launched with — an English shot of it on a Chinese simulator comes out half
# Chinese. So each language needs the simulator itself switched, which is why these
# are dedicated simulators rather than ones other projects are using.
set -euo pipefail
type_name=$1
language=$2
runtime=com.apple.CoreSimulator.SimRuntime.iOS-26-5
name="Ringtone Shots ($type_name)"

udid=$(xcrun simctl list devices -j | python3 -c '
import json, sys
name, runtime = sys.argv[1], sys.argv[2]
for d in json.load(sys.stdin)["devices"].get(runtime, []):
    if d["name"] == name:
        print(d["udid"]); break
' "$name" "$runtime")
if [ -z "$udid" ]; then
  type_id=$(xcrun simctl list devicetypes -j | python3 -c '
import json, sys
for t in json.load(sys.stdin)["devicetypes"]:
    if t["name"] == sys.argv[1]:
        print(t["identifier"]); break
' "$type_name")
  udid=$(xcrun simctl create "$name" "$type_id" "$runtime")
fi

case $language in
  en) locale=en_US ;;
  zh-Hant) locale=zh_TW ;;
  *) locale=$language ;;
esac

# Preferences can only be rewritten reliably while the simulator is down.
xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
prefs=~/Library/Developer/CoreSimulator/Devices/$udid/data/Library/Preferences/.GlobalPreferences.plist
mkdir -p "$(dirname "$prefs")"
[ -f "$prefs" ] || plutil -create xml1 "$prefs"
plutil -replace AppleLanguages -json "[\"$language\"]" "$prefs"
plutil -replace AppleLocale -string "$locale" "$prefs"
# A fresh simulator greets the first keyboard with a slide-to-type tutorial,
# which covers the naming-alert screenshot.
keyboard=~/Library/Developer/CoreSimulator/Devices/$udid/data/Library/Preferences/com.apple.Preferences.plist
[ -f "$keyboard" ] || plutil -create xml1 "$keyboard"
plutil -replace DidShowContinuousPathIntroduction -bool true "$keyboard"
xcrun simctl bootstatus "$udid" -b >/dev/null
echo "$udid"
