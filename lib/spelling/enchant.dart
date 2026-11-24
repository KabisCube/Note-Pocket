// Spell checking on Linux, through the Enchant library that most desktops come with.
// Enchant passes words on to whichever engine is installed (Aspell, Hunspell...).
// It is called straight from Dart (FFI), so nothing is bundled with the app, and without it there is
// just no spell checking. Enchant prints warnings about engines that aren't installed; they are harmless.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'spell_checker.dart';
import 'word_list.dart';

const enchantLibraryName = 'libenchant-2.so.2';
// KDE's own spell check settings, relative to the config folder
const kdeSpellSettingsPath = 'KDE/Sonnet.conf';
const _kdeLanguageKeys = ['defaultLanguage', 'preferredLanguages'];

typedef _Broker = Pointer<Void>;
typedef _Dictionary = Pointer<Void>;

class _Enchant {
	_Enchant(DynamicLibrary library)
		: initBroker = library.lookupFunction<_Broker Function(), _Broker Function()>('enchant_broker_init'),
			requestDictionary = library.lookupFunction<
				_Dictionary Function(_Broker, Pointer<Utf8>),
				_Dictionary Function(_Broker, Pointer<Utf8>)
			>('enchant_broker_request_dict'),
			check = library.lookupFunction<
				Int Function(_Dictionary, Pointer<Utf8>, IntPtr),
				int Function(_Dictionary, Pointer<Utf8>, int)
			>('enchant_dict_check'),
			suggest = library.lookupFunction<
				Pointer<Pointer<Utf8>> Function(_Dictionary, Pointer<Utf8>, IntPtr, Pointer<Size>),
				Pointer<Pointer<Utf8>> Function(_Dictionary, Pointer<Utf8>, int, Pointer<Size>)
			>('enchant_dict_suggest'),
			freeStrings = library.lookupFunction<
				Void Function(_Dictionary, Pointer<Pointer<Utf8>>),
				void Function(_Dictionary, Pointer<Pointer<Utf8>>)
			>('enchant_dict_free_string_list');

	final _Broker Function() initBroker;
	final _Dictionary Function(_Broker, Pointer<Utf8>) requestDictionary;
	final int Function(_Dictionary, Pointer<Utf8>, int) check;
	final Pointer<Pointer<Utf8>> Function(_Dictionary, Pointer<Utf8>, int, Pointer<Size>) suggest;
	final void Function(_Dictionary, Pointer<Pointer<Utf8>>) freeStrings;
}

class _EnchantDictionary implements SpellDictionary {
	_EnchantDictionary(this.enchant, this.dictionary, this.language);

	@override
	final String language;
	final _Enchant enchant;
	final _Dictionary dictionary;

	// Enchant answers 0 for a known word, above 0 for an unknown one, and below 0 for an error.
	// After an error the word counts as known, so nothing is marked by mistake.
	@override
	bool knows(String word) {
		return using((arena) {
			final text = word.toNativeUtf8(allocator: arena);
			return enchant.check(dictionary, text, text.length) <= 0;
		});
	}

	// The list belongs to Enchant, so it is copied and handed back
	@override
	List<String> suggestionsFor(String word) {
		return using((arena) {
			final text = word.toNativeUtf8(allocator: arena);
			final count = arena<Size>();
			final list = enchant.suggest(dictionary, text, text.length, count);
			if (list == nullptr) return const [];
			final suggestions = [for (var index = 0; index < count.value; index++) list[index].toDartString()];
			enchant.freeStrings(dictionary, list);
			return suggestions;
		});
	}
}

// The dictionaries live as long as the app, so they are never freed.
SpellChecker? openEnchant(List<String> languages, {WordList? addedWords}) {
	final _Enchant enchant;
	try {
		enchant = _Enchant(DynamicLibrary.open(enchantLibraryName));
	} on ArgumentError {
		return null;
	}
	final broker = enchant.initBroker();
	if (broker == nullptr) return null;
	final dictionaries = [
		for (final language in languages)
			if (_openDictionary(enchant, broker, language) case final dictionary?) dictionary,
	];
	return dictionaries.isEmpty ? null : SpellChecker(dictionaries, addedWords: addedWords);
}

// Enchant falls back from "sv_SE" to "sv" by itself.
SpellDictionary? _openDictionary(_Enchant enchant, _Broker broker, String language) {
	return using((arena) {
		final dictionary = enchant.requestDictionary(broker, language.toNativeUtf8(allocator: arena));
		return dictionary == nullptr ? null : _EnchantDictionary(enchant, dictionary, language);
	});
}

// The languages picked in KDE's spell check settings, or else the system's own languages.
Future<List<String>> linuxSpellLanguages(List<String> systemLanguages) async {
	final environment = Platform.environment;
	final configFolder = environment['XDG_CONFIG_HOME'] ?? '${environment['HOME']}/.config';
	try {
		final picked = kdeSpellLanguages(await File('$configFolder/$kdeSpellSettingsPath').readAsString());
		if (picked.isNotEmpty) return picked;
	} on FileSystemException {
		// Not on KDE, or never set there
	}
	return systemLanguages.toSet().toList();
}

List<String> kdeSpellLanguages(String settings) {
	final languages = <String>{};
	for (final line in settings.split('\n')) {
		final equals = line.indexOf('=');
		if (equals == -1 || !_kdeLanguageKeys.contains(line.substring(0, equals).trim())) continue;
		languages.addAll(line.substring(equals + 1).split(',').map((language) => language.trim()));
	}
	return languages.where((language) => language.isNotEmpty).toList();
}
