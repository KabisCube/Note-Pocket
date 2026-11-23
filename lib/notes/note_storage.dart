import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'note.dart';

const noteExtension = '.txt';
const maxFileNameLength = 100;
final invalidFileNameCharacters = RegExp(r'[<>:"/\\|?*\x00-\x1F]');
final trailingDots = RegExp(r'\.+$');

String fileNameForTitle(String title) {
	var name = title.replaceAll(invalidFileNameCharacters, '').trim();
	if (name.length > maxFileNameLength) {
		name = name.substring(0, maxFileNameLength);
	}
	name = name.replaceAll(trailingDots, '').trim();
	return name.isEmpty ? untitledName : name;
}

class NoteStorage {
	NoteStorage(this.folder);

	final Directory folder;

	static Future<NoteStorage> open(String folderPath) async {
		final folder = Directory(folderPath);
		await folder.create(recursive: true);
		return NoteStorage(folder);
	}

	Future<List<Note>> loadAll() async {
		final entries = await folder.list().toList();
		final noteFiles = entries
			.whereType<File>()
			.where((file) => p.extension(file.path).toLowerCase() == noteExtension);
		final notes = [for (final file in noteFiles) await _read(file)];
		notes.sort((a, b) => b.modified.compareTo(a.modified));
		return notes;
	}

	Future<Note> save(Note? existing, String content) async {
		final targetFile = _availableFile(fileNameForTitle(titleOf(content)), existing?.file);
		var file = existing?.file ?? targetFile;
		await file.writeAsString(content);
		if (file.path != targetFile.path) {
			file = await file.rename(targetFile.path);
		}
		return Note(file: file, content: content, modified: DateTime.now());
	}

	// A file that is already gone (removed outside the app) counts as deleted
	Future<void> delete(Note note) async {
		try {
			await note.file.delete();
		} on PathNotFoundException {
			return;
		}
	}

	Future<Note?> findSameNamed(String content) async {
		final namedFile = _fileFor(fileNameForTitle(titleOf(content)));
		return namedFile.existsSync() ? _read(namedFile) : null;
	}

	Future<Note> saveReceived(String content) async {
		final namedFile = _fileFor(fileNameForTitle(titleOf(content)));
		if (!namedFile.existsSync()) return save(null, content);
		await namedFile.writeAsString(content);
		return Note(file: namedFile, content: content, modified: DateTime.now());
	}

	File _fileFor(String fileName) => File(p.join(folder.path, '$fileName$noteExtension'));

	Future<Note> _read(File file) async {
		final bytes = await file.readAsBytes();
		return Note(
			file: file,
			content: utf8.decode(bytes, allowMalformed: true),
			modified: await file.lastModified(),
		);
	}

	File _availableFile(String baseName, File? currentFile) {
		var copyNumber = 1;
		while (true) {
			final suffix = copyNumber == 1 ? '' : ' ($copyNumber)';
			final candidate = _fileFor('$baseName$suffix');
			if (_isSameFile(candidate, currentFile) || !candidate.existsSync()) {
				return candidate;
			}
			copyNumber++;
		}
	}

	bool _isSameFile(File candidate, File? currentFile) {
		if (currentFile == null) return false;
		if (Platform.isWindows) {
			return candidate.path.toLowerCase() == currentFile.path.toLowerCase();
		}
		return candidate.path == currentFile.path;
	}
}
