import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_pocket/notes/checklist_editing.dart';
import 'package:note_pocket/notes/note.dart';
import 'package:note_pocket/notes/note_storage.dart';

TextEditingValue cursorAt(String text, int offset) {
	return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: offset));
}

TextEditingValue typeEdit(TextEditingValue before, TextEditingValue after) {
	return ChecklistFormatter().formatEditUpdate(before, after);
}

void main() {
	group('file syntax', () {
		test('checkboxes only match at line start', () {
			expect(noteSyntax.parse('- [ ] bread').type, LineType.unchecked);
			expect(noteSyntax.parse('- [ ] bread').text, 'bread');
			expect(noteSyntax.parse('- [x] milk').type, LineType.checked);
			expect(noteSyntax.parse('- bread').type, LineType.bullet);
			expect(noteSyntax.parse('xavier').type, LineType.text);
			expect(noteSyntax.parse('a - [ ] b').type, LineType.text);
		});

		test('older and shorthand checkboxes are still read', () {
			expect(noteSyntax.parse('[ ] bread').type, LineType.unchecked);
			expect(noteSyntax.parse('[] bread').type, LineType.unchecked);
			expect(noteSyntax.parse('- [] bread').type, LineType.unchecked);
			expect(noteSyntax.parse('[x] milk').type, LineType.checked);
			expect(noteSyntax.parse('[X] milk').type, LineType.checked);
			expect(noteSyntax.parse('- [X] milk').text, 'milk');
		});

		test('tabs and 4 spaces both indent', () {
			expect(noteSyntax.parse('\t- [ ] child').indent, 1);
			expect(noteSyntax.parse('    - [ ] child').indent, 1);
			expect(noteSyntax.parse('\t\t- [x] grandchild').indent, 2);
		});

		test('normalizing keeps tabs and fixes space-indented and short checkboxes', () {
			const file = 'Intro\n\tplain\n- [ ] parent\n\t- [x] child';
			expect(normalizeChecklists(file), file);
			expect(normalizeChecklists('    [] child'), '\t- [ ] child');
			expect(normalizeChecklists('[x] a\n[ ] b'), '- [x] a\n- [ ] b');
			expect(normalizeChecklists('    plain'), '    plain');
		});
	});

	group('title', () {
		test('comes from first line', () {
			expect(titleOf('Groceries\n[ ] bread'), 'Groceries');
			expect(titleOf(''), untitledName);
		});

		test('splits and joins back to the same text', () {
			const content = 'Groceries\n- [ ] bread\n- [x] milk';
			final parts = splitTitle(content);
			expect(parts.body, '- [ ] bread\n- [x] milk');
			expect(joinTitle(parts.title, parts.body), content);
		});

		test('color at end of title is read and left out of the title', () {
			expect(parseTitle('fix songs: @green'), (text: 'fix songs:', color: 'green'));
			expect(parseTitle('fix songs: #green'), (text: 'fix songs:', color: 'green'));
			expect(parseTitle('#1 priority'), (text: '#1 priority', color: null));
			expect(parseTitle('tasks @notacolor'), (text: 'tasks @notacolor', color: null));
			expect(titleOf('fix songs: @green\n[ ] a'), 'fix songs:');
			expect(formatTitle('fix songs:', 'green'), '**fix songs:** @green');
			expect(formatTitle('fix songs:', null), '**fix songs:**');
		});

		test('the title is saved between bold stars and read without them', () {
			expect(parseTitle('**fix songs** @green'), (text: 'fix songs', color: 'green'));
			expect(parseTitle('**fix songs**'), (text: 'fix songs', color: null));
			expect(parseTitle('*fix songs*'), (text: 'fix songs', color: null));
			expect(titleOf('**Groceries**\n- [ ] bread'), 'Groceries');
			expect(formatTitle('  ', null), '');
		});

		test('bold and italic text are found between stars only when they touch the text', () {
			final matches = emphasisPattern.allMatches('buy **milk** and 2 * 3 * 4 *a* **b**').map((match) => match[0]).toList();
			expect(matches, ['**milk**', '*a*', '**b**']);
		});

		test('tags are read from the last line only', () {
			final tagged = splitTags('[ ] a\n#work #music');
			expect(tagged.body, '[ ] a');
			expect(tagged.tags, ['work', 'music']);
			expect(splitTags('#work').body, '');
			expect(splitTags('#work').tags, ['work']);
			expect(splitTags('#work\nmore text').tags, isEmpty);
			expect(splitTags('# heading').tags, isEmpty);
			expect(splitTags('a\n#1 priority').tags, isEmpty);
			expect(joinTags('[ ] a', ['work', 'music']), '[ ] a\n#work #music');
			expect(joinTags('[ ] a', []), '[ ] a');
			expect(parseTagInput('work, #music  ##home'), ['work', 'music', 'home']);
		});

		test('a color typed after a tag is read and left out of the tag', () {
			expect(parseTagInput('#work@yellow #home'), ['work', 'home']);
			expect(typedTagColors('#work@yellow #home #me@notacolor'), {'work': 'yellow'});
			expect(parseTagInput('#me@notacolor'), ['me@notacolor']);
		});

		test('file names drop invalid characters', () {
			expect(fileNameForTitle('a/b:c?'), 'abc');
			expect(fileNameForTitle('...'), untitledName);
		});
	});

	group('editing', () {
		test('enter on a checkbox starts a new checkbox', () {
			final result = typeEdit(cursorAt('- [ ] milk', 10), cursorAt('- [ ] milk\n', 11));
			expect(result.text, '- [ ] milk\n- [ ] ');
			expect(result.selection.baseOffset, 17);
		});

		test('enter keeps child indent', () {
			final result = typeEdit(cursorAt('\t- [ ] a', 8), cursorAt('\t- [ ] a\n', 9));
			expect(result.text, '\t- [ ] a\n\t- [ ] ');
		});

		test('enter on an empty checkbox keeps it and adds a plain line', () {
			final result = typeEdit(cursorAt('- [ ] a\n\t- [ ] ', 15), cursorAt('- [ ] a\n\t- [ ] \n', 16));
			expect(result.text, '- [ ] a\n\t- [ ] \n');
		});

		test('backspace at checkbox text start removes the checkbox', () {
			final result = typeEdit(cursorAt('- [ ] milk', 6), cursorAt('- [ ]milk', 5));
			expect(result.text, 'milk');
			expect(result.selection.baseOffset, 0);
		});

		test('typing [] becomes a checkbox', () {
			final result = typeEdit(cursorAt('[]', 2), cursorAt('[] ', 3));
			expect(result.text, '- [ ] ');
			expect(result.selection.baseOffset, 6);
		});

		test('tab indents below a checkbox, at most one level deeper', () {
			final once = changeIndent(cursorAt('- [ ] a\n- [ ] b', 15), 1);
			expect(once.text, '- [ ] a\n\t- [ ] b');
			expect(changeIndent(once, 1).text, once.text);
			expect(changeIndent(once, -1).text, '- [ ] a\n- [ ] b');
		});

		test('tab indents plain lines too', () {
			final indented = changeIndent(cursorAt('notes', 0), 1);
			expect(indented.text, '\tnotes');
			expect(changeIndent(indented, -1).text, 'notes');
		});

		test('checkbox button converts the current line', () {
			expect(toggleListType(cursorAt('milk', 4), LineType.unchecked).text, '- [ ] milk');
			expect(toggleListType(cursorAt('- [ ] milk', 10), LineType.unchecked).text, 'milk');
		});

		test('cursor is kept out of the checkbox prefix', () {
			const nowhere = TextSelection.collapsed(offset: 0);
			expect(selectionOutsidePrefix('- [ ] milk', 1, nowhere), const TextSelection.collapsed(offset: 6));
			expect(selectionOutsidePrefix('- [ ] milk', 8, const TextSelection.collapsed(offset: 7)), null);
			expect(selectionOutsidePrefix('a\n- milk', 3, const TextSelection.collapsed(offset: 4)), const TextSelection.collapsed(offset: 1));
		});

		test('left from the text selects the box, then goes on to the line above', () {
			const text = 'a\n- [ ] milk';
			const box = TextSelection(baseOffset: 4, extentOffset: 7);
			expect(selectionOutsidePrefix(text, 7, const TextSelection.collapsed(offset: 8)), box);
			expect(selectionOutsidePrefix(text, 4, box), const TextSelection.collapsed(offset: 1));
			expect(selectionOutsidePrefix(text, 7, box), const TextSelection.collapsed(offset: 8));
			expect(selectionOutsidePrefix(text, 7, const TextSelection.collapsed(offset: 8), isTap: true), const TextSelection.collapsed(offset: 8));
		});

		test('typing on a selected box toggles it or types into the text', () {
			const box = TextEditingValue(text: '- [ ] milk', selection: TextSelection(baseOffset: 2, extentOffset: 5));
			// What the text field sends: the selected "[ ]" replaced by what was typed
			TextEditingValue typed(String character) => ChecklistFormatter().formatEditUpdate(
				box,
				TextEditingValue(
					text: box.text.replaceRange(2, 5, character),
					selection: TextSelection.collapsed(offset: 2 + character.length),
				),
			);
			expect(typed('x').text, '- [x] milk');
			expect(typed('x').selection, box.selection);
			expect(typed(' ').text, '- [x] milk');
			expect(typed('o').text, '- [ ] omilk');
			expect(typed('').text, 'milk');
		});

		test('clicking a box in a selection sets every selected box the same way', () {
			const text = '- [ ] a\nnote\n- [x] b\n- [ ] c';
			final updated = setCheckedLines(text, const TextSelection(baseOffset: 0, extentOffset: 17), checked: true);
			expect(updated.text, '- [x] a\nnote\n- [x] b\n- [ ] c');
			expect(updated.changedLineStarts, [0]);
		});

		test('toggling checks and unchecks', () {
			expect(toggleCheckedAt('a\n- [ ] milk', 2), 'a\n- [x] milk');
			expect(toggleCheckedAt('- [x] milk', 0), '- [ ] milk');
		});

		test('the shortcut toggles the checkbox on the cursor line', () {
			final checked = toggleCheckedLines(cursorAt('a\n- [ ] milk', 5));
			expect(checked.text, 'a\n- [x] milk');
			expect(checked.selection.baseOffset, 5);
			expect(toggleCheckedLines(checked).text, 'a\n- [ ] milk');
			expect(toggleCheckedLines(cursorAt('plain', 2)).text, 'plain');
		});

		test('the shortcut checks all selected checkboxes, or unchecks them when all are checked', () {
			const text = '- [x] a\nplain\n\t- [ ] b';
			final selected = TextEditingValue(
				text: text,
				selection: const TextSelection(baseOffset: 0, extentOffset: text.length),
			);
			final allChecked = toggleCheckedLines(selected);
			expect(allChecked.text, '- [x] a\nplain\n\t- [x] b');
			expect(toggleCheckedLines(allChecked).text, '- [ ] a\nplain\n\t- [ ] b');
		});

		test('bullets start with "- " and continue on enter like checkboxes', () {
			expect(noteSyntax.parse('- milk').type, LineType.bullet);
			expect(noteSyntax.parse('\t- milk').indent, 1);
			expect(noteSyntax.parse('-milk').type, LineType.text);
			final result = typeEdit(cursorAt('\t- milk', 7), cursorAt('\t- milk\n', 8));
			expect(result.text, '\t- milk\n\t- ');
			final ended = typeEdit(cursorAt('- a\n- ', 6), cursorAt('- a\n- \n', 7));
			expect(ended.text, '- a\n- \n');
		});

		test('backspace at bullet text start removes the bullet', () {
			final result = typeEdit(cursorAt('- milk', 2), cursorAt('-milk', 1));
			expect(result.text, 'milk');
		});

		test('selected lines all become checkboxes, and back to text', () {
			const text = 'milk\n\tbread\n\neggs';
			final selected = TextEditingValue(
				text: text,
				selection: const TextSelection(baseOffset: 0, extentOffset: text.length),
			);
			final checkboxes = toggleListType(selected, LineType.unchecked);
			expect(checkboxes.text, '- [ ] milk\n\t- [ ] bread\n\n- [ ] eggs');
			expect(toggleListType(checkboxes, LineType.unchecked).text, text);
			expect(toggleListType(checkboxes, LineType.bullet).text, '- milk\n\t- bread\n\n- eggs');
		});

		test('lines move up and down with the cursor', () {
			final movedUp = moveLines(cursorAt('a\nb\nc', 4), -1);
			expect(movedUp.text, 'a\nc\nb');
			expect(movedUp.selection.baseOffset, 2);
			expect(moveLines(cursorAt('a\nb\nc', 0), 1).text, 'b\na\nc');
			expect(moveLines(cursorAt('a\nb', 0), -1).text, 'a\nb');
		});

		test('only the box itself toggles a checkbox, not the indent before it', () {
			const text = '\t\t- [ ] milk';
			expect(checkboxLineStartAt(text, 0), isNull);
			expect(checkboxLineStartAt(text, 2), isNull);
			expect(checkboxLineStartAt(text, 5), 0);
			expect(checkboxLineStartAt(text, 7), 0);
			expect(checkboxLineStartAt(text, 9), isNull);
			expect(checkboxLineStartAt('- [ ] milk', 0), 0);
			expect(checkboxLineStartAt('- [ ] milk', 2), 0);
		});
	});
}
