// Renders the README screenshots into docs/screenshots/. Run it with "tools/Take Screenshots.bat".
// The app runs on a copy of the demo notes in tools/screenshots/notes, so real notes are never shown.
// Flutter tests draw all text as blocks unless real fonts are loaded, so the app font is loaded
// from the system first. Symbols the font lacks (• ◦ ■) are normally drawn by the system's
// fallback font, which tests don't have, so a symbol font is loaded under the theme's fallback name.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_pocket/main.dart';
import 'package:note_pocket/notes/note_order.dart';
import 'package:note_pocket/notes/notes_folder.dart';
import 'package:note_pocket/ui/ascii_widgets.dart';
import 'package:note_pocket/ui/note_edit_screen.dart';
import 'package:note_pocket/ui/note_list_screen.dart';
import 'package:note_pocket/ui/terminal_theme.dart';

// Window, the same as the app's default size in windows/runner/main.cpp
const windowSize = Size(420, 800);
const pixelRatio = 2.0;

// Files
const demoNotesFolder = 'tools/screenshots/notes';
const demoOrderFile = 'tools/screenshots/order.txt';
const screenshotFolder = '../../docs/screenshots';
const mainViewScreenshot = '$screenshotFolder/main_view.png';
const maximizedNoteScreenshot = '$screenshotFolder/maximized_note.png';

// Fonts
const windowsFontFolder = r'C:\Windows\Fonts';
const appFontFiles = ['consola.ttf', 'consolab.ttf', 'consolai.ttf', 'consolaz.ttf'];
const symbolFontFile = 'seguisym.ttf';

// Timing
const fileWaitTime = Duration(milliseconds: 100);
const maxWaitRounds = 50;
const settleRounds = 3;
const transitionTime = Duration(seconds: 1);
final titleTypingTime = typingInterval * (screenTitle.length + 2);

// Position in order.txt of the note opened full screen
const maximizedNoteIndex = 1;

const demoTagColors = {
	'home': 'green',
	'shopping': 'yellow',
	'travel': 'cyan',
	'work': 'orange',
	'writing': 'purple',
	'music': 'pink',
};

Future<void> loadFonts() async {
	Future<ByteData> read(String fileName) async {
		final bytes = await File('$windowsFontFolder\\$fileName').readAsBytes();
		return ByteData.sublistView(bytes);
	}

	final appFont = FontLoader(terminalFont);
	for (final fileName in appFontFiles) {
		appFont.addFont(read(fileName));
	}
	await appFont.load();
	await (FontLoader(terminalFontFallback.first)..addFont(read(symbolFontFile))).load();
}

Future<(AppSettings, NoteOrder)> copyDemoNotes() async {
	final workFolder = await Directory.systemTemp.createTemp('note_pocket_screenshots');
	final notesFolder = await Directory('${workFolder.path}/notes').create();
	await for (final entry in Directory(demoNotesFolder).list()) {
		if (entry is File) await entry.copy('${notesFolder.path}/${entry.uri.pathSegments.last}');
	}
	final orderFile = await File(demoOrderFile).copy('${workFolder.path}/$orderFileName');
	final settings = AppSettings(File('${workFolder.path}/$settingsFileName'), {
		notesFolderKey: notesFolder.path,
		for (final entry in demoTagColors.entries) '$tagColorKeyPrefix${entry.key}': entry.value,
	});
	return (settings, NoteOrder(orderFile));
}

// Files are only read on the real clock, not the test's fake one, so frames are built on the real clock
// and real time is let pass between them, until the wanted widget shows up and a little after.
Future<void> waitFor(WidgetTester tester, Finder finder) async {
	Future<void> letFilesLoad() => tester.runAsync(() async {
		await tester.pump();
		await Future.delayed(fileWaitTime);
	});

	for (var round = 0; round < maxWaitRounds && finder.evaluate().isEmpty; round++) {
		await letFilesLoad();
	}
	expect(finder, findsWidgets);
	for (var round = 0; round < settleRounds; round++) {
		await letFilesLoad();
	}
	await tester.pump();
}

void main() {
	setUpAll(() async {
		await loadFonts();
		applyThemeName(darkPalette.name);
		EditableText.debugDeterministicCursor = true;
		WidgetsApp.debugAllowBannerOverride = false;
	});

	testWidgets('screenshots', (tester) async {
		tester.view.physicalSize = windowSize * pixelRatio;
		tester.view.devicePixelRatio = pixelRatio;
		addTearDown(tester.view.reset);

		await tester.runAsync(() async {
			final (settings, order) = await copyDemoNotes();
			await tester.pumpWidget(NotePocketApp(settings: settings, order: order));
		});
		await waitFor(tester, find.text(maximizeLabel));
		await tester.pump(titleTypingTime);
		await tester.pump(transitionTime);
		await expectLater(find.byType(NotePocketApp), matchesGoldenFile(mainViewScreenshot));

		await tester.runAsync(() => tester.tap(find.text(maximizeLabel).at(maximizedNoteIndex)));
		await waitFor(tester, find.byType(NoteEditScreen));
		await tester.pump(transitionTime);
		await tester.pump(titleTypingTime);
		await waitFor(tester, find.byType(NoteEditScreen));
		await expectLater(find.byType(NotePocketApp), matchesGoldenFile(maximizedNoteScreenshot));

		await tester.pumpWidget(const SizedBox());
	}, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
