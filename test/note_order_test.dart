import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_pocket/notes/note.dart';
import 'package:note_pocket/notes/note_order.dart';

Note noteNamed(String name, DateTime modified) {
	return Note(file: File('notes/$name.txt'), content: name, modified: modified);
}

void main() {
	test('saved order is kept and unknown notes go on top, newest first', () async {
		final folder = await Directory.systemTemp.createTemp('note_pocket_order');
		final order = NoteOrder(File('${folder.path}/$orderFileName'));
		final older = DateTime(2026);
		final newer = DateTime(2027);

		final first = noteNamed('first', older);
		final second = noteNamed('second', older);
		await order.save([second, first]);

		final newNote = noteNamed('new', newer);
		final newestNote = noteNamed('newest', newer.add(const Duration(days: 1)));
		final sorted = await order.sort([first, newNote, second, newestNote]);
		expect(sorted.map((note) => note.content), ['newest', 'new', 'second', 'first']);
		await folder.delete(recursive: true);
	});
}
