# Maintainer notes

## Local Windows build

Run **tools/Build Windows.bat** to build a release version into `dist/NotePocket-windows/`. Keep the files next to `note_pocket.exe` when moving it.

## Local Linux build

Run **tools/Build Linux.sh** to build a release version into `dist/NotePocket-linux/`. Keep the files next to `note_pocket` when moving it. It needs `flutter` on your PATH plus `clang cmake ninja pkg-config gtk3`.

To run the app while developing, use `run_linux.sh` or `run_android.sh` in the project root (the Linux versions of the `.bat` files). `run_android.sh` uses `adb` from your PATH or from `$ANDROID_HOME/platform-tools`.

## Screenshots

Run **tools/Take Screenshots.bat** to render the README screenshots into `docs/screenshots/`. They show the made-up notes in `tools/screenshots/notes`, never your own. The note order is in `tools/screenshots/order.txt` and the tag colors are at the top of `tools/screenshots/screenshots_test.dart`. It needs Windows, since it loads the Consolas font from the system.

## Release signing

To sign release builds with your own key, create a keystore in `signing/` and copy `signing/keystore.properties.example` to `signing/keystore.properties` with your values:

```sh
keytool -genkeypair -v -keystore signing/release.jks -alias notepocket -keyalg RSA -keysize 4096 -validity 10000
```

Both `keystore.properties` and `*.jks` are ignored by git. If `keystore.properties` is missing, release builds are signed with the debug key instead.

## Releasing

Run **tools/Release Note Pocket.bat** on a clean `main`. It asks for the new version, runs the tests and opens Notepad for the changelog: write what changed, save and close Notepad. It then bumps the version in `pubspec.yaml`, commits, tags `vX.Y.Z` and pushes. The workflow in `.github/workflows/release.yml` builds the Android, Windows and Linux apps and publishes them under Releases. Versions starting with `0.` are marked as pre-releases.

On Linux, run **tools/Release Note Pocket.sh** instead. It does the same steps, but opens the changelog in `$VISUAL`/`$EDITOR` (or Kate, VS Code or nano if neither is set) instead of Notepad.

Changelogs live in `fastlane/metadata/android/en-US/changelogs/<versionCode>.txt` (max 500 characters).

The workflow needs these repository secrets (GitHub > Settings > Secrets and variables > Actions):

- `KEYSTORE_BASE64`: the keystore file as base64. In PowerShell from the project root: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("$PWD\signing\release.jks")) | Set-Clipboard`
- `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`: the values from `signing/keystore.properties`
