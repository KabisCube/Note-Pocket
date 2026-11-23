// Terminal-style completion for a folder path typed in settings, like the tags field's.
// The part after the last separator is matched against the folders in the folder before it.
// With one match, Tab fills in the whole name and a separator, ready for the next level.
// With several, Tab only fills in the part they share.
// Hidden folders (starting with ".") only match once a "." is typed. "~" stands for the home folder.
// Windows matches names in any case and accepts both / and \ as separators.

import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'tag_completion.dart';

const homeMark = '~';

class PathStyle {
	const PathStyle({required this.separator, required this.ignoresCase});

	static final current = PathStyle(separator: Platform.pathSeparator, ignoresCase: Platform.isWindows);

	final String separator;
	final bool ignoresCase;

	int lastSeparatorIn(String text) => max(text.lastIndexOf('/'), text.lastIndexOf(separator));
}

// The folder whose contents to match, as typed (with "~" and all), and the name being typed after it.
// Null when there is no folder before the name yet.
({String folder, String partial})? splitTypedPath(String typed, PathStyle style) {
	final last = style.lastSeparatorIn(typed);
	if (last == -1) return null;
	return (folder: typed.substring(0, last + 1), partial: typed.substring(last + 1));
}

String expandHome(String path, String? homeFolder, PathStyle style) {
	if (homeFolder == null) return path;
	if (path == homeMark) return homeFolder;
	if (path.startsWith('$homeMark/') || path.startsWith('$homeMark${style.separator}')) {
		return '$homeFolder${path.substring(homeMark.length)}';
	}
	return path;
}

String? get homeFolder => Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

TagCompletion completePath(TextEditingValue value, List<String> folderNames, PathStyle style) {
	final cursor = value.selection.baseOffset;
	final isCursorAtEnd = value.selection.isCollapsed && cursor == value.text.length;
	if (!isCursorAtEnd) return TagCompletion.none;
	final typed = splitTypedPath(value.text, style);
	if (typed == null) return TagCompletion.none;
	final partial = typed.partial;

	String comparable(String name) => style.ignoresCase ? name.toLowerCase() : name;
	final matches = [
		for (final name in folderNames)
			if (name.length > partial.length
				&& comparable(name).startsWith(comparable(partial))
				&& (!name.startsWith('.') || partial.startsWith('.'))) name,
	]..sort();
	// With nothing typed yet, only a folder that is the only one there is worth showing
	if (matches.isEmpty || (partial.isEmpty && matches.length > 1)) return TagCompletion.none;

	final remainders = [for (final name in matches) name.substring(partial.length)];
	final sharedPart = sharedStart(remainders);
	return TagCompletion(
		sharedPart: sharedPart,
		endings: [for (final remainder in remainders) remainder.substring(sharedPart.length)],
		typedStart: typed.folder.length,
		typedSpelling: matches.first.substring(0, partial.length),
	);
}

// The text Tab makes: the whole name and a separator with one match, otherwise the shared part.
TextEditingValue acceptPathCompletion(TextEditingValue value, TagCompletion completion, PathStyle style) {
	final inserted = completion.hasOneMatch
		? '${completion.sharedPart}${completion.endings.single}${style.separator}'
		: completion.sharedPart;
	final text = value.text.replaceRange(completion.typedStart, value.text.length, completion.typedSpelling) + inserted;
	return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
}

// The names of the folders in a folder, or none when it can't be read
Future<List<String>> folderNamesIn(String folderPath) async {
	final names = <String>[];
	try {
		await for (final entry in Directory(folderPath).list(followLinks: true)) {
			if (entry is Directory) names.add(p.basename(entry.path));
		}
		return names;
	} on FileSystemException {
		return const [];
	}
}
