import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_pocket/notes/note.dart';
import 'package:note_pocket/notes/note_storage.dart';
import 'package:note_pocket/transfer/lan_protocol.dart';
import 'package:note_pocket/ui/review_screen.dart';

TextButton buttonLabelled(WidgetTester tester, String label) {
	return tester.widget<TextButton>(find.widgetWithText(TextButton, label));
}

void main() {
	testWidgets('accept is only enabled once every difference is picked', (tester) async {
		final localNote = Note(
			file: File('Groceries.txt'),
			content: 'Groceries\n[ ] milk\n[ ] bread',
			modified: DateTime(2026),
		);
		const packet = NotePacket(senderName: 'phone', content: 'Groceries\n[x] milk\n[ ] bread');

		await tester.pumpWidget(MaterialApp(
			home: ReviewScreen(storage: NoteStorage(Directory.systemTemp), packet: packet, localNote: localNote),
		));
		await tester.pumpAndSettle();
		expect(buttonLabelled(tester, acceptLabel).onPressed, isNull);

		await tester.tap(find.textContaining('phone', findRichText: true).last);
		await tester.pump();
		expect(buttonLabelled(tester, acceptLabel).onPressed, isNotNull);
		expect(tester.takeException(), isNull);
	});

	testWidgets('a new note can be accepted right away', (tester) async {
		const packet = NotePacket(senderName: 'phone', content: 'Fresh\n[ ] one');
		await tester.pumpWidget(MaterialApp(
			home: ReviewScreen(storage: NoteStorage(Directory.systemTemp), packet: packet),
		));
		await tester.pumpAndSettle();
		expect(find.text('from phone: new note'), findsOneWidget);
		expect(buttonLabelled(tester, acceptLabel).onPressed, isNotNull);
	});
}
