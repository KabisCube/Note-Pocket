#!/usr/bin/env bash
script="$(realpath "$0")"
cd "$(dirname "$script")"
source tools/linux-env.sh "$script" "$@"

require_flutter

# Use adb from PATH, or from the Android SDK if ANDROID_HOME is set
ADB="$(command -v adb)"
if [ -z "$ADB" ] && [ -n "$ANDROID_HOME" ] && [ -x "$ANDROID_HOME/platform-tools/adb" ]; then
	ADB="$ANDROID_HOME/platform-tools/adb"
fi
if [ -z "$ADB" ]; then
	echo "adb was not found. Install the Android platform tools or set ANDROID_HOME."
	pause
	exit 1
fi

DEVICE_ID="$("$ADB" devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')"

if [ -z "$DEVICE_ID" ]; then
	echo "No Android device found. Connect the phone with USB debugging enabled."
	pause
	exit 1
fi

flutter run -d "$DEVICE_ID"
pause
