import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_pocket/ui/shortcuts.dart';

void main() {
	test('shortcuts are saved and read back the same', () {
		final activators = <ShortcutActivator>[
			const SingleActivator(LogicalKeyboardKey.enter, control: true, shift: true),
			const CharacterActivator('+'),
		];
		final readBack = decodeActivators(encodeActivators(activators))!;
		expect(readBack.map(describeActivator), ['Ctrl+Shift+Enter', '+']);
	});

	test('unreadable saved shortcuts fall back to the defaults', () {
		final bindings = KeyBindings.fromSaved({'saveNote': 'not json', 'closeNote': '[{"key":${LogicalKeyboardKey.keyQ.keyId},"ctrl":true}]'});
		expect(describeActivators(bindings.of(ShortcutAction.saveNote)), 'Ctrl+S');
		expect(describeActivators(bindings.of(ShortcutAction.closeNote)), 'Ctrl+Q');
	});

	test('the default keys are described the way people say them', () {
		final bindings = KeyBindings();
		expect(describeActivators(bindings.of(ShortcutAction.toggleCheckbox)), 'Ctrl+Enter, Ctrl+L');
		expect(describeActivators(bindings.of(ShortcutAction.moveLinesUp)), 'Ctrl+Up');
		expect(describeActivators(bindings.of(ShortcutAction.newNote)), '+, Num +');
	});

	test('keys already used by another action are found', () {
		final bindings = KeyBindings();
		const tab = SingleActivator(LogicalKeyboardKey.tab);
		expect(bindings.actionsUsing(tab, except: ShortcutAction.saveNote), [ShortcutAction.indent]);
	});
}
