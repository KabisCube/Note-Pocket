import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_pocket/notes/tag_completion.dart';
import 'package:note_pocket/ui/tags_view.dart';

const knownTags = ['music', 'work', 'workshop', 'world'];

TextEditingValue typed(String text) {
	return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
}

void main() {
	test('one match completes to the rest of the tag', () {
		final completion = completeTag(typed('#mu'), knownTags);
		expect(completion.hasOneMatch, isTrue);
		expect(completion.sharedPart, 'sic');
		expect(acceptTagCompletion(typed('#mu'), completion).text, '#music ');
		expect(acceptTagCompletion(typed('mu'), completeTag(typed('mu'), knownTags)).text, '#music ');
	});

	test('several matches fill in only the part they share', () {
		final completion = completeTag(typed('#wo'), knownTags);
		expect(completion.hasOneMatch, isFalse);
		expect(completion.sharedPart, 'r');
		expect(acceptTagCompletion(typed('#wo'), completion).text, '#wor');
	});

	test('work and workout: tab fills in "rk", then "out" completes on its own', () {
		const tags = ['work', 'workout'];
		final first = completeTag(typed('#wo'), tags);
		expect(first.sharedPart, 'rk');
		expect(first.hasOneMatch, isFalse);
		final afterFirstTab = acceptTagCompletion(typed('#wo'), first);
		expect(afterFirstTab.text, '#work');

		final second = completeTag(afterFirstTab, tags);
		expect(second.hasOneMatch, isTrue);
		expect(second.sharedPart, 'out');
		expect(acceptTagCompletion(afterFirstTab, second).text, '#workout ');
	});

	test('tags already in the field, finished tags and unknown words are not completed', () {
		expect(completeTag(typed('#music #mu'), knownTags).isEmpty, isTrue);
		expect(completeTag(typed('#music '), knownTags).isEmpty, isTrue);
		expect(completeTag(typed('#music'), knownTags).isEmpty, isTrue);
		expect(completeTag(typed('#zz'), knownTags).isEmpty, isTrue);
	});

	test('matching ignores case but keeps the tag spelling', () {
		final completion = completeTag(typed('#MU'), knownTags);
		expect(acceptTagCompletion(typed('#MU'), completion).text, '#music ');
	});

	test('the tag under the cursor is found for its color menu', () {
		TextEditingValue cursorIn(String text, int offset) {
			return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: offset));
		}

		expect(tagAtCursor(cursorIn('#work #music', 2)), 'work');
		expect(tagAtCursor(cursorIn('#work #music', 8)), 'music');
		expect(tagAtCursor(cursorIn('#work #music', 12)), 'music');
		expect(tagAtCursor(cursorIn('', 0)), isNull);
	});
}
