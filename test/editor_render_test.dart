import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_pocket/notes/note.dart';
import 'package:note_pocket/notes/note_order.dart';
import 'package:note_pocket/notes/note_storage.dart';
import 'package:note_pocket/notes/notes_folder.dart';
import 'package:note_pocket/ui/ascii_widgets.dart';
import 'package:note_pocket/ui/checklist_controller.dart';
import 'package:note_pocket/ui/note_editor.dart';
import 'package:note_pocket/ui/note_list_screen.dart';
import 'package:note_pocket/ui/tags_view.dart';
import 'package:note_pocket/ui/terminal_theme.dart';

const fileWaitTime = Duration(milliseconds: 200);
final titleTypingTime = typingInterval * (screenTitle.length + 2);

void main() {
	testWidgets('editor renders tabs and checkboxes and moves the cursor over a tab', (tester) async {
		final controller = ChecklistController(text: '\t- [ ] child\nplain\tafter');
		await tester.pumpWidget(MaterialApp(
			home: Scaffold(body: TextField(controller: controller, maxLines: null)),
		));
		await tester.tap(find.byType(TextField));
		await tester.pump();

		controller.selection = const TextSelection.collapsed(offset: 17);
		await tester.pump();
		expect(tester.takeException(), isNull);
		expect(controller.text, '\t- [ ] child\nplain\tafter');
	});

	testWidgets('typing a color tag in the title sets the color when leaving the field', (tester) async {
		final editorKey = GlobalKey<NoteEditorState>();
		await tester.pumpWidget(MaterialApp(
			home: Scaffold(
				body: NoteEditor(
					key: editorKey,
					storage: NoteStorage(Directory.systemTemp),
					fillsSpace: true,
					onApply: () {},
				),
			),
		));
		final editor = editorKey.currentState!;
		editor.titleController.text = 'test name #yellow';
		await tester.pump();
		expect(editor.content, '**test name** @yellow');

		editor.bodyFocus.requestFocus();
		await tester.pump();
		expect(editor.titleController.text, 'test name');
		expect(editor.titleColor, 'yellow');
		expect(editor.content, '**test name** @yellow');

		editor.titleFocus.requestFocus();
		editor.titleController.text = 'test name #blue';
		await tester.pump(colorTagDelay);
		expect(editor.titleController.text, 'test name');
		expect(editor.titleColor, 'blue');
		editor.autosaveTimer?.cancel();
	});

	testWidgets('tag tabs filter the note list', (tester) async {
		final folder = (await tester.runAsync(() => Directory.systemTemp.createTemp('note_pocket_tags')))!;
		await tester.runAsync(() async {
			await File('${folder.path}/Work.txt').writeAsString('Work\n[ ] report\n#work');
			await File('${folder.path}/Home.txt').writeAsString('Home\n[ ] dishes\n#home');
			final orderFile = File('${folder.parent.path}/note_pocket_tags_order.txt');
			await tester.pumpWidget(MaterialApp(
				home: NoteListScreen(
					storage: NoteStorage(folder),
					order: NoteOrder(orderFile),
					settings: AppSettings(File('${folder.parent.path}/note_pocket_test_settings.ini'), {}),
					onNotesFolderChanged: (_) async {},
					onThemeChanged: (_) async {},
					onAccentColorChanged: (_) async {},
				),
			));
			await Future.delayed(fileWaitTime);
		});
		await tester.pumpAndSettle();
		expect(find.text('Work'), findsOneWidget);
		expect(find.text('Home'), findsOneWidget);

		await tester.tap(find.text(' #work '));
		await tester.pumpAndSettle();
		expect(find.text('[#work]'), findsOneWidget);
		expect(find.text('Work'), findsOneWidget);
		expect(find.text('Home'), findsNothing);
		expect(tester.takeException(), isNull);

		await tester.runAsync(() => folder.delete(recursive: true));
	});

	testWidgets('arrow keys step through the list, enter edits with the cursor in the text, escape returns', (tester) async {
		final folder = (await tester.runAsync(() => Directory.systemTemp.createTemp('note_pocket_keys')))!;
		await tester.runAsync(() async {
			await File('${folder.path}/Work.txt').writeAsString('Work\n- [ ] report\n#work');
			await File('${folder.path}/Home.txt').writeAsString('Home\n- [ ] dishes');
			final orderFile = File('${folder.parent.path}/note_pocket_keys_order.txt');
			await orderFile.writeAsString('Work.txt\nHome.txt');
			await tester.pumpWidget(MaterialApp(
				home: NoteListScreen(
					storage: NoteStorage(folder),
					order: NoteOrder(orderFile),
					settings: AppSettings(File('${folder.parent.path}/note_pocket_keys_settings.ini'), {}),
					onNotesFolderChanged: (_) async {},
					onThemeChanged: (_) async {},
					onAccentColorChanged: (_) async {},
				),
			));
			await Future.delayed(fileWaitTime);
		});
		await tester.pumpAndSettle();

		bool isFocusedInside(String text) {
			final focusContext = FocusManager.instance.primaryFocus?.context;
			if (focusContext == null) return false;
			return find.descendant(of: find.byWidget(focusContext.widget), matching: find.text(text)).evaluate().isNotEmpty;
		}

		await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
		await tester.pump();
		expect(isFocusedInside('[all]'), isTrue);
		await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
		await tester.pump();
		expect(isFocusedInside(receiveLabel), isTrue);
		await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
		await tester.pump();
		expect(isFocusedInside(settingsLabel), isTrue);
		expect(find.text('[all]'), findsOneWidget);
		await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
		await tester.pump();
		expect(isFocusedInside('[all]'), isTrue);
		await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
		await tester.pump();
		expect(isFocusedInside(newNoteButtonLabel), isTrue);
		await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
		await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
		await tester.pump();
		expect(isFocusedInside('Home'), isTrue);
		await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
		await tester.pump();
		expect(isFocusedInside('Work'), isTrue);

		await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
		await tester.pumpAndSettle();
		expect(find.text('[#work]'), findsOneWidget);
		expect(find.text('Home'), findsNothing);
		expect(isFocusedInside('[#work]'), isTrue);
		await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
		await tester.pumpAndSettle();
		expect(find.text('[all]'), findsOneWidget);
		await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
		await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
		await tester.pump();
		expect(isFocusedInside('Work'), isTrue);

		await tester.sendKeyEvent(LogicalKeyboardKey.enter);
		await tester.runAsync(() => Future.delayed(fileWaitTime));
		await tester.pumpAndSettle();
		final editor = tester.state<NoteEditorState>(find.byType(NoteEditor));
		expect(editor.bodyFocus.hasPrimaryFocus, isTrue);
		expect(editor.bodyController.selection, TextSelection.collapsed(offset: editor.bodyController.text.length));

		await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
		await tester.sendKeyEvent(LogicalKeyboardKey.enter);
		await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
		await tester.pump();
		expect(editor.bodyController.text, '- [x] report');
		expect(find.byType(NoteEditor), findsOneWidget);
		await tester.pump(checkboxFrameInterval * checkboxMarks.length);

		for (var press = 0; press < 2; press++) {
			await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
			await tester.pump();
		}
		expect(isFocusedInside(newNoteButtonLabel), isTrue);
		await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
		await tester.pump();
		expect(editor.bodyFocus.hasPrimaryFocus, isTrue);

		bool isFocusedIn(Finder finder) {
			final focusContext = FocusManager.instance.primaryFocus?.context;
			return focusContext != null && find.ancestor(of: find.byWidget(focusContext.widget), matching: finder).evaluate().isNotEmpty;
		}

		await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
		await tester.pump();
		expect(editor.titleFocus.hasPrimaryFocus, isTrue);
		await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
		await tester.pump();
		expect(isFocusedIn(find.byType(PopupMenuButton<String>)), isTrue);
		await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
		await tester.pump();
		expect(isFocusedIn(find.byType(PopupMenuButton<VoidCallback>)), isTrue);
		expect(find.text('[all]'), findsOneWidget);
		editor.bodyFocus.requestFocus();
		await tester.pump();

		await tester.runAsync(() async {
			await tester.sendKeyEvent(LogicalKeyboardKey.escape);
			await Future.delayed(fileWaitTime);
			await tester.pump();
		});
		await tester.pumpAndSettle();
		expect(find.byType(NoteEditor), findsNothing);
		expect(isFocusedInside('Work'), isTrue);
		expect(tester.takeException(), isNull);

		await tester.runAsync(() => folder.delete(recursive: true));
	});

	testWidgets('note list renders frames and opens a note inline', (tester) async {
		final folder = (await tester.runAsync(() => Directory.systemTemp.createTemp('note_pocket_test')))!;
		await tester.runAsync(() => File('${folder.path}/Groceries.txt').writeAsString('Groceries\n[ ] milk\n\t[x] oat'));

		await tester.runAsync(() async {
			final orderFile = File('${folder.parent.path}/note_pocket_test_order.txt');
			await tester.pumpWidget(MaterialApp(
				home: NoteListScreen(
					storage: NoteStorage(folder),
					order: NoteOrder(orderFile),
					settings: AppSettings(File('${folder.parent.path}/note_pocket_test_settings.ini'), {}),
					onNotesFolderChanged: (_) async {},
					onThemeChanged: (_) async {},
					onAccentColorChanged: (_) async {},
				),
			));
			await Future.delayed(fileWaitTime);
		});
		await tester.pumpAndSettle();
		expect(find.text('Groceries'), findsOneWidget);

		await tester.tap(find.text('Groceries'));
		await tester.runAsync(() => Future.delayed(fileWaitTime));
		await tester.pumpAndSettle();
		expect(find.byType(NoteEditor), findsOneWidget);
		expect(tester.takeException(), isNull);

		await tester.runAsync(() => folder.delete(recursive: true));
	});

	testWidgets('long list lines wrap with an indent under the text', (tester) async {
		const longLine = '\t- [ ] when I type this and the words wrap they should wrap like this';
		final controller = ChecklistController(text: longLine)..wrapWidth = 300;
		await tester.pumpWidget(MaterialApp(
			home: Scaffold(
				body: SizedBox(width: 300, child: TextField(controller: controller, maxLines: null)),
			),
		));
		final span = controller.buildTextSpan(
			context: tester.element(find.byType(TextField)),
			style: const TextStyle(fontSize: 14),
			withComposing: false,
		);
		final indentedStarts = <WidgetSpan>[];
		span.visitChildren((child) {
			if (child is WidgetSpan && child.child is Padding) indentedStarts.add(child);
			return true;
		});
		expect(indentedStarts, isNotEmpty);
		expect(span.toPlainText(includePlaceholders: true).length, longLine.length);

		controller.selection = const TextSelection.collapsed(offset: longLine.length);
		await tester.pump();
		expect(tester.takeException(), isNull);
	});

	testWidgets('typing a known tag shows the completion and tab accepts it', (tester) async {
		final editorKey = GlobalKey<NoteEditorState>();
		await tester.pumpWidget(MaterialApp(
			home: Scaffold(
				body: NoteEditor(
					key: editorKey,
					storage: NoteStorage(Directory.systemTemp),
					fillsSpace: true,
					onApply: () {},
					initialTags: const ['music'],
					knownTags: const ['music', 'workshop'],
				),
			),
		));
		final editor = editorKey.currentState!;
		editor.tagsFocus.requestFocus();
		editor.tagsController.value = const TextEditingValue(
			text: '#music #wo',
			selection: TextSelection.collapsed(offset: 10),
		);
		await tester.pump();
		expect(find.textContaining('rkshop', findRichText: true), findsOneWidget);

		await tester.sendKeyEvent(LogicalKeyboardKey.tab);
		await tester.pump();
		expect(editor.tagsController.text, '#music #workshop ');
		expect(tester.takeException(), isNull);
		editor.autosaveTimer?.cancel();
	});

	testWidgets('the completion starts right where the typed tag ends', (tester) async {
		final editorKey = GlobalKey<NoteEditorState>();
		await tester.pumpWidget(MaterialApp(
			home: Scaffold(
				body: NoteEditor(
					key: editorKey,
					storage: NoteStorage(Directory.systemTemp),
					fillsSpace: true,
					onApply: () {},
					initialTags: const ['music'],
					knownTags: const ['music', 'software-dev'],
				),
			),
		));
		final editor = editorKey.currentState!;
		editor.tagsFocus.requestFocus();
		editor.tagsController.value = const TextEditingValue(text: '#so', selection: TextSelection.collapsed(offset: 3));
		await tester.pump();

		final tagsField = find.byWidgetPredicate((widget) => widget is TextField && widget.controller is TagsController);
		final typedText = TextPainter(
			text: TextSpan(text: '#so', style: tester.widget<TextField>(tagsField).style),
			textDirection: TextDirection.ltr,
		)..layout();
		final textEnd = tester.getTopLeft(tagsField).dx + typedText.width;
		final completionStart = tester.getTopLeft(find.byType(CompletionGhost)).dx;
		expect((completionStart - textEnd).abs(), lessThan(1));
		typedText.dispose();
		editor.autosaveTimer?.cancel();
	});

	testWidgets('an opened note types its name out, then shows the title field', (tester) async {
		final note = Note(file: File('Groceries.txt'), content: 'Groceries\n[ ] milk', modified: DateTime(2026));
		await tester.pumpWidget(MaterialApp(
			home: Scaffold(
				body: NoteEditor(
					storage: NoteStorage(Directory.systemTemp),
					note: note,
					fillsSpace: true,
					onApply: () {},
				),
			),
		));
		expect(find.byType(TypewriterText), findsOneWidget);
		final titleField = find.byWidgetPredicate((widget) => widget is TextField && widget.focusNode != null && widget.style?.fontWeight == FontWeight.bold);
		expect(titleField, findsNothing);

		await tester.pump(typingInterval * ('Groceries'.length + 2));
		await tester.pump();
		expect(find.byType(TypewriterText), findsNothing);
		expect(titleField, findsOneWidget);
	});

	testWidgets('coming back to the main screen starts the title hidden and types it out', (tester) async {
		final folder = (await tester.runAsync(() => Directory.systemTemp.createTemp('note_pocket_title')))!;
		await tester.runAsync(() async {
			await tester.pumpWidget(MaterialApp(
				home: NoteListScreen(
					storage: NoteStorage(folder),
					order: NoteOrder(File('${folder.parent.path}/note_pocket_title_order.txt')),
					settings: AppSettings(File('${folder.parent.path}/note_pocket_title_settings.ini'), {}),
					onNotesFolderChanged: (_) async {},
					onThemeChanged: (_) async {},
					onAccentColorChanged: (_) async {},
				),
			));
			await Future.delayed(fileWaitTime);
		});
		await tester.runAsync(() => Future.delayed(titleTypingTime));
		await tester.pump();
		expect(find.text(screenTitle), findsOneWidget);

		final navigator = Navigator.of(tester.element(find.byType(NoteListScreen)));
		navigator.push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('other screen'))));
		await tester.pumpAndSettle();
		navigator.pop();
		await tester.pump();
		expect(find.text(screenTitle), findsNothing);

		await tester.pumpAndSettle();
		await tester.pump(titleTypingTime);
		expect(find.text(screenTitle), findsOneWidget);
		await tester.runAsync(() => folder.delete(recursive: true));
	});

	testWidgets('dragging a note title with the mouse moves the note', (tester) async {
		final folder = (await tester.runAsync(() => Directory.systemTemp.createTemp('note_pocket_drag')))!;
		final orderFile = File('${folder.parent.path}/note_pocket_drag_order.txt');
		await tester.runAsync(() async {
			await File('${folder.path}/Alpha.txt').writeAsString('Alpha\none');
			await File('${folder.path}/Beta.txt').writeAsString('Beta\ntwo');
			await orderFile.writeAsString('Alpha.txt\nBeta.txt');
			await tester.pumpWidget(MaterialApp(
				home: NoteListScreen(
					storage: NoteStorage(folder),
					order: NoteOrder(orderFile),
					settings: AppSettings(File('${folder.parent.path}/note_pocket_drag_settings.ini'), {}),
					onNotesFolderChanged: (_) async {},
					onThemeChanged: (_) async {},
					onAccentColorChanged: (_) async {},
				),
			));
			await Future.delayed(fileWaitTime);
		});
		await tester.pumpAndSettle();
		expect(tester.getTopLeft(find.text('Alpha')).dy, lessThan(tester.getTopLeft(find.text('Beta')).dy));

		final distance = tester.getTopLeft(find.text('Beta')).dy - tester.getTopLeft(find.text('Alpha')).dy;
		final mouse = await tester.startGesture(tester.getCenter(find.text('Alpha')), kind: PointerDeviceKind.mouse);
		for (var step = 0; step < 10; step++) {
			await mouse.moveBy(Offset(0, distance / 5));
			await tester.pump();
		}
		await mouse.up();
		await tester.pumpAndSettle();

		expect(tester.getTopLeft(find.text('Beta')).dy, lessThan(tester.getTopLeft(find.text('Alpha')).dy));
		await tester.runAsync(() => folder.delete(recursive: true));
	});

	testWidgets('closing a maximized note shows its new text in the list right away', (tester) async {
		final folder = (await tester.runAsync(() => Directory.systemTemp.createTemp('note_pocket_maximize')))!;
		await tester.runAsync(() async {
			await File('${folder.path}/Groceries.txt').writeAsString('Groceries\n[ ] milk');
			await tester.pumpWidget(MaterialApp(
				home: NoteListScreen(
					storage: NoteStorage(folder),
					order: NoteOrder(File('${folder.parent.path}/note_pocket_maximize_order.txt')),
					settings: AppSettings(File('${folder.parent.path}/note_pocket_maximize_settings.ini'), {}),
					onNotesFolderChanged: (_) async {},
					onThemeChanged: (_) async {},
					onAccentColorChanged: (_) async {},
				),
			));
			await Future.delayed(fileWaitTime);
		});
		await tester.pumpAndSettle();

		await tester.tap(find.text('[^]'));
		await tester.pumpAndSettle();
		final bodyField = find.byWidgetPredicate((widget) => widget is TextField && widget.controller is ChecklistController);
		await tester.enterText(bodyField, '[ ] milk\n[ ] eggs');
		await tester.runAsync(() async {
			await tester.sendKeyEvent(LogicalKeyboardKey.escape);
			await Future.delayed(fileWaitTime);
		});
		await tester.pumpAndSettle();
		await tester.runAsync(() => Future.delayed(fileWaitTime));
		await tester.pumpAndSettle();

		expect(find.byType(NoteEditor), findsNothing);
		expect(find.textContaining('eggs', findRichText: true), findsOneWidget);
		await tester.runAsync(() => folder.delete(recursive: true));
	});

	test('text between stars is bold or italic and keeps its stars', () {
		bool hasSpan(InlineSpan span, String wantedText, bool Function(TextStyle style) isWantedStyle) {
			if (span is! TextSpan) return false;
			if (span.style != null && isWantedStyle(span.style!) && span.toPlainText() == wantedText) return true;
			return span.children?.any((child) => hasSpan(child, wantedText, isWantedStyle)) ?? false;
		}

		const text = '- [ ] buy **milk** and *eggs*';
		final span = checklistSpan(text, tabWidth: 0);
		expect(span.toPlainText(includePlaceholders: false), text);
		expect(hasSpan(span, 'milk', (style) => style.fontWeight == FontWeight.bold), isTrue);
		expect(hasSpan(span, 'eggs', (style) => style.fontStyle == FontStyle.italic), isTrue);

		bool isHidden(TextStyle style) => style.fontSize == hiddenTextStyle.fontSize;
		expect(hasSpan(span, boldMark, isHidden), isTrue);
		final cursorLineSpan = checklistSpan(text, tabWidth: 0, lineWithMarksShown: 0);
		expect(hasSpan(cursorLineSpan, boldMark, isHidden), isFalse);
		expect(hasSpan(cursorLineSpan, boldMark, (style) => style.color == terminalDimText), isTrue);
	});

	testWidgets('note text and cursor use the note color', (tester) async {
		final note = Note(file: File('Song.txt'), content: '*Song* @blue\nlyrics', modified: DateTime(2026));
		await tester.pumpWidget(MaterialApp(
			home: Scaffold(
				body: NoteEditor(storage: NoteStorage(Directory.systemTemp), note: note, fillsSpace: true, onApply: () {}),
			),
		));
		await tester.pump(titleTypingTime);
		final body = tester.widgetList<TextField>(find.byType(TextField)).firstWhere((field) => field.maxLines == null);
		expect(body.cursorColor, titleColors['blue']);
		expect(body.style?.color, titleColors['blue']);
	});
	testWidgets('tags being typed are only saved once the tags field is left', (tester) async {
		final note = Note(file: File('Song.txt'), content: '**Song**\nlyrics\n#music', modified: DateTime(2026));
		final editorKey = GlobalKey<NoteEditorState>();
		await tester.pumpWidget(MaterialApp(
			home: Scaffold(
				body: NoteEditor(key: editorKey, storage: NoteStorage(Directory.systemTemp), note: note, fillsSpace: true, onApply: () {}),
			),
		));
		await tester.pump(titleTypingTime);
		final editor = editorKey.currentState!;

		editor.tagsFocus.requestFocus();
		await tester.pump();
		editor.tagsController.text = '#music #wor';
		await tester.pump();
		expect(editor.autosaveContent, '**Song**\nlyrics\n#music');

		editor.bodyFocus.requestFocus();
		await tester.pump();
		expect(editor.autosaveContent, '**Song**\nlyrics\n#music #wor');
		editor.autosaveTimer?.cancel();
	});

	testWidgets('up and down move between title, body and tags at the edges of the body', (tester) async {
		final note = Note(file: File('Song.txt'), content: '**Song**\nverse\nchorus\n#music', modified: DateTime(2026));
		final editorKey = GlobalKey<NoteEditorState>();
		await tester.pumpWidget(MaterialApp(
			home: Scaffold(
				body: NoteEditor(key: editorKey, storage: NoteStorage(Directory.systemTemp), note: note, fillsSpace: true, onApply: () {}),
			),
		));
		await tester.pump(titleTypingTime);
		await tester.pump();
		final editor = editorKey.currentState!;
		expect(editor.bodyFocus.hasPrimaryFocus, isTrue);

		await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
		await tester.pump();
		expect(editor.tagsFocus.hasPrimaryFocus, isTrue);

		await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
		await tester.pump();
		expect(editor.bodyFocus.hasPrimaryFocus, isTrue);
		expect(editor.bodyController.selection.baseOffset, editor.bodyController.text.length);

		await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
		await tester.pump();
		expect(editor.bodyFocus.hasPrimaryFocus, isTrue);
		await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
		await tester.pump();
		expect(editor.titleFocus.hasPrimaryFocus, isTrue);

		await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
		await tester.pump();
		expect(editor.bodyFocus.hasPrimaryFocus, isTrue);
		expect(editor.bodyController.selection.baseOffset, 0);
		editor.autosaveTimer?.cancel();
	});

	testWidgets('the menus at the top of a note can be reached and opened with the keyboard', (tester) async {
		final note = Note(file: File('Song.txt'), content: '**Song**\nverse', modified: DateTime(2026));
		final editorKey = GlobalKey<NoteEditorState>();
		await tester.pumpWidget(MaterialApp(
			home: Scaffold(
				body: NoteEditor(key: editorKey, storage: NoteStorage(Directory.systemTemp), note: note, fillsSpace: true, onApply: () {}),
			),
		));
		await tester.pump(titleTypingTime);
		await tester.pump();
		final editor = editorKey.currentState!;

		bool isFocusedIn(Finder finder) {
			final focusContext = FocusManager.instance.primaryFocus?.context;
			return focusContext != null && find.ancestor(of: find.byWidget(focusContext.widget), matching: finder).evaluate().isNotEmpty;
		}

		await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
		await tester.pump();
		expect(editor.titleFocus.hasPrimaryFocus, isTrue);
		editor.titleController.selection = const TextSelection.collapsed(offset: 1);
		await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
		await tester.pump();
		expect(editor.titleFocus.hasPrimaryFocus, isTrue);
		editor.titleController.selection = TextSelection.collapsed(offset: editor.titleController.text.length);
		await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
		await tester.pump();
		expect(isFocusedIn(find.byType(PopupMenuButton<String>)), isTrue);
		await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
		await tester.pump();
		expect(isFocusedIn(find.byType(PopupMenuButton<VoidCallback>)), isTrue);
		await tester.sendKeyEvent(LogicalKeyboardKey.enter);
		await tester.pumpAndSettle();
		expect(find.text(sendLabel), findsOneWidget);
		await tester.sendKeyEvent(LogicalKeyboardKey.escape);
		await tester.pumpAndSettle();
		expect(find.text(sendLabel), findsNothing);

		editor.bodyFocus.requestFocus();
		await tester.pump();
		await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
		await tester.sendKeyEvent(LogicalKeyboardKey.f10);
		await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
		await tester.pumpAndSettle();
		expect(find.text(sendLabel), findsOneWidget);
		await tester.sendKeyEvent(LogicalKeyboardKey.escape);
		await tester.pumpAndSettle();
		editor.autosaveTimer?.cancel();
	});

	testWidgets('a color typed after a tag sets the tag color when leaving the field', (tester) async {
		final note = Note(file: File('Song.txt'), content: '**Song**\nlyrics\n#music', modified: DateTime(2026));
		final editorKey = GlobalKey<NoteEditorState>();
		final pickedColors = <String, String?>{};
		await tester.pumpWidget(MaterialApp(
			home: Scaffold(
				body: NoteEditor(
					key: editorKey,
					storage: NoteStorage(Directory.systemTemp),
					note: note,
					fillsSpace: true,
					onApply: () {},
					onTagColorPicked: (tag, colorName) async => pickedColors[tag] = colorName,
				),
			),
		));
		await tester.pump(titleTypingTime);
		final editor = editorKey.currentState!;

		editor.tagsFocus.requestFocus();
		await tester.pump();
		editor.tagsController.text = '#music@yellow #work';
		await tester.pump();
		expect(editor.content, '**Song**\nlyrics\n#music #work');

		editor.bodyFocus.requestFocus();
		await tester.pump();
		expect(pickedColors, {'music': 'yellow'});
		expect(editor.tagColors['music'], 'yellow');
		expect(editor.tagsController.text, '#music #work');
		editor.autosaveTimer?.cancel();
	});
}
