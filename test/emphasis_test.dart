import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_pocket/notes/checklist_editing.dart';
import 'package:note_pocket/notes/emphasis_editing.dart';
import 'package:note_pocket/notes/note.dart';

// Selections are written with | at each end, or one | for a cursor
TextEditingValue parse(String marked) {
	final start = marked.indexOf('|');
	final end = marked.lastIndexOf('|');
	return TextEditingValue(
		text: marked.replaceAll('|', ''),
		selection: TextSelection(baseOffset: start, extentOffset: start == end ? start : end - 1),
	);
}

String show(TextEditingValue value) {
	final selection = value.selection;
	if (selection.isCollapsed) return value.text.replaceRange(selection.start, selection.start, '|');
	return value.text.replaceRange(selection.end, selection.end, '|').replaceRange(selection.start, selection.start, '|');
}

String toggled(String marked, String mark) => show(toggleEmphasis(parse(marked), mark));

void main() {
	test('selected text is made bold or italic, and back', () {
		expect(toggled('buy |milk| now', boldMark), 'buy **|milk|** now');
		expect(toggled('buy **|milk|** now', boldMark), 'buy |milk| now');
		expect(toggled('buy |milk |now', italicMark), 'buy *|milk|* now');
		expect(toggled('|*milk*|', italicMark), '|milk|');
	});

	test('bold and italic replace each other', () {
		expect(toggled('*|milk|*', boldMark), '**|milk|**');
		expect(toggled('|a *b* c|', boldMark), '**|a b c|**');
		expect(toggled('**mi|lk**', italicMark), '*mi|lk*');
	});

	test('the word around the cursor is used, or an empty pair is made', () {
		expect(toggled('buy mi|lk', boldMark), 'buy **mi|lk**');
		expect(toggled('**mi|lk**', boldMark), 'mi|lk');
		expect(toggled('buy |', italicMark), 'buy *|*');
		expect(toggled('buy *|*', italicMark), 'buy |');
		expect(toggled('buy **|**', boldMark), 'buy |');
		expect(toggled('**milk|**', boldMark), '**milk**|');
	});

	test('each selected line gets its own marks, after its checkbox', () {
		expect(toggled('|- [ ] a\n\n\t- b|', boldMark), '- [ ] **|a**\n\n\t- **b|**');
		expect(toggled('- [ ] **|a**\n\n\t- **b|**', boldMark), '- [ ] |a\n\n\t- b|');
	});

	test('checking a checkbox checks everything nested under it, unchecking only itself', () {
		const text = '- [ ] parent\n\t- [ ] child1\n\t\t- [ ] grandchild\n\t- [ ] child2\n- [ ] other';
		final checked = toggleCheckedAt(text, 0);
		expect(checked, '- [x] parent\n\t- [x] child1\n\t\t- [x] grandchild\n\t- [x] child2\n- [ ] other');
		expect(changedLineStarts(text, checked).length, 4);
		expect(toggleCheckedAt(checked, 0), checked.replaceFirst('[x]', '[ ]'));
		expect(
			toggleCheckedAt(text, 13),
			'- [ ] parent\n\t- [x] child1\n\t\t- [x] grandchild\n\t- [ ] child2\n- [ ] other',
		);
		final atParent = TextEditingValue(text: text, selection: const TextSelection.collapsed(offset: 8));
		expect(toggleCheckedLines(atParent).text, checked);
	});
}
