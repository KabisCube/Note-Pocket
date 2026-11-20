import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_pocket/notes/note_storage.dart';
import 'package:note_pocket/ui/settings_screen.dart';

const typingTime = Duration(seconds: 2);

void main() {
	testWidgets('Esc leaves the settings screen', (tester) async {
		await tester.pumpWidget(MaterialApp(
			home: Builder(
				builder: (context) => TextButton(
					onPressed: () => Navigator.push(
						context,
						MaterialPageRoute(
							builder: (_) => SettingsScreen(
								currentFolder: Directory.systemTemp.path,
								storage: NoteStorage(Directory.systemTemp),
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
		expect(find.byType(SettingsScreen), findsOneWidget);

		await tester.sendKeyEvent(LogicalKeyboardKey.escape);
		await tester.pumpAndSettle();
		expect(find.byType(SettingsScreen), findsNothing);
	});
}
