// Finds misspelled words. A word is right when any of the dictionaries knows it, so notes can mix languages.
// Things that aren't ordinary words are left alone: links, paths, tags, names like "fooBar" or "v2",
// abbreviations in capitals, and single letters.

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'word_list.dart';

const maxSuggestions = 5;

abstract class SpellDictionary {
	// Like "sv_SE"
	String get language;

	bool knows(String word);

	// Best first
	List<String> suggestionsFor(String word);
}

// What the app checks with, set at startup. Null when the system has no spell checker or no dictionaries.
SpellChecker? systemSpellChecker;

final _token = RegExp(r'\S+');
final _notProse = RegExp(r'[\d/\\@#_=<>|~]|\w\.\w', unicode: true);
final _word = RegExp(r"\p{L}[\p{L}\p{M}]*(?:['’][\p{L}\p{M}]+)*", unicode: true);
final _innerCapital = RegExp(r'.\p{Lu}', unicode: true);

// Tells its listeners when a word is added or removed, or when it is turned on or off.
class SpellChecker extends ChangeNotifier {
	SpellChecker(this.dictionaries, {WordList? addedWords}) : addedWords = addedWords ?? WordList();

	final List<SpellDictionary> dictionaries;
	final WordList addedWords;
	bool _isOn = true;

	bool get isOn => _isOn;

	set isOn(bool value) {
		_isOn = value;
		notifyListeners();
	}

	// For each word looked up, the languages that know it
	final Map<String, Set<String>> _languagesByWord = {};

	bool isCorrect(String word) => addedWords.contains(_plain(word)) || _languagesKnowing(word).isNotEmpty;

	Set<String> _languagesKnowing(String word) {
		return _languagesByWord.putIfAbsent(word, () => {
			for (final dictionary in dictionaries)
				if (dictionary.knows(_plain(word))) _languageOf(dictionary),
		});
	}

	// Without the country, so kinds of English count as one language
	String _languageOf(SpellDictionary dictionary) => dictionary.language.split('_').first;

	String _plain(String word) => word.replaceAll('’', "'");

	// The languages that know the most words in the text: just one, unless it is too close to tell.
	Set<String> languagesOf(String text) {
		final counts = {for (final dictionary in dictionaries) _languageOf(dictionary): 0};
		for (final word in _wordsIn(text)) {
			for (final language in _languagesKnowing(text.substring(word.start, word.end))) {
				counts[language] = counts[language]! + 1;
			}
		}
		final most = counts.values.fold(0, max);
		return {
			for (final entry in counts.entries)
				if (entry.value == most) entry.key,
		};
	}

	// Suggestions in the language the word is written in, closest to the word first. The language is
	// the one of the first context (like the word's line, then the whole note) that is clearly in one.
	// With none, every language is used. Equally close suggestions keep the dictionaries' own order, taking turns.
	List<String> suggestionsFor(String word, {List<String> contexts = const []}) {
		final plainWord = _plain(word);
		final language = contexts
			.map(languagesOf)
			.where((languages) => languages.length == 1)
			.map((languages) => languages.single)
			.firstOrNull;
		final inLanguage = _suggestionsFrom(
			dictionaries.where((dictionary) => language == null || _languageOf(dictionary) == language),
			plainWord,
		);
		return inLanguage.isEmpty ? _suggestionsFrom(dictionaries, plainWord) : inLanguage;
	}

	List<String> _suggestionsFrom(Iterable<SpellDictionary> sources, String word) {
		final lists = [for (final dictionary in sources) dictionary.suggestionsFor(word)];
		final longest = lists.fold(0, (length, list) => max(length, list.length));
		final suggestions = {
			for (var index = 0; index < longest; index++)
				for (final list in lists)
					if (index < list.length) list[index],
		};
		final distances = {
			for (final suggestion in suggestions) suggestion: editDistance(word.toLowerCase(), suggestion.toLowerCase()),
		};
		final sorted = suggestions.toList();
		mergeSort(sorted, compare: (first, second) => distances[first]!.compareTo(distances[second]!));
		return sorted.take(maxSuggestions).toList();
	}

	void add(String word) {
		addedWords.add(_plain(word));
		notifyListeners();
	}

	void remove(String word) {
		addedWords.remove(word);
		notifyListeners();
	}

	// The misspelled words in a text, as positions in it.
	List<({int start, int end})> misspelledIn(String text) {
		if (!isOn) return const [];
		return [
			for (final word in _wordsIn(text))
				if (!isCorrect(text.substring(word.start, word.end))) word,
		];
	}

	// The ordinary words in a text
	Iterable<({int start, int end})> _wordsIn(String text) sync* {
		for (final token in _token.allMatches(text)) {
			if (_notProse.hasMatch(token[0]!)) continue;
			for (final word in _word.allMatches(token[0]!)) {
				if (word[0]!.length == 1 || _innerCapital.hasMatch(word[0]!)) continue;
				yield (start: token.start + word.start, end: token.start + word.end);
			}
		}
	}
}

// How many letters have to be added, removed or replaced to turn one word into the other.
// Each row holds the distances from the first letters of "from" to every start of "to".
int editDistance(String from, String to) {
	var row = [for (var length = 0; length <= to.length; length++) length];
	for (var fromIndex = 0; fromIndex < from.length; fromIndex++) {
		final nextRow = [fromIndex + 1];
		for (var toIndex = 0; toIndex < to.length; toIndex++) {
			final replaced = row[toIndex] + (from[fromIndex] == to[toIndex] ? 0 : 1);
			nextRow.add(min(replaced, min(row[toIndex + 1], nextRow[toIndex]) + 1));
		}
		row = nextRow;
	}
	return row.last;
}
