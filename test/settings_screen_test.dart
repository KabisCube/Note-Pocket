import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_pocket/notes/note_storage.dart';
import 'package:note_pocket/notes/notes_folder.dart';
import 'package:note_pocket/ui/settings_screen.dart';
import 'package:note_pocket/ui/shortcuts.dart';

const typingTime = Duration(seconds: 2);

Future<AppSettings> openSettings(WidgetTester tester) async {
	final settings = AppSettings(File('${Directory.systemTemp.path}/note_pocket_settings_screen_test.ini'), {});
	await tester.pumpWidget(MaterialApp(
		home: Builder(
			builder: (context) => TextButton(
				onPressed: () => Navigator.push(
					context,
					MaterialPageRoute(
						builder: (_) => SettingsScreen(
							currentFolder: Directory.systemTemp.path,
							storage: NoteStorage(Directory.systemTemp),
							settings: settings,
							onNotesFolderChanged: (_) async {},
							onThemeChanged: (_) async {},
							onAccentColorChanged: (_) async {},
						),
					),
				),
				child: const Text('open settings'),
			),
		),
	));
	await tester.tap(find.text('open settings'));
	await tester.pumpAndSettle();
	await tester.pump(typingTime);
	return settings;
}

void main() {
	tearDown(() => keyBindings = KeyBindings());

	testWidgets('Esc leaves the settings screen', (tester) async {
		await openSettings(tester);
		expect(find.byType(SettingsScreen), findsOneWidget);

		await tester.sendKeyEvent(LogicalKeyboardKey.escape);
		await tester.pumpAndSettle();
		expect(find.byType(SettingsScreen), findsNothing);
	});

	testWidgets('a shortcut is changed by pressing [set] and then the new keys', (tester) async {
		final settings = await openSettings(tester);
		// The list only builds what is on screen, so scroll down to the row first
		final description = find.text(ShortcutAction.saveNote.description);
		await tester.scrollUntilVisible(description, 100, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
		final saveRow = find.ancestor(of: description, matching: find.byType(Row)).first;
		await tester.tap(find.descendant(of: saveRow, matching: find.text(setShortcutLabel)));
		await tester.pump();
		expect(find.text(recordingHint), findsOneWidget);

		await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
		await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
		await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
		await tester.pump();

		expect(describeActivators(keyBindings.of(ShortcutAction.saveNote)), 'Ctrl+K');
		expect(decodeActivators(settings.shortcuts[ShortcutAction.saveNote.name])!.map(describeActivator), ['Ctrl+K']);
		expect(find.byType(SettingsScreen), findsOneWidget);

		await tester.tap(find.descendant(of: saveRow, matching: find.text(resetShortcutLabel)));
		await tester.pump();
		expect(keyBindings.isChanged(ShortcutAction.saveNote), isFalse);
	});
}
