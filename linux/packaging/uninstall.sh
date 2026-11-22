#!/usr/bin/env bash
# Removes Note Pocket from the app menu again. The app folder and your notes are not touched.
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
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"

rm -f "$data_home/applications/$APP_ID.desktop" "$data_home/icons/hicolor/256x256/apps/$APP_ID.png"

echo "Note Pocket was removed from the app menu."
