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
const trueValue = 'true';

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

	Map<String, String> get tagColors {
		return {
			for (final entry in _values.entries)
				if (entry.key.startsWith(tagColorKeyPrefix)) entry.key.substring(tagColorKeyPrefix.length): entry.value,
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
