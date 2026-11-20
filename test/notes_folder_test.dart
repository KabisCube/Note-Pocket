import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_pocket/notes/notes_folder.dart';
import 'package:note_pocket/ui/terminal_theme.dart';

void main() {
	test('settings are saved as key=value lines and read back', () async {
		final folder = await Directory.systemTemp.createTemp('note_pocket_settings');
		final file = File('${folder.path}/$settingsFileName');

		final settings = await AppSettings.read(file);
		expect(settings.notesFolder, isNull);
		await settings.setNotesFolder(r'D:\notes=work');
		expect(await file.readAsString(), r'notes_folder=D:\notes=work');

		final reloaded = await AppSettings.read(file);
		expect(reloaded.notesFolder, r'D:\notes=work');
		await reloaded.setNotesFolder(null);
		expect((await AppSettings.read(file)).notesFolder, isNull);
		await folder.delete(recursive: true);
	});

	test('the theme setting is saved and unknown names fall back to dark', () async {
		final folder = await Directory.systemTemp.createTemp('note_pocket_theme');
		final file = File('${folder.path}/$settingsFileName');
		await (await AppSettings.read(file)).setTheme(lightPalette.name);
		final reloaded = await AppSettings.read(file);
		expect(paletteNamed(reloaded.theme), lightPalette);
		expect(paletteNamed('no such theme'), darkPalette);
		expect(paletteNamed(null), darkPalette);
		await folder.delete(recursive: true);
	});

	testWidgets('without a picked theme, the theme follows the OS light or dark mode', (tester) async {
		addTearDown(() {
			tester.platformDispatcher.clearPlatformBrightnessTestValue();
			applyThemeName(darkPalette.name);
		});

		tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
		applyThemeName(null);
		expect(chosenThemeName, systemThemeName);
		expect(currentPalette, darkPalette);

		tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
		applyThemeName(systemThemeName);
		expect(currentPalette, lightPalette);

		applyThemeName(highContrastPalette.name);
		expect(currentPalette, highContrastPalette);
	});

	test('the accent color is green until another note color is saved', () async {
		final folder = await Directory.systemTemp.createTemp('note_pocket_accent');
		final file = File('${folder.path}/$settingsFileName');
		accentColorName = (await AppSettings.read(file)).accentColor ?? defaultAccentColorName;
		expect(terminalAccent, currentPalette.titleColors['green']);

		await (await AppSettings.read(file)).setAccentColor('blue');
		accentColorName = (await AppSettings.read(file)).accentColor ?? defaultAccentColorName;
		expect(terminalAccent, currentPalette.titleColors['blue']);
		accentColorName = defaultAccentColorName;
		await folder.delete(recursive: true);
	});

	test('a folder that can be created is usable, an empty path is not', () async {
		final folder = await Directory.systemTemp.createTemp('note_pocket_usable');
		expect(await checkUsableFolder('${folder.path}/new/notes'), isNull);
		expect(await checkUsableFolder('  '), isNotNull);
		await folder.delete(recursive: true);
	});
}
