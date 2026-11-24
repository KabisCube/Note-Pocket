// Makes the selected text bold or italic, or plain again when it already is.
// - With nothing selected, the word around the cursor is used. Outside a word, an empty pair of marks
//   is added with the cursor inside. At the end of emphasized text, the cursor steps out of it.
// - The editor has no text that is both bold and italic, so one replaces the other.
// - Emphasis can't span lines, so several selected lines each get their own marks.

import 'dart:math';

import 'package:flutter/services.dart';

import 'checklist_editing.dart';
import 'note.dart';

final _wordCharacter = RegExp(r"[\p{L}\p{N}_'’-]", unicode: true);

TextEditingValue toggleEmphasis(TextEditingValue value, String mark) {
	if (!value.selection.isValid) return value;
	return value.selection.isCollapsed ? _toggleAtCursor(value, mark) : _toggleSelected(value, mark);
}

TextEditingValue _toggleAtCursor(TextEditingValue value, String mark) {
	final text = value.text;
	final cursor = value.selection.baseOffset;
	final line = lineAt(text, cursor);

	for (final match in _emphasisIn(text, line.start, line.end)) {
		if (cursor < match.start || cursor > match.end) continue;
		if (match.mark == mark && cursor == match.end - mark.length) return _withCursor(text, match.end);
		final isOnEdge = cursor == match.start || cursor == match.end;
		if (isOnEdge && match.mark != mark) continue;
		final newMark = match.mark == mark ? '' : mark;
		final inner = text.substring(match.start + match.mark.length, match.end - match.mark.length);
		final cursorInInner = (cursor - match.start - match.mark.length).clamp(0, inner.length);
		return _withCursor(
			text.replaceRange(match.start, match.end, '$newMark$inner$newMark'),
			match.start + newMark.length + cursorInInner,
		);
	}

	final starsBefore = RegExp(r'\**$').firstMatch(text.substring(line.start, cursor))![0]!.length;
	final starsAfter = RegExp(r'^\**').firstMatch(text.substring(cursor, line.end))![0]!.length;
	if (starsBefore == mark.length && starsAfter == mark.length) {
		return _withCursor(text.replaceRange(cursor - mark.length, cursor + mark.length, ''), cursor - mark.length);
	}

	var wordStart = cursor;
	var wordEnd = cursor;
	while (wordStart > line.start && _wordCharacter.hasMatch(text[wordStart - 1])) {
		wordStart--;
	}
	while (wordEnd < line.end && _wordCharacter.hasMatch(text[wordEnd])) {
		wordEnd++;
	}
	final isInWord = wordStart < cursor && wordEnd > cursor;
	if (!isInWord) wordStart = wordEnd = cursor;
	final word = text.substring(wordStart, wordEnd);
	return _withCursor(text.replaceRange(wordStart, wordEnd, '$mark$word$mark'), cursor + mark.length);
}

TextEditingValue _toggleSelected(TextEditingValue value, String mark) {
	final text = value.text;
	final parts = _selectedParts(text, value.selection);
	if (parts.isEmpty) return value;

	bool isAlready(({int start, int end}) part) => _emphasisIn(text, part.start, part.end)
		.any((match) => match.mark == mark && match.start <= part.start && match.end >= part.end);
	final newMark = parts.every(isAlready) ? '' : mark;

	// From the last part to the first, so the positions of earlier ones stay right
	var updated = text;
	var selectionStart = 0;
	var selectionEndFromEnd = 0;
	for (final (index, part) in parts.reversed.indexed) {
		final touched = _emphasisIn(text, part.start, part.end);
		final start = touched.fold(part.start, (first, match) => min(first, match.start));
		final end = touched.fold(part.end, (last, match) => max(last, match.end));
		var inner = text.substring(start, end);
		for (final match in touched.reversed) {
			final shown = text.substring(match.start + match.mark.length, match.end - match.mark.length);
			inner = inner.replaceRange(match.start - start, match.end - start, shown);
		}
		if (index == 0) selectionEndFromEnd = text.length - end + newMark.length;
		updated = updated.replaceRange(start, end, '$newMark$inner$newMark');
		selectionStart = start + newMark.length;
	}
	return TextEditingValue(
		text: updated,
		selection: TextSelection(baseOffset: selectionStart, extentOffset: updated.length - selectionEndFromEnd),
	);
}

// The selected part of each line, without list prefixes and the spaces around it. Empty ones are left out.
List<({int start, int end})> _selectedParts(String text, TextSelection selection) {
	final parts = <({int start, int end})>[];
	var lineStart = lineAt(text, selection.start).start;
	while (lineStart <= selection.end) {
		final lineEnd = lineAt(text, lineStart).end;
		var start = max(selection.start, lineStart + noteSyntax.prefixLength(editorLineAt(text, lineStart)));
		var end = min(selection.end, lineEnd);
		while (start < end && text[start].trim().isEmpty) {
			start++;
		}
		while (end > start && text[end - 1].trim().isEmpty) {
			end--;
		}
		if (start < end) parts.add((start: start, end: end));
		lineStart = lineEnd + lineBreak.length;
	}
	return parts;
}

// The emphasized text that the range touches, in order, as positions in the whole text.
List<({int start, int end, String mark})> _emphasisIn(String text, int rangeStart, int rangeEnd) {
	final line = lineAt(text, rangeStart);
	final contentStart = line.start + noteSyntax.prefixLength(editorLineAt(text, rangeStart));
	return [
		for (final match in emphasisPattern.allMatches(text.substring(contentStart, line.end)))
			if (contentStart + match.start < rangeEnd && contentStart + match.end > rangeStart)
				(start: contentStart + match.start, end: contentStart + match.end, mark: match[1]!),
	];
}

TextEditingValue _withCursor(String text, int cursor) {
	return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: cursor));
}
