#!/usr/bin/env bash
# Adds Note Pocket to the app menu with its icon, for the folder this script is in.
# Run it again after moving the folder. uninstall.sh removes it again.
set -euo pipefail

# Started from a file manager there is no terminal, so reopen in one to show what happens.
# Without any terminal program it still runs, just without a window.
if [ ! -t 1 ] && [ -z "${NOTE_POCKET_IN_TERMINAL:-}" ]; then
	export NOTE_POCKET_IN_TERMINAL=1
	for terminal in konsole gnome-terminal kgx ptyxis xfce4-terminal kitty alacritty foot xterm x-terminal-emulator; do
		command -v "$terminal" >/dev/null || continue
		case "$terminal" in
			gnome-terminal|kgx|ptyxis) exec "$terminal" -- bash "$(realpath "$0")" ;;
			*) exec "$terminal" -e bash "$(realpath "$0")" ;;
		esac
	done
fi
# The marker only stops the reopened script from reopening again. Clear it so programs
# started from here (like a file manager window) don't inherit it.
opened_terminal="${NOTE_POCKET_IN_TERMINAL:-}"
unset NOTE_POCKET_IN_TERMINAL
# In a terminal opened just for this, wait before it closes, also after an error
if [ -n "$opened_terminal" ] && [ -t 0 ]; then
	trap 'echo; read -rp "Press Enter to close..."' EXIT
fi

APP_ID="com.notepocket.app"
folder="$(dirname "$(realpath "$0")")"
program="$folder/note_pocket"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
icon_file="$data_home/icons/hicolor/256x256/apps/$APP_ID.png"
desktop_file="$data_home/applications/$APP_ID.desktop"

if [ ! -x "$program" ]; then
	echo "note_pocket was not found next to this script, in $folder"
	exit 1
fi

# Quotes a path for the Exec line of a .desktop file
desktop_quote() {
	local path="$1"
	path="${path//\\/\\\\}"; path="${path//\"/\\\"}"; path="${path//\`/\\\`}"; path="${path//\$/\\\$}"
	path="${path//\\/\\\\}"
	path="${path//%/%%}"
	printf '"%s"' "$path"
}

mkdir -p "$(dirname "$icon_file")" "$(dirname "$desktop_file")"
cp "$folder/data/app_icon.png" "$icon_file"
# The file is named after the app ID: Wayland desktops find a window's icon that way
cat > "$desktop_file" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Note Pocket
Comment=Plain text notes and checklists
Exec=$(desktop_quote "$program")
Path=$folder
Icon=$APP_ID
Terminal=false
Categories=Utility;TextEditor;
Keywords=notes;checklist;todo;text;
StartupWMClass=$APP_ID
DESKTOP

echo "Note Pocket is now in the app menu."
echo "It runs $program"
