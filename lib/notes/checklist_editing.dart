// Editing rules for lists in the note body.
// The editor text is the same as the file text: checkboxes are "- [ ] " / "- [x] ", bullets are "- ",
// and indents are real tabs.
// ChecklistFormatter runs on every keystroke and handles:
// - Enter on a list line with text starts a new item of the same kind. On an empty item it
//   leaves the item and adds a plain line, which ends the list.
// - Deleting into a list prefix removes the whole prefix.
// - Typed or pasted "[] ", "[ ] " and space-indented list lines get normalized.
// - With a checkbox's box selected, x or space toggles it instead of replacing it.

import 'dart:math';

import 'package:flutter/services.dart';

import 'note.dart';

const checkboxBoxLength = 3;
// Typed on a selected checkbox box, these toggle it
const boxToggleCharacters = {'x', 'X', ' '};

String normalizeChecklists(String text) => splitLines(text).map(normalizeLine).join(lineBreak);

String normalizeLine(String rawLine) {
	final line = noteSyntax.parse(rawLine);
	return line.isListItem ? noteSyntax.format(line) : rawLine;
}

({int start, int end}) lineAt(String text, int offset) {
	final start = offset == 0 ? 0 : text.lastIndexOf(lineBreak, offset - 1) + 1;
	final nextBreak = text.indexOf(lineBreak, offset);
	return (start: start, end: nextBreak == -1 ? text.length : nextBreak);
}

NoteLine editorLineAt(String text, int offset) {
	final range = lineAt(text, offset);
	return noteSyntax.parse(text.substring(range.start, range.end));
}

// Only taps on the box itself count, not on the indent to its left.
// The "- " before the box is drawn with no width, so a tap anywhere in it is at the box's left edge.
int? checkboxLineStartAt(String text, int cursor) {
	final lineStart = lineAt(text, cursor).start;
	final line = editorLineAt(text, cursor);
	if (!line.isCheckbox) return null;
	final dashStart = lineStart + noteSyntax.indentLength(line);
	final boxStart = dashStart + bulletPrefix.length;
	final boxEnd = boxStart + checkboxBoxLength;
	final isOnBox = cursor > boxStart || (line.indent == 0 && cursor >= dashStart);
	return isOnBox && cursor <= boxEnd ? lineStart : null;
}

// The "[ ]" of the checkbox on the line starting at lineStart, or null when that line has no checkbox.
({int start, int end})? checkboxBoxAt(String text, int lineStart) {
	final line = editorLineAt(text, lineStart);
	if (!line.isCheckbox) return null;
	final start = lineStart + noteSyntax.indentLength(line) + bulletPrefix.length;
	return (start: start, end: start + checkboxBoxLength);
}

// The line start and box of a selection that covers exactly one checkbox's "[ ]", or null.
({int lineStart, int start, int end})? selectedCheckboxBox(TextEditingValue value) {
	final selection = value.selection;
	if (!selection.isValid || selection.isCollapsed) return null;
	final lineStart = lineAt(value.text, selection.start).start;
	final box = checkboxBoxAt(value.text, lineStart);
	if (box == null || selection.start != box.start || selection.end != box.end) return null;
	return (lineStart: lineStart, start: box.start, end: box.end);
}

// Keeps a collapsed cursor out of list prefixes, so they act like a single symbol.
// Left from the start of a checkbox item's text selects its box instead (typing x or space toggles it),
// and Left again goes on to the end of the line above. Right from the box goes back to the text.
// Returns the selection to use instead, or null to leave the cursor where it is.
TextSelection? selectionOutsidePrefix(String text, int cursor, TextSelection previous, {bool isTap = false}) {
	final lineStart = lineAt(text, cursor).start;
	final line = editorLineAt(text, cursor);
	final prefixEnd = lineStart + noteSyntax.prefixLength(line);
	if (!line.isListItem || cursor >= prefixEnd) return null;

	final atTextStart = TextSelection.collapsed(offset: prefixEnd);
	final lineAbove = lineStart > 0 ? TextSelection.collapsed(offset: lineStart - 1) : null;
	if (isTap) return atTextStart;

	final box = checkboxBoxAt(text, lineStart);
	final boxSelection = box == null ? null : TextSelection(baseOffset: box.start, extentOffset: box.end);
	final wasOnBox = box != null && previous.start == box.start && previous.end == box.end;
	if (wasOnBox) {
		final isMovingRight = cursor >= box.end;
		return isMovingRight ? atTextStart : (lineAbove ?? boxSelection);
	}

	final isMovingLeft = previous.isCollapsed && previous.baseOffset == prefixEnd && cursor == prefixEnd - 1;
	if (!isMovingLeft) return atTextStart;
	return boxSelection ?? lineAbove ?? atTextStart;
}

String toggleCheckedAt(String text, int lineStart) {
	final range = lineAt(text, lineStart);
	final line = editorLineAt(text, lineStart);
	return text.replaceRange(range.start, range.end, noteSyntax.format(line.toggled()));
}

// Checks the checkboxes on the selected lines, or unchecks them when they all already are checked.
// Other lines are left alone. Checked and unchecked boxes are the same length, so the selection stays.
TextEditingValue toggleCheckedLines(TextEditingValue value) {
	if (!value.selection.isValid) return value;
	final text = value.text;
	final range = _selectedLines(text, value.selection);
	final lines = text.substring(range.start, range.end).split(lineBreak).map(noteSyntax.parse).toList();
	final checkboxes = lines.where((line) => line.isCheckbox);
	if (checkboxes.isEmpty) return value;

	final newType = checkboxes.every((line) => line.isChecked) ? LineType.unchecked : LineType.checked;
	final updatedBlock = [
		for (final line in lines) line.isCheckbox ? noteSyntax.format(line.withType(newType)) : noteSyntax.format(line),
	].join(lineBreak);
	return value.copyWith(text: text.replaceRange(range.start, range.end, updatedBlock));
}

// Checks (or unchecks) every checkbox on the selected lines, as when one of them is clicked while
// several lines are selected. Returns the new text and the starts of the lines that changed.
// Checked and unchecked boxes are the same length, so line starts and the selection stay put.
({String text, List<int> changedLineStarts}) setCheckedLines(String text, TextSelection selection, {required bool checked}) {
	final range = _selectedLines(text, selection);
	final wantedType = checked ? LineType.checked : LineType.unchecked;
	final changedLineStarts = <int>[];
	final updatedLines = <String>[];
	var lineStart = range.start;
	for (final rawLine in text.substring(range.start, range.end).split(lineBreak)) {
		final line = noteSyntax.parse(rawLine);
		if (line.isCheckbox && line.type != wantedType) {
			changedLineStarts.add(lineStart);
			updatedLines.add(noteSyntax.format(line.withType(wantedType)));
		} else {
			updatedLines.add(rawLine);
		}
		lineStart += rawLine.length + lineBreak.length;
	}
	return (text: text.replaceRange(range.start, range.end, updatedLines.join(lineBreak)), changedLineStarts: changedLineStarts);
}

// Whether the line starting at lineStart is one of the lines the selection touches.
bool isLineSelected(String text, TextSelection selection, int lineStart) {
	final range = _selectedLines(text, selection);
	return lineStart >= range.start && lineStart <= range.end;
}

({int start, int end}) _selectedLines(String text, TextSelection selection) {
	return (start: lineAt(text, selection.start).start, end: lineAt(text, selection.end).end);
}

// Turns the selected lines into checkboxes or bullets, or back into plain text when they all
// already are that kind. With nothing selected yet, a new item is added at the end.
TextEditingValue toggleListType(TextEditingValue value, LineType listType) {
	final text = value.text;
	final newPrefix = noteSyntax.prefixFor(listType);
	if (!value.selection.isValid) {
		final separator = text.isEmpty ? '' : lineBreak;
		final updated = '$text$separator$newPrefix';
		return _valueWithCursor(updated, updated.length);
	}

	final range = _selectedLines(text, value.selection);
	final rawLines = text.substring(range.start, range.end).split(lineBreak);
	final isSeveralLines = rawLines.length > 1;
	bool isWanted(NoteLine line) => listType == LineType.bullet ? line.type == LineType.bullet : line.isCheckbox;
	final lines = rawLines.map(noteSyntax.parse).toList();
	final isAlreadyThatType = lines.every((line) => isWanted(line) || (isSeveralLines && line.text.trim().isEmpty));

	final updatedLines = [
		for (var index = 0; index < lines.length; index++)
			if (isSeveralLines && !lines[index].isListItem && lines[index].text.trim().isEmpty)
				rawLines[index]
			else if (isAlreadyThatType)
				'${tabIndent * lines[index].indent}${lines[index].text}'
			else
				noteSyntax.format(_asListItem(lines[index], listType)),
	];
	final updatedBlock = updatedLines.join(lineBreak);
	final updated = text.replaceRange(range.start, range.end, updatedBlock);

	if (isSeveralLines || !value.selection.isCollapsed) {
		return TextEditingValue(
			text: updated,
			selection: TextSelection(baseOffset: range.start, extentOffset: range.start + updatedBlock.length),
		);
	}
	final lengthChange = updatedBlock.length - (range.end - range.start);
	return _valueWithCursor(updated, max(range.start, value.selection.baseOffset + lengthChange));
}

NoteLine _asListItem(NoteLine line, LineType listType) {
	if (line.isListItem) return line.isCheckbox && listType != LineType.bullet ? line : line.withType(listType);
	final leadingTabs = RegExp('^$tabIndent*').firstMatch(line.text)![0]!;
	return NoteLine(listType, leadingTabs.length, line.text.substring(leadingTabs.length));
}

// Moves the selected lines one line up (-1) or down (+1), keeping the selection on them.
TextEditingValue moveLines(TextEditingValue value, int direction) {
	if (!value.selection.isValid) return value;
	final text = value.text;
	final range = _selectedLines(text, value.selection);
	final block = text.substring(range.start, range.end);

	if (direction < 0) {
		if (range.start == 0) return value;
		final previous = lineAt(text, range.start - 1);
		final previousLine = text.substring(previous.start, previous.end);
		final updated = text.replaceRange(previous.start, range.end, '$block$lineBreak$previousLine');
		return _shiftSelection(value, updated, -(previousLine.length + lineBreak.length));
	}

	if (range.end >= text.length) return value;
	final next = lineAt(text, range.end + 1);
	final nextLine = text.substring(next.start, next.end);
	final updated = text.replaceRange(range.start, next.end, '$nextLine$lineBreak$block');
	return _shiftSelection(value, updated, nextLine.length + lineBreak.length);
}

TextEditingValue _shiftSelection(TextEditingValue value, String updatedText, int shift) {
	return TextEditingValue(
		text: updatedText,
		selection: TextSelection(
			baseOffset: value.selection.baseOffset + shift,
			extentOffset: value.selection.extentOffset + shift,
		),
	);
}

TextEditingValue changeIndent(TextEditingValue value, int indentChange) {
	final cursor = value.selection.baseOffset;
	if (cursor < 0) return value;
	final text = value.text;
	final range = lineAt(text, cursor);
	final line = editorLineAt(text, cursor);
	if (!line.isListItem) return _changeTextIndent(value, range.start, indentChange);

	final newIndent = (line.indent + indentChange).clamp(0, _maxIndentBelow(text, range.start));
	if (newIndent == line.indent) return value;

	final updatedLine = noteSyntax.format(line.withIndent(newIndent));
	final lengthChange = updatedLine.length - (range.end - range.start);
	return _valueWithCursor(text.replaceRange(range.start, range.end, updatedLine), cursor + lengthChange);
}

TextEditingValue _changeTextIndent(TextEditingValue value, int lineStart, int indentChange) {
	final text = value.text;
	final selection = value.selection;
	if (indentChange > 0) {
		final updated = text.replaceRange(selection.start, selection.end, tabIndent);
		return _valueWithCursor(updated, selection.start + tabIndent.length);
	}
	if (!text.startsWith(tabIndent, lineStart)) return value;
	final updated = text.replaceRange(lineStart, lineStart + tabIndent.length, '');
	return _valueWithCursor(updated, max(lineStart, selection.baseOffset - tabIndent.length));
}

int _maxIndentBelow(String text, int lineStart) {
	if (lineStart == 0) return 0;
	final previousLine = editorLineAt(text, lineStart - 1);
	return previousLine.isListItem ? previousLine.indent + 1 : 0;
}

TextEditingValue _valueWithCursor(String text, int cursor) {
	return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: cursor));
}

class ChecklistFormatter extends TextInputFormatter {
	@override
	TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
		return _typeOnSelectedBox(oldValue, newValue)
			?? _continueListOnEnter(oldValue, newValue)
			?? _removePrefixOnDelete(oldValue, newValue)
			?? _convertTypedPrefixes(newValue);
	}

	// With a checkbox's box selected, typing never replaces the box:
	// x or space toggles it, deleting removes the whole prefix, and anything else is typed at the start of the text.
	// (On desktop, x and space are caught as keys before this, so the toggle can animate.)
	TextEditingValue? _typeOnSelectedBox(TextEditingValue oldValue, TextEditingValue newValue) {
		final box = selectedCheckboxBox(oldValue);
		if (box == null || newValue.text == oldValue.text) return null;
		final oldText = oldValue.text;
		final before = oldText.substring(0, box.start);
		final after = oldText.substring(box.end);
		final newText = newValue.text;
		if (newText.length < before.length + after.length || !newText.startsWith(before) || !newText.endsWith(after)) return null;

		final typed = newText.substring(before.length, newText.length - after.length);
		final line = editorLineAt(oldText, box.lineStart);
		final prefixEnd = box.lineStart + noteSyntax.prefixLength(line);
		if (boxToggleCharacters.contains(typed)) {
			return TextEditingValue(
				text: toggleCheckedAt(oldText, box.lineStart),
				selection: TextSelection(baseOffset: box.start, extentOffset: box.end),
			);
		}
		if (typed.isEmpty) return _valueWithCursor(oldText.replaceRange(box.lineStart, prefixEnd, ''), box.lineStart);
		if (typed.contains(lineBreak)) return _valueWithCursor(oldText, prefixEnd);
		return _valueWithCursor(oldText.replaceRange(prefixEnd, prefixEnd, typed), prefixEnd + typed.length);
	}

	TextEditingValue? _continueListOnEnter(TextEditingValue oldValue, TextEditingValue newValue) {
		final newlineIndex = _singleInsertionIndex(oldValue, newValue);
		final text = newValue.text;
		if (newlineIndex == null || text[newlineIndex] != lineBreak) return null;

		final lineStart = lineAt(text, newlineIndex).start;
		final line = noteSyntax.parse(text.substring(lineStart, newlineIndex));
		if (!line.isListItem || line.text.isEmpty) return null;

		final nextLineStart = newlineIndex + 1;
		final nextType = line.isCheckbox ? LineType.unchecked : line.type;
		final newPrefix = noteSyntax.format(NoteLine(nextType, line.indent, ''));
		final updated = text.replaceRange(nextLineStart, nextLineStart, newPrefix);
		return _valueWithCursor(updated, nextLineStart + newPrefix.length);
	}

	TextEditingValue? _removePrefixOnDelete(TextEditingValue oldValue, TextEditingValue newValue) {
		final deletedIndex = _singleDeletionIndex(oldValue, newValue);
		if (deletedIndex == null) return null;
		final text = oldValue.text;

		if (text[deletedIndex] == lineBreak) {
			final nextLineStart = deletedIndex + 1;
			final nextLine = editorLineAt(text, nextLineStart);
			if (!nextLine.isListItem) return null;
			final updated = text.replaceRange(deletedIndex, nextLineStart + noteSyntax.prefixLength(nextLine), '');
			return _valueWithCursor(updated, deletedIndex);
		}

		final lineStart = lineAt(text, deletedIndex).start;
		final prefixLength = noteSyntax.prefixLength(editorLineAt(text, deletedIndex));
		if (deletedIndex - lineStart >= prefixLength) return null;
		return _valueWithCursor(text.replaceRange(lineStart, lineStart + prefixLength, ''), lineStart);
	}

	TextEditingValue _convertTypedPrefixes(TextEditingValue newValue) {
		final cursor = newValue.selection.baseOffset;
		final convertedLines = <String>[];
		var cursorShift = 0;
		var lineStart = 0;

		for (final rawLine in newValue.text.split(lineBreak)) {
			final converted = normalizeLine(rawLine);
			if (cursor > lineStart) cursorShift += converted.length - rawLine.length;
			convertedLines.add(converted);
			lineStart += rawLine.length + lineBreak.length;
		}

		if (cursorShift == 0 && convertedLines.join(lineBreak) == newValue.text) return newValue;
		return _valueWithCursor(convertedLines.join(lineBreak), cursor + cursorShift);
	}

	int? _singleInsertionIndex(TextEditingValue oldValue, TextEditingValue newValue) {
		final cursor = newValue.selection.baseOffset;
		final isOneLonger = newValue.text.length == oldValue.text.length + 1;
		if (!isOneLonger || !newValue.selection.isCollapsed || cursor < 1) return null;
		final index = cursor - 1;
		final isSingleInsertion = newValue.text.substring(0, index) == oldValue.text.substring(0, index)
			&& newValue.text.substring(cursor) == oldValue.text.substring(index);
		return isSingleInsertion ? index : null;
	}

	int? _singleDeletionIndex(TextEditingValue oldValue, TextEditingValue newValue) {
		final index = newValue.selection.baseOffset;
		final isOneShorter = newValue.text.length == oldValue.text.length - 1;
		if (!isOneShorter || !newValue.selection.isCollapsed || index < 0) return null;
		final isSingleDeletion = oldValue.text.substring(0, index) == newValue.text.substring(0, index)
			&& oldValue.text.substring(index + 1) == newValue.text.substring(index);
		return isSingleDeletion ? index : null;
	}
}
