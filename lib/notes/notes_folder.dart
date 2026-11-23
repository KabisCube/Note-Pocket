// Where notes are stored.
// The default is Documents/NotePocket. A custom folder can be set in settings, which are kept
// as plain key=value lines in settings.ini in the app's own data folder.
// On Android, shared folders need storage access, asked for through a small native channel
// (MainActivity.kt). Notes from the old private app folder are copied over once.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'note.dart';
import 'note_storage.dart';

const notesFolderName = 'NotePocket';
const settingsFileName = 'settings.ini';
const settingSeparator = '=';
const storageChannel = MethodChannel('note_pocket/storage');

// Setting keys
const notesFolderKey = 'notes_folder';
const copiedPrivateNotesKey = 'copied_private_notes';
const tagColorKeyPrefix = 'tag_color.';
const themeKey = 'theme';
const accentColorKey = 'accent_color';
const fontSizeChangeKey = 'font_size_change';
const saveModeKey = 'save_mode';
const shortcutKeyPrefix = 'shortcut.';
const trueValue = 'true';
const manualSaveValue = 'manual';

class AppSettings {
	AppSettings(this.file, this._values);

	final File file;
	final Map<String, String> _values;

	static Future<AppSettings> load() async {
		final appFolder = await getApplicationSupportDirectory();
		await appFolder.create(recursive: true);
		return read(File(p.join(appFolder.path, settingsFileName)));
	}

	static Future<AppSettings> read(File file) async {
		final values = <String, String>{};
		if (await file.exists()) {
			for (final line in splitLines(await file.readAsString())) {
				final separatorIndex = line.indexOf(settingSeparator);
				if (separatorIndex > 0) values[line.substring(0, separatorIndex)] = line.substring(separatorIndex + 1);
			}
		}
		return AppSettings(file, values);
	}

	String? get notesFolder => _values[notesFolderKey];

	bool get hasCopiedPrivateNotes => _values[copiedPrivateNotesKey] == trueValue;

	Future<void> setNotesFolder(String? path) => _set(notesFolderKey, path);

	String? get theme => _values[themeKey];

	Future<void> setTheme(String themeName) => _set(themeKey, themeName);

	String? get accentColor => _values[accentColorKey];

	Future<void> setAccentColor(String colorName) => _set(accentColorKey, colorName);

	// Points added to (or taken from) the normal text size
	int get fontSizeChange => int.tryParse(_values[fontSizeChangeKey] ?? '') ?? 0;

	Future<void> setFontSizeChange(int change) => _set(fontSizeChangeKey, '$change');

	// Notes are saved automatically unless set to save only with the save shortcut
	bool get savesOnlyOnRequest => _values[saveModeKey] == manualSaveValue;

	Future<void> setSavesOnlyOnRequest(bool onlyOnRequest) => _set(saveModeKey, onlyOnRequest ? manualSaveValue : null);

	// Changed keyboard shortcuts in their saved form, by action name
	Map<String, String> get shortcuts => _valuesStartingWith(shortcutKeyPrefix);

	Future<void> setShortcut(String actionName, String? keys) => _set('$shortcutKeyPrefix$actionName', keys);

	Map<String, String> get tagColors => _valuesStartingWith(tagColorKeyPrefix);

	Map<String, String> _valuesStartingWith(String prefix) {
		return {
			for (final entry in _values.entries)
				if (entry.key.startsWith(prefix)) entry.key.substring(prefix.length): entry.value,
		};
	}

	Future<void> setTagColor(String tag, String? colorName) => _set('$tagColorKeyPrefix$tag', colorName);

	Future<void> markPrivateNotesCopied() => _set(copiedPrivateNotesKey, trueValue);

	Future<void> _set(String key, String? value) async {
		if (value == null) {
			_values.remove(key);
		} else {
			_values[key] = value;
		}
		final lines = [for (final entry in _values.entries) '${entry.key}$settingSeparator${entry.value}'];
		await file.writeAsString(lines.join(lineBreak));
	}
}

Future<String> defaultNotesFolder() async {
	final documentsPath = Platform.isAndroid
		? await storageChannel.invokeMethod<String>('documentsFolder')
		: (await getApplicationDocumentsDirectory()).path;
	return p.join(documentsPath!, notesFolderName);
}

// The app's private folder: where Android notes were kept before, and a fallback without storage access.
Future<String> privateNotesFolder() async {
	return p.join((await getApplicationDocumentsDirectory()).path, notesFolderName);
}

Future<bool> needsStorageAccess(String folderPath) async {
	if (!Platform.isAndroid || folderPath == await privateNotesFolder()) return false;
	return await storageChannel.invokeMethod<bool>('hasStorageAccess') != true;
}

Future<void> requestStorageAccess() => storageChannel.invokeMethod('requestStorageAccess');

Future<void> copyPrivateNotesOnce(AppSettings settings, String targetFolder) async {
	if (!Platform.isAndroid || settings.hasCopiedPrivateNotes) return;
	final privateFolder = Directory(await privateNotesFolder());
	if (privateFolder.path != targetFolder && await privateFolder.exists()) {
		await for (final entry in privateFolder.list()) {
			final isNote = entry is File && p.extension(entry.path) == noteExtension;
			final target = File(p.join(targetFolder, p.basename(entry.path)));
			if (isNote && !await target.exists()) await entry.copy(target.path);
		}
	}
	await settings.markPrivateNotesCopied();
}

Future<String?> checkUsableFolder(String folderPath) async {
	if (folderPath.trim().isEmpty) return 'enter a folder path';
	try {
		await Directory(folderPath).create(recursive: true);
		return null;
	} on FileSystemException catch (error) {
		return error.osError?.message ?? error.message;
	}
}

// A folder picked in the system's folder picker, as a path. Android gives a content:// address for
// folders on the phone's storage; those are turned back into paths, which the app can use with storage access.
// Null for folders that have no path, like ones in cloud storage apps.
const androidStorageProvider = 'com.android.externalstorage.documents';
const androidPrimaryStorage = 'primary';
const androidPrimaryStoragePath = '/storage/emulated/0';

String? folderPathFromUri(Uri uri) {
	if (uri.scheme == 'file') return uri.toFilePath();
	if (uri.scheme.isEmpty) return uri.path;
	if (uri.scheme != 'content' || uri.host != androidStorageProvider) return null;
	final treeIndex = uri.pathSegments.indexOf('tree');
	if (treeIndex == -1 || treeIndex + 1 >= uri.pathSegments.length) return null;
	final documentId = uri.pathSegments[treeIndex + 1];
	final separatorIndex = documentId.indexOf(':');
	if (separatorIndex == -1) return null;
	final volume = documentId.substring(0, separatorIndex);
	final volumePath = volume == androidPrimaryStorage ? androidPrimaryStoragePath : '/storage/$volume';
	final folder = documentId.substring(separatorIndex + 1);
	return folder.isEmpty ? volumePath : p.posix.join(volumePath, folder);
}
