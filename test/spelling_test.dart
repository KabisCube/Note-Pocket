import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_pocket/notes/note_storage.dart';
import 'package:note_pocket/spelling/enchant.dart';
import 'package:note_pocket/spelling/spell_checker.dart';
import 'package:note_pocket/spelling/word_list.dart';
import 'package:note_pocket/ui/ascii_widgets.dart';
import 'package:note_pocket/ui/checklist_controller.dart';
import 'package:note_pocket/ui/note_editor.dart';
import 'package:note_pocket/ui/spelling_menu.dart';
import 'package:note_pocket/ui/terminal_theme.dart';

class FakeDictionary implements SpellDictionary {
	FakeDictionary(this.words, [this.language = 'en_US']);

	@override
	final String language;

	final Set<String> words;

	@override
	bool knows(String word) => words.contains(word);

	@override
	List<String> suggestionsFor(String word) => words.where((known) => known[0] == word[0]).toList();
}

final checker = SpellChecker([FakeDictionary({'buy', "don't"}), FakeDictionary({'mjölk'})]);

List<String> misspelled(String line) {
	return [for (final word in checker.misspelledIn(line)) line.substring(word.start, word.end)];
}

void main() {
	test('a word is right when any dictionary knows it', () {
		expect(misspelled('buy mjölk, melk'), ['melk']);
		expect(misspelled('don’t **bui**'), ['bui']);
	});

	test('things that are not ordinary words are skipped', () {
		expect(misspelled('https://exmple.com exmple.com #taag v2x ABCD fooBar a /hoome'), isEmpty);
	});

	test('suggestions come from every dictionary, closest first, and added words become right', () {
		final ownChecker = SpellChecker([FakeDictionary({'milk', 'mild'}), FakeDictionary({'mjölk', 'milk'})]);
		expect(ownChecker.suggestionsFor('melk'), ['milk', 'mjölk', 'mild']);
		expect(ownChecker.suggestionsFor('mjök').first, 'mjölk');
		expect(ownChecker.isCorrect('melk'), isFalse);
		ownChecker.add('melk');
		expect(ownChecker.isCorrect('melk'), isTrue);
	});

	test('suggestions are in the language of the line, or else of the note, or else in all of them', () {
		final twoLanguages = SpellChecker([
			FakeDictionary({'buy', 'milk', 'glass'}, 'en_US'),
			FakeDictionary({'köp', 'mjölk', 'glass'}, 'sv_SE'),
		]);
		List<String> suggestions(List<String> contexts) => twoLanguages.suggestionsFor('melk', contexts: contexts);
		expect(suggestions(['buy melk', 'köp köp buy melk']), ['milk']);
		expect(suggestions(['köp melk']), ['mjölk']);
		expect(suggestions(['glass melk', 'köp\nglass melk']), ['mjölk']);
		expect(suggestions(['melk', 'melk']), ['milk', 'mjölk']);
	});

	test('the languages are read from KDE settings', () {
		const settings = '[General]\ndefaultLanguage=sv_SE\nignore_sv_SE=Qt\npreferredLanguages=sv_SE, en_CA\n';
		expect(kdeSpellLanguages(settings), ['sv_SE', 'en_CA']);
		expect(kdeSpellLanguages('[General]\n'), isEmpty);
	});

	testWidgets('misspelled words are marked, but not while they are typed, and can be replaced', (tester) async {
		final focus = FocusNode();
		final controller = ChecklistController(text: '- [ ] buy melk')
			..focusNode = focus
			..spellChecker = checker;
		await tester.pumpWidget(MaterialApp(
			home: Scaffold(body: TextField(controller: controller, focusNode: focus, maxLines: null)),
		));
		List<String> shown() => [for (final word in controller.misspelledWords) word.textInside(controller.text)];
		focus.requestFocus();
		await tester.pump();
		expect(shown(), ['melk']);

		controller.value = const TextEditingValue(text: '- [ ] buy melkk', selection: TextSelection.collapsed(offset: 15));
		expect(shown(), isEmpty);
		controller.value = const TextEditingValue(text: '- [ ] buy melkk ', selection: TextSelection.collapsed(offset: 16));
		expect(shown(), ['melkk']);
		controller.selection = const TextSelection.collapsed(offset: 12);
		expect(shown(), ['melkk']);
		controller.replaceWord(controller.misspelledWords.single, 'mjölk');
		expect(controller.text, '- [ ] buy mjölk ');
		expect(controller.selection.baseOffset, 15);
		await tester.pumpWidget(const SizedBox());
		focus.dispose();
		controller.dispose();
	});

	testWidgets('right-clicking a misspelled word offers suggestions and adding it', (tester) async {
		systemSpellChecker = SpellChecker([FakeDictionary({'milk'})]);
		addTearDown(() => systemSpellChecker = null);
		final editorKey = GlobalKey<NoteEditorState>();
		await tester.pumpWidget(MaterialApp(
			home: Scaffold(
				body: NoteEditor(
					key: editorKey,
					storage: NoteStorage(Directory.systemTemp),
					initialContent: 'Title\nmelk muck',
					savesAutomatically: false,
					fillsSpace: true,
					onApply: () {},
				),
			),
		));
		await tester.pump();
		final body = editorKey.currentState!.bodyController;
		editorKey.currentState!.bodyFocus.requestFocus();
		await tester.pump();

		Future<void> rightClick(int offset) async {
			final editable = editorKey.currentState!.bodyFocus.context!.findAncestorStateOfType<EditableTextState>()!.renderEditable;
			final caret = editable.getLocalRectForCaret(TextPosition(offset: offset));
			final position = editable.localToGlobal(caret.center);
			final gesture = await tester.startGesture(position, kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
			await gesture.up();
			await tester.pumpAndSettle();
		}

		await rightClick(2);
		await tester.tap(find.text('milk'));
		await tester.pumpAndSettle();
		expect(body.text, 'milk muck');
		expect(find.text(addToDictionaryLabel), findsNothing);

		await rightClick(7);
		await tester.tap(find.text(addToDictionaryLabel));
		await tester.pumpAndSettle();
		expect(body.misspelledWords, isEmpty);
		expect(body.text, 'milk muck');

		await rightClick(7);
		expect(find.text(addToDictionaryLabel), findsNothing);
		await tester.pumpWidget(const SizedBox());
	}, variant: TargetPlatformVariant.only(TargetPlatform.linux));

	test('added words are kept in a file, and can be removed', () async {
		final folder = await Directory.systemTemp.createTemp('note_pocket_words');
		final file = File('${folder.path}/$wordListFileName');
		final ownChecker = SpellChecker([FakeDictionary({})], addedWords: await WordList.read(file));
		ownChecker.add('kabis');
		ownChecker.add('Aardvark');
		expect(ownChecker.isCorrect('Kabis'), isTrue);
		expect(ownChecker.isCorrect('aardvark'), isFalse);
		expect((await WordList.read(file)).words, ['Aardvark', 'kabis']);
		ownChecker.remove('kabis');
		expect(ownChecker.isCorrect('kabis'), isFalse);
		expect((await WordList.read(file)).words, ['Aardvark']);
		ownChecker.isOn = false;
		expect(ownChecker.misspelledIn('kabis'), isEmpty);
		await folder.delete(recursive: true);
	});

	testWidgets('suggestions open when the cursor rests on a misspelled word', (tester) async {
		systemSpellChecker = SpellChecker([FakeDictionary({'milk', 'mild', 'and'})]);
		addTearDown(() => systemSpellChecker = null);
		final editorKey = GlobalKey<NoteEditorState>();
		var isClosed = false;
		await tester.pumpWidget(MaterialApp(
			home: Scaffold(
				body: NoteEditor(
					key: editorKey,
					storage: NoteStorage(Directory.systemTemp),
					initialContent: 'Title\nmilk melk and\nand',
					savesAutomatically: false,
					fillsSpace: true,
					onApply: () => isClosed = true,
				),
			),
		));
		await tester.pump();
		final editor = editorKey.currentState!;
		final body = editor.bodyController;
		editor.bodyFocus.requestFocus();
		await tester.pump();
		final menu = find.text(addToDictionaryLabel);

		Future<void> press(LogicalKeyboardKey key) async {
			await tester.sendKeyEvent(key);
			await tester.pump();
		}
		Future<void> restAt(int offset) async {
			body.selection = TextSelection.collapsed(offset: offset);
			await tester.pump();
			expect(menu, findsNothing);
			await tester.pump(spellingMenuDelay);
			await tester.pump();
		}

		await restAt(2);
		expect(menu, findsNothing);
		for (final key in [LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowUp]) {
			await restAt(7);
			expect(menu, findsOneWidget);
			await press(key);
			expect(menu, findsNothing);
			// Up on the first line moves on to the title
			if (key == LogicalKeyboardKey.arrowUp) {
				expect(editor.titleFocus.hasFocus, isTrue);
			} else {
				expect(body.selection.baseOffset, isNot(7));
			}
			editor.bodyFocus.requestFocus();
			await tester.pump();
		}

		await restAt(8);
		expect(menu, findsOneWidget);
		await press(LogicalKeyboardKey.escape);
		expect(menu, findsNothing);
		expect(isClosed, isFalse);

		// After Esc, not again until the cursor has left the word
		await restAt(7);
		expect(menu, findsNothing);
		await restAt(2);
		await restAt(6);
		expect(menu, findsOneWidget);
		await press(LogicalKeyboardKey.arrowDown);
		await press(LogicalKeyboardKey.arrowDown);
		await press(LogicalKeyboardKey.enter);
		expect(body.text, 'milk mild and\nand');
		expect(menu, findsNothing);
		expect(editor.bodyFocus.hasFocus, isTrue);

		body.value = const TextEditingValue(text: 'melk and', selection: TextSelection.collapsed(offset: 8));
		await restAt(2);
		await tester.tap(menu);
		await tester.pump();
		expect(menu, findsNothing);
		expect(body.misspelledWords, isEmpty);
		expect(editor.bodyFocus.hasFocus, isTrue);

		// Typing doesn't open it
		body.value = const TextEditingValue(text: 'mulk', selection: TextSelection.collapsed(offset: 4));
		await tester.pump(spellingMenuDelay * 2);
		expect(menu, findsNothing);
		await restAt(2);
		expect(menu, findsOneWidget);
		await tester.pumpWidget(const SizedBox());
		expect(tester.takeException(), isNull);
	}, variant: TargetPlatformVariant.only(TargetPlatform.linux));

	testWidgets('the row under the mouse is inverted in dropdowns', (tester) async {
		await tester.pumpWidget(MaterialApp(
			home: Scaffold(
				body: PopupMenuButton<int>(
					itemBuilder: (_) => const [
						TerminalMenuItem(value: 1, label: 'one', color: Color(0xFF00FF00)),
						TerminalMenuItem(value: 2, label: 'two', color: Color(0xFF00FF00)),
					],
				),
			),
		));
		await tester.tap(find.byType(PopupMenuButton<int>));
		await tester.pumpAndSettle();
		Color? colorOf(String label) => tester.widget<Text>(find.text(label)).style?.color;
		final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
		await mouse.addPointer(location: Offset.zero);
		for (final (hovered, other) in [('one', 'two'), ('two', 'one')]) {
			await mouse.moveTo(tester.getCenter(find.text(hovered)));
			await tester.pumpAndSettle();
			expect(colorOf(hovered), terminalBackground);
			expect(colorOf(other), const Color(0xFF00FF00));
		}
		await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
		await tester.pumpAndSettle();
		expect(colorOf('one'), terminalBackground);
		expect(colorOf('two'), const Color(0xFF00FF00));
		await mouse.removePointer();
	}, variant: TargetPlatformVariant.only(TargetPlatform.linux));

	testWidgets('the spelling shortcut opens suggestions that the keyboard can pick from', (tester) async {
		systemSpellChecker = SpellChecker([FakeDictionary({'milk', 'mild', 'and'})]);
		addTearDown(() => systemSpellChecker = null);
		final editorKey = GlobalKey<NoteEditorState>();
		var isClosed = false;
		await tester.pumpWidget(MaterialApp(
			home: Scaffold(
				body: NoteEditor(
					key: editorKey,
					storage: NoteStorage(Directory.systemTemp),
					initialContent: 'Title\nmilk melk and ',
					savesAutomatically: false,
					fillsSpace: true,
					onApply: () => isClosed = true,
				),
			),
		));
		await tester.pump();
		final editor = editorKey.currentState!;
		editor.bodyFocus.requestFocus();
		await tester.pump();
		editor.bodyController.selection = const TextSelection.collapsed(offset: 14);
		await tester.pump();

		Future<void> press(LogicalKeyboardKey key) async {
			await tester.sendKeyEvent(key);
			await tester.pumpAndSettle();
		}
		Future<void> openMenu() async {
			await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
			await tester.sendKeyEvent(LogicalKeyboardKey.period);
			await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
			await tester.pumpAndSettle();
		}

		await openMenu();
		expect(find.text(addToDictionaryLabel), findsOneWidget);
		await press(LogicalKeyboardKey.escape);
		expect(find.text(addToDictionaryLabel), findsNothing);
		expect(isClosed, isFalse);
		expect(editor.bodyFocus.hasFocus, isTrue);

		await openMenu();
		await press(LogicalKeyboardKey.arrowDown);
		await press(LogicalKeyboardKey.enter);
		expect(editor.bodyController.text, 'milk mild and ');
		expect(editor.bodyController.selection, const TextSelection.collapsed(offset: 14));
		expect(editor.bodyFocus.hasFocus, isTrue);

		await openMenu();
		expect(find.text(addToDictionaryLabel), findsNothing);
		await tester.pumpWidget(const SizedBox());
	}, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
