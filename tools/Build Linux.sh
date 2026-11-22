#!/usr/bin/env bash
script="$(realpath "$0")"
cd "$(dirname "$script")/.."
source tools/linux-env.sh "$script" "$@"
BUILD_FOLDER="build/linux/x64/release/bundle"
OUTPUT_FOLDER="dist/NotePocket-linux"

require_flutter

if ! flutter build linux --release; then
	echo "Build failed."
	pause
	exit 1
fi

rm -rf "$OUTPUT_FOLDER"
mkdir -p "$(dirname "$OUTPUT_FOLDER")"
cp -r "$BUILD_FOLDER" "$OUTPUT_FOLDER"

echo
echo "Built $OUTPUT_FOLDER/note_pocket"
command -v xdg-open >/dev/null && xdg-open "$OUTPUT_FOLDER" >/dev/null 2>&1 &
pause
