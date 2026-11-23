import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_pocket/notes/note.dart';
import 'package:note_pocket/notes/note_order.dart';
import 'package:note_pocket/notes/note_storage.dart';
import 'package:note_pocket/notes/notes_folder.dart';
import 'package:note_pocket/ui/ascii_widgets.dart';
import 'package:note_pocket/ui/note_editor.dart';
import 'package:note_pocket/ui/note_list_screen.dart';

const fileWaitTime = Duration(milliseconds: 200);
final titleTypingTime = typingInterval * 20;
// Popup titles type themselves out, like screen titles
final popupTitleTypingTime = typingInterval * 40;

// Keeps notes in memory, and can be told to fail like a full disk or a file locked by another program
class MemoryStorage extends NoteStorage {
	MemoryStorage([this.notes = const []]) : super(Directory.systemTemp);

	final List<Note> notes;
	final saved = <String>[];
	bool isFailing = false;

	@override
	Future<List<Note>> loadAll() async => notes;

	@override
	Future<Note> save(Note? existing, String content) async {
		if (isFailing) throw const FileSystemException('Permission denied', 'Groceries.txt');
		saved.add(content);
		return Note(file: existing?.file ?? File('Groceries.txt'), content: content, modified: DateTime.now());
	}
}

final groceries = Note(file: File('Groceries.txt'), content: '**Groceries**\nmilk', modified: DateTime(2026));

void main() {
	stayingInNoteTests();

	testWidgets('a note whose save fails can still be left, instead of the list getting stuck', (tester) async {
		final storage = MemoryStorage([groceries]);
		final folder = Directory.systemTemp;
		await tester.runAsync(() async {
			await tester.pumpWidget(MaterialApp(
				home: NoteListScreen(
					storage: storage,
					order: NoteOrder(File('${folder.path}/note_pocket_saving_order.txt')),
					settings: AppSettings(File('${folder.path}/note_pocket_saving_settings.ini'), {}),
					onNotesFolderChanged: (_) async {},
					onThemeChanged: (_) async {},
					onAccentColorChanged: (_) async {},
				),
			));
			await Future.delayed(fileWaitTime);
		});
		await tester.pumpAndSettle();
		await tester.tap(find.text('Groceries'));
		await tester.pumpAndSettle();
		final editors = find.byType(NoteEditor);
		final editor = tester.state<NoteEditorState>(editors);

		storage.isFailing = true;
		editor.bodyController.text = 'milk\neggs';
		await tester.pump(autosaveDelay);
		await tester.pump();
		expect(find.text(saveErrorLabel), findsOneWidget);

		// Before the fix, every save after a failed one failed too, and Esc did nothing
		await tester.sendKeyEvent(LogicalKeyboardKey.escape);
		await tester.pumpAndSettle();
		await tester.pump(popupTitleTypingTime);
		expect(find.textContaining("couldn't save"), findsOneWidget);
		await tester.tap(find.text('[edit]'));
		await tester.pumpAndSettle();
		expect(editors, findsOneWidget);

		storage.isFailing = false;
		await tester.sendKeyEvent(LogicalKeyboardKey.escape);
		await tester.pumpAndSettle();
		expect(editors, findsNothing);
		expect(storage.saved.last, '**Groceries**\nmilk\neggs');
		expect(tester.takeException(), isNull);
	});

	testWidgets('when saving only on request, nothing saves until asked, and leaving asks first', (tester) async {
		final storage = MemoryStorage();
		final editorKey = GlobalKey<NoteEditorState>();
		await tester.pumpWidget(MaterialApp(
			home: Scaffold(
				body: NoteEditor(
					key: editorKey,
					storage: storage,
					note: groceries,
					fillsSpace: true,
					savesAutomatically: false,
					onApply: () {},
				),
			),
		));
		await tester.pump(titleTypingTime);
		final editor = editorKey.currentState!;
		expect(find.text(unsavedMark), findsNothing);

		editor.bodyController.text = 'milk\neggs';
		await tester.pump(autosaveDelay * 2);
		expect(storage.saved, isEmpty);
		expect(find.text(unsavedMark), findsOneWidget);

		editor.bodyFocus.requestFocus();
		await tester.pump();
		await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
		await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
		await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
		await tester.pump();
		expect(storage.saved, ['**Groceries**\nmilk\neggs']);
		expect(find.text(unsavedMark), findsNothing);

		editor.bodyController.text = 'milk\neggs\nbread';
		await tester.pump();
		final cancelled = editor.confirmLeave();
		await tester.pumpAndSettle();
		await tester.pump(popupTitleTypingTime);
		expect(find.text('save changes? [y/n]'), findsOneWidget);

		// Clicking beside the popup does nothing; [cancel] goes back to the note, cursor and all
		await tester.tapAt(const Offset(5, 5));
		await tester.pumpAndSettle();
		expect(find.text('save changes? [y/n]'), findsOneWidget);
		await tester.tap(find.text('[cancel]'));
		await tester.pumpAndSettle();
		expect(await cancelled, isFalse);
		expect(editor.bodyFocus.hasFocus, isTrue);
		expect(storage.saved, hasLength(1));

		final leaving = editor.confirmLeave();
		await tester.pumpAndSettle();
		await tester.pump(popupTitleTypingTime);
		await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
		await tester.pumpAndSettle();
		expect(await leaving, isTrue);
		expect(storage.saved, hasLength(1));
	});

	testWidgets('a note opened without changes never asks, even if its file is in an older form', (tester) async {
		final oldStyle = Note(file: File('Old.txt'), content: '*Old* #green\n[ ] milk', modified: DateTime(2026));
		final editorKey = GlobalKey<NoteEditorState>();
		await tester.pumpWidget(MaterialApp(
			home: Scaffold(
				body: NoteEditor(key: editorKey, storage: MemoryStorage(), note: oldStyle, fillsSpace: true, savesAutomatically: false, onApply: () {}),
			),
		));
		await tester.pump(titleTypingTime);
		expect(editorKey.currentState!.hasUnsavedChanges, isFalse);
		expect(await editorKey.currentState!.confirmLeave(), isTrue);
	});
}

void stayingInNoteTests() {
	for (final answer in ['Esc', '[cancel]']) {
		testWidgets('answering the save popup with $answer stays in the note, with the cursor in its text', (tester) async {
			final storage = MemoryStorage([groceries]);
			final folder = Directory.systemTemp;
			final settings = AppSettings(File('${folder.path}/note_pocket_staying_settings.ini'), {});
			await tester.runAsync(() async {
				await settings.setSavesOnlyOnRequest(true);
				await tester.pumpWidget(MaterialApp(
					home: NoteListScreen(
						storage: storage,
						order: NoteOrder(File('${folder.path}/note_pocket_staying_order.txt')),
						settings: settings,
						onNotesFolderChanged: (_) async {},
						onThemeChanged: (_) async {},
						onAccentColorChanged: (_) async {},
					),
				));
				await Future.delayed(fileWaitTime);
			});
			await tester.pumpAndSettle();
			await tester.tap(find.text('Groceries'));
			await tester.pumpAndSettle();
			await tester.pump(titleTypingTime);
			final editor = tester.state<NoteEditorState>(find.byType(NoteEditor));
			final body = find.byWidgetPredicate((widget) => widget is TextField && widget.maxLines == null);
			await tester.enterText(body, 'milk\neggs');
			await tester.pump();

			Future<void> answerPopup() async {
				await tester.sendKeyEvent(LogicalKeyboardKey.escape);
				await tester.pumpAndSettle();
				await tester.pump(popupTitleTypingTime);
				expect(find.text('save changes? [y/n]'), findsOneWidget);
				if (answer == 'Esc') {
					await tester.sendKeyEvent(LogicalKeyboardKey.escape);
				} else {
					await tester.tap(find.text('[cancel]'));
				}
				await tester.pumpAndSettle();
			}

			// Before the fix the note stayed open, but the focus went to the list, so it acted closed
			await answerPopup();
			expect(find.byType(NoteEditor), findsOneWidget);
			expect(editor.bodyFocus.hasPrimaryFocus, isTrue);

			// Leaving again asks again
			await answerPopup();
			expect(find.byType(NoteEditor), findsOneWidget);
			expect(editor.bodyFocus.hasPrimaryFocus, isTrue);
			expect(storage.saved, isEmpty);
		});
	}
}
