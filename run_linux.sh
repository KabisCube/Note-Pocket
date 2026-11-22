#!/usr/bin/env bash
script="$(realpath "$0")"
cd "$(dirname "$script")"
source tools/linux-env.sh "$script" "$@"

require_flutter

flutter run -d linux
pause
