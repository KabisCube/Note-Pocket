#!/usr/bin/env bash
# Publishes a new release: checks the repo, runs the tests, bumps the version in pubspec.yaml,
# writes the changelog, then commits, tags vX.Y.Z and pushes. GitHub Actions builds and uploads the apps.
# Linux/macOS version of release.ps1.
set -uo pipefail
cd "$(dirname "$0")/.."

RED=$'\e[31m'; GREEN=$'\e[32m'; RESET=$'\e[0m'

stop_release() {
	echo "${RED}$1${RESET}"
	exit 1
}

run_git() {
	local output
	if ! output="$(git "$@" 2>&1)"; then
		stop_release "git $* failed:"$'\n'"$output"
	fi
	printf '%s' "$output"
}

# True if version $1 is newer than version $2
is_newer() {
	[ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
}

pubspec_file="pubspec.yaml"
version_line="$(grep -E '^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+' "$pubspec_file" | head -n1)"
[ -n "$version_line" ] || stop_release "Could not find the version in $pubspec_file."
current_code="${version_line##*+}"

latest_tag="$(git tag --list 'v*' --sort=-v:refname | head -n1)"
latest_version="${latest_tag#v}"
[ -n "$latest_version" ] || latest_version="0.0.0"
IFS=. read -r major minor patch <<< "$latest_version"
suggested="$major.$minor.$((patch + 1))"

echo "Latest release: $latest_tag"
version="${1:-}"
if [ -z "$version" ]; then
	read -rp "New version (Enter for $suggested): " version
	[ -n "$version" ] || version="$suggested"
fi
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || stop_release "Version must look like 1.2.3, got '$version'."
is_newer "$version" "$latest_version" || stop_release "Version $version must be newer than $latest_version."
tag="v$version"

[ -z "$(run_git status --porcelain)" ] || stop_release "You have uncommitted changes. Commit or stash them first."
branch="$(run_git rev-parse --abbrev-ref HEAD)"
[ "$branch" = "main" ] || stop_release "Releases are made from main, but you are on '$branch'."
run_git fetch origin main --tags >/dev/null
[ "$(run_git rev-list --count 'HEAD..origin/main')" = "0" ] || stop_release "GitHub has commits you do not have. Pull first."
[ -z "$(run_git tag --list "$tag")" ] || stop_release "Tag $tag already exists."

echo "Running tests..."
flutter test || stop_release "Tests failed. Nothing was released."

new_code=$((current_code + 1))
changelog_dir="fastlane/metadata/android/en-US/changelogs"
changelog="$changelog_dir/$new_code.txt"
mkdir -p "$changelog_dir"
[ -f "$changelog" ] || : > "$changelog"

# Open the changelog in an editor and wait for it to close
if [ -n "${VISUAL:-${EDITOR:-}}" ]; then
	editor=(${VISUAL:-$EDITOR})
elif command -v kate >/dev/null; then
	editor=(kate --block)
elif command -v code >/dev/null; then
	editor=(code --wait)
else
	editor=(nano)
fi
echo "Write what changed in $version, then save and close the editor."
"${editor[@]}" "$changelog"

notes="$(<"$changelog")"
notes="${notes#"${notes%%[![:space:]]*}"}"
notes="${notes%"${notes##*[![:space:]]}"}"
max_changelog_chars=500
if [ -z "$notes" ]; then
	rm -f "$changelog"
	stop_release "The changelog is empty. Nothing was released."
fi
notes_length="$(printf '%s' "$notes" | wc -m)"
[ "$notes_length" -le "$max_changelog_chars" ] || stop_release "The changelog is $notes_length characters. F-Droid allows $max_changelog_chars. Shorten it and run again."

sed -i -E "s/^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+/version: $version+$new_code/" "$pubspec_file"

echo "Releasing $tag (version code $new_code)..."
run_git add -- "$pubspec_file" "$changelog" >/dev/null
run_git commit -m "Release $version" >/dev/null
run_git tag -a "$tag" -m "Note Pocket $version" >/dev/null
run_git push --atomic origin main "$tag" >/dev/null
echo "${GREEN}Done. GitHub is now building $tag; the apps appear under Releases in a few minutes.${RESET}"
