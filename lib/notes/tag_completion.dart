// Terminal-style completion for the tag being typed in the tags field.
// The tag being typed is the word right before the cursor, with any leading "#" ignored.
// Tags that are longer than what's typed match. Their shared continuation is shown and filled in by Tab.
// With one match, Tab finishes the whole tag. With several, Tab only fills in the shared part,
// and the editor animates a marker after it to show that more than one tag continues from there.

import 'package:flutter/services.dart';

import 'note.dart';

final tagSeparatorCharacter = RegExp(r'[\s,]');

// typedStart and typedSpelling let Tab rewrite what was typed in the existing tag's spelling,
// so "#MU" becomes "#music" and still matches the #music tab.
class TagCompletion {
	const TagCompletion({
		required this.sharedPart,
		required this.endings,
		this.typedStart = 0,
		this.typedSpelling = '',
	});

	static const none = TagCompletion(sharedPart: '', endings: []);

	final String sharedPart;
	final List<String> endings;
	final int typedStart;
	final String typedSpelling;

	bool get isEmpty => endings.isEmpty;
	bool get hasOneMatch => endings.length == 1;
}

({int start, String word}) typedTagAt(String text, int cursor) {
	var start = cursor;
	while (start > 0 && !tagSeparatorCharacter.hasMatch(text[start - 1])) {
		start--;
	}
	return (start: start, word: text.substring(start, cursor).replaceFirst(leadingTagMarks, ''));
}

TagCompletion completeTag(TextEditingValue value, List<String> knownTags) {
	final cursor = value.selection.baseOffset;
	final isCursorAtEnd = value.selection.isCollapsed && cursor == value.text.length;
	if (!isCursorAtEnd) return TagCompletion.none;
	final typedTag = typedTagAt(value.text, cursor);
	final typed = typedTag.word;
	if (typed.isEmpty) return TagCompletion.none;

	final tagsInField = parseTagInput(value.text.substring(0, cursor - typed.length)).map((tag) => tag.toLowerCase()).toSet();
	final matches = [
		for (final tag in knownTags)
			if (tag.length > typed.length
				&& tag.toLowerCase().startsWith(typed.toLowerCase())
				&& !tagsInField.contains(tag.toLowerCase())) tag,
	];
	if (matches.isEmpty) return TagCompletion.none;

	final remainders = [for (final tag in matches) tag.substring(typed.length)];
	final sharedPart = sharedStart(remainders);
	return TagCompletion(
		sharedPart: sharedPart,
		endings: [for (final remainder in remainders) remainder.substring(sharedPart.length)],
		typedStart: typedTag.start,
		typedSpelling: '$tagMark${matches.first.substring(0, typed.length)}',
	);
}

// The text Tab inserts: the whole tag and a space when there's one match, otherwise the shared part.
TextEditingValue acceptTagCompletion(TextEditingValue value, TagCompletion completion) {
	final inserted = completion.hasOneMatch
		? '${completion.sharedPart}${completion.endings.single} '
		: completion.sharedPart;
	final text = value.text.replaceRange(completion.typedStart, value.text.length, completion.typedSpelling) + inserted;
	return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
}

String sharedStart(List<String> words) {
	var shared = words.first;
	for (final word in words.skip(1)) {
		var length = 0;
		while (length < shared.length && length < word.length && shared[length] == word[length]) {
			length++;
		}
		shared = shared.substring(0, length);
	}
	return shared;
}
