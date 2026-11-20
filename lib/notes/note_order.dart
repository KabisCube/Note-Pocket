// The order notes are dragged into is kept by the app, not in the notes folder:
// a plain order.txt in the app's own data folder, one note filename per line, top to bottom.
// Notes missing from the file (new or renamed outside the app) go to the top, newest first.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'note.dart';

const orderFileName = 'order.txt';

class NoteOrder {
	NoteOrder(this.file);

	final File file;

	static Future<NoteOrder> openDefault() async {
		final appFolder = await getApplicationSupportDirectory();
		await appFolder.create(recursive: true);
		return NoteOrder(File(p.join(appFolder.path, orderFileName)));
	}

	Future<List<Note>> sort(List<Note> notes) async {
		final positions = <String, int>{};
		for (final name in await _readNames()) {
			positions.putIfAbsent(name, () => positions.length);
		}

		final unordered = notes.where((note) => !positions.containsKey(_nameOf(note))).toList()
			..sort((a, b) => b.modified.compareTo(a.modified));
		final ordered = notes.where((note) => positions.containsKey(_nameOf(note))).toList()
			..sort((a, b) => positions[_nameOf(a)]!.compareTo(positions[_nameOf(b)]!));
		return [...unordered, ...ordered];
	}

	Future<void> save(List<Note> notes) async {
		await file.writeAsString(notes.map(_nameOf).join(lineBreak));
	}

	Future<List<String>> _readNames() async {
		if (!await file.exists()) return const [];
		return splitLines(await file.readAsString()).where((name) => name.isNotEmpty).toList();
	}

	String _nameOf(Note note) => p.basename(note.file.path);
}
