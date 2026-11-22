#!/usr/bin/env bash
script="$(realpath "$0")"
cd "$(dirname "$script")/.."
source tools/linux-env.sh "$script" "$@"
require_flutter

bash tools/release.sh "$@"
result=$?
pause
exit $result
