import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_pocket/notes/note.dart';
import 'package:note_pocket/notes/note_storage.dart';
import 'package:note_pocket/ui/ascii_widgets.dart';
import 'package:note_pocket/ui/checklist_controller.dart';
import 'package:note_pocket/ui/note_editor.dart';
import 'package:note_pocket/ui/terminal_theme.dart';

// The widths of the gaps drawn for tabs, in order
List<double> tabGaps(InlineSpan span) {
	final gaps = <double>[];
	span.visitChildren((child) {
		if (child is WidgetSpan && child.child is SizedBox) gaps.add((child.child as SizedBox).width!);
		return true;
	});
	return gaps;
}

TextStyle? styleOf(InlineSpan span, String text) {
	TextStyle? found;
	span.visitChildren((child) {
		if (child is TextSpan && child.text == text) found = child.style;
		return found == null;
	});
	return found;
}

void main() {
	// A tab is 4 columns wide, so 40 makes each column 10
	const tabWidth = 40.0;

	test('tabs reach to the next tab stop, so rows line up like in a text editor', () {
		expect(tabGaps(checklistSpan('a\tx\nabc\tx\nabcd\tx', tabWidth: tabWidth)), [30, 10, 40]);
	});

	test('characters drawn with no width are not counted towards tab stops', () {
		// "- " before a box is hidden, so "[ ] a" takes 5 columns and the tab fills 3
		expect(tabGaps(checklistSpan('- [ ] a\tx', tabWidth: tabWidth)), [30]);
		// The stars around bold text are hidden away from the cursor's line, and shown on it
		expect(tabGaps(checklistSpan('**a**\tx', tabWidth: tabWidth)), [30]);
		expect(tabGaps(checklistSpan('**a**\tx', tabWidth: tabWidth, lineWithMarksShown: 0)), [30]);
	});

	test('indents are still a whole tab each', () {
		expect(tabGaps(checklistSpan('\t\t- [ ] a', tabWidth: tabWidth)), [40, 40]);
	});

	test('checkboxes and bullets are drawn in the text color unless the note has a color', () {
		expect(styleOf(checklistSpan('- [ ] a', tabWidth: 0), '[ ]')?.color, terminalText);
		expect(styleOf(checklistSpan('\t- a', tabWidth: 0), bulletMarkFor(1))?.color, terminalText);
		final blue = titleColors['blue']!;
		expect(styleOf(checklistSpan('- [ ] a', tabWidth: 0, checkboxColor: blue), '[ ]')?.color, blue);
	});

	testWidgets('left from an item selects its box, and x checks it', (tester) async {
		final note = Note(file: File('List.txt'), content: '**List**\n- [ ] milk', modified: DateTime(2026));
		final editorKey = GlobalKey<NoteEditorState>();
		await tester.pumpWidget(MaterialApp(
			home: Scaffold(
				body: NoteEditor(key: editorKey, storage: NoteStorage(Directory.systemTemp), note: note, fillsSpace: true, onApply: () {}),
			),
		));
		await tester.pump(typingInterval * 10);
		final editor = editorKey.currentState!;
		final body = editor.bodyController;
		body.selection = const TextSelection.collapsed(offset: 6);
		await tester.pump();

		await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
		await tester.pump();
		expect(body.isBoxSelected, isTrue);

		await tester.sendKeyEvent(LogicalKeyboardKey.keyX, character: 'x');
		await tester.pump(checkboxFrameInterval * 5);
		expect(body.text, '- [x] milk');
		expect(body.isBoxSelected, isTrue);

		await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
		await tester.pump();
		expect(body.selection, const TextSelection.collapsed(offset: 6));
		editor.autosaveTimer?.cancel();
	});
}
