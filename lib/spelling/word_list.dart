// The words added with "add to dictionary", kept by the app itself: a plain dictionary.txt in the app's own
// data folder, one word per line. They are right in every language.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../notes/note.dart';

const wordListFileName = 'dictionary.txt';

class WordList {
	// With no file, nothing is kept between runs (used by tests)
	WordList([this.file, Iterable<String> words = const []]) : _words = {...words};

	final File? file;
	final Set<String> _words;

	static Future<WordList> openDefault() async {
		final appFolder = await getApplicationSupportDirectory();
		await appFolder.create(recursive: true);
		return read(File(p.join(appFolder.path, wordListFileName)));
	}

	static Future<WordList> read(File file) async {
		if (!await file.exists()) return WordList(file);
		final lines = splitLines(await file.readAsString()).map((line) => line.trim());
		return WordList(file, lines.where((line) => line.isNotEmpty));
	}

	List<String> get words {
		return _words.toList()..sort((first, second) => first.toLowerCase().compareTo(second.toLowerCase()));
	}

	// A word added in lowercase is also right with a capital, like at the start of a sentence
	bool contains(String word) => _words.contains(word) || _words.contains(word.toLowerCase());

	void add(String word) {
		if (_words.add(word)) _save();
	}

	void remove(String word) {
		if (_words.remove(word)) _save();
	}

	// Written at once, so quick changes can't end up in the wrong order
	void _save() => file?.writeAsStringSync(words.join(lineBreak));
}
