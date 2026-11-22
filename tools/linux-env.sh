# Shared setup for the Linux launcher scripts. Source it at the top of a script with:
#   source tools/linux-env.sh "<absolute path of the script>" "$@"

# When started from a file manager there is no terminal, so reopen the script in one.
if [ ! -t 1 ] && [ -z "${NOTE_POCKET_IN_TERMINAL:-}" ]; then
	export NOTE_POCKET_IN_TERMINAL=1
	script="$1"; shift
	for terminal in konsole gnome-terminal kgx ptyxis xfce4-terminal kitty alacritty foot xterm x-terminal-emulator; do
		command -v "$terminal" >/dev/null || continue
		case "$terminal" in
			gnome-terminal|kgx|ptyxis) exec "$terminal" -- bash "$script" "$@" ;;
			*) exec "$terminal" -e bash "$script" "$@" ;;
		esac
	done
	notify-send "Note Pocket" "No terminal found to run $(basename "$script")" 2>/dev/null
	exit 1
fi
# The marker only stops the reopened script from reopening again. Clear it so programs
# started from here (like the file manager window Build Linux.sh opens) don't inherit it.
unset NOTE_POCKET_IN_TERMINAL

# Scripts started outside a shell don't load ~/.zshrc, so add the usual install locations.
if ! command -v flutter >/dev/null; then
	for dir in "$HOME/development/flutter/bin" "$HOME/flutter/bin" "/opt/flutter/bin"; do
		[ -x "$dir/flutter" ] && export PATH="$dir:$PATH" && break
	done
fi
if [ -z "${ANDROID_HOME:-}" ] && [ -d "$HOME/Android/Sdk" ]; then
	export ANDROID_HOME="$HOME/Android/Sdk"
fi

pause() { [ -t 0 ] && read -rp "Press Enter to close..."; }

require_flutter() {
	if ! command -v flutter >/dev/null; then
		echo "flutter was not found. Install Flutter and add it to your PATH."
		pause
		exit 1
	fi
}
