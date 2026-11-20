import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../notes/note.dart';
import '../notes/note_storage.dart';
import '../notes/notes_folder.dart';
import 'ascii_widgets.dart';
import 'note_editor.dart';
import 'send_screen.dart';
import 'terminal_theme.dart';

const settingsTitle = 'SETTINGS';
const saveLabel = '[save]';
const defaultLabel = '[use default]';
const sendAllLabel = '[send all notes]';
const openFolderLabel = '[open folder]';

// The file manager command for showing a folder on each desktop system
final fileManagerCommand = Platform.isWindows ? 'explorer' : (Platform.isMacOS ? 'open' : 'xdg-open');
final canOpenFolder = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
const lineGap = 8.0;

class SettingsScreen extends StatefulWidget {
	const SettingsScreen({
		super.key,
		required this.currentFolder,
		required this.storage,
		required this.onNotesFolderChanged,
		required this.onThemeChanged,
		required this.onAccentColorChanged,
	});

	final String currentFolder;
	final NoteStorage storage;
	final Future<void> Function(String? folderPath) onNotesFolderChanged;
	final Future<void> Function(String themeName) onThemeChanged;
	final Future<void> Function(String colorName) onAccentColorChanged;

	@override
	State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
	late final folderController = TextEditingController(text: widget.currentFolder);
	String? defaultFolder;
	String? errorText;

	@override
	void initState() {
		super.initState();
		defaultNotesFolder().then((folder) {
			if (mounted) setState(() => defaultFolder = folder);
		});
	}

	@override
	void dispose() {
		folderController.dispose();
		super.dispose();
	}

	Future<void> _save() async {
		final folderPath = folderController.text.trim();
		final problem = await checkUsableFolder(folderPath);
		if (problem != null) {
			setState(() => errorText = "[!] can't use that folder: $problem");
			return;
		}
		await _applyFolder(folderPath == defaultFolder ? null : folderPath);
	}

	Future<void> _sendAll() async {
		final notes = await widget.storage.loadAll();
		if (!mounted || notes.isEmpty) return;
		await Navigator.push(
			context,
			MaterialPageRoute(builder: (_) => SendScreen(contents: [for (final note in notes) note.content])),
		);
	}

	void _openFolder() => Process.run(fileManagerCommand, [widget.currentFolder]);

	Future<void> _pickTheme(String themeName) async {
		await widget.onThemeChanged(themeName);
		if (mounted) setState(() {});
	}

	Future<void> _pickAccentColor(String colorName) async {
		await widget.onAccentColorChanged(colorName);
		if (mounted) setState(() {});
	}

	Future<void> _applyFolder(String? folderPath) async {
		await widget.onNotesFolderChanged(folderPath);
		if (mounted) Navigator.pop(context);
	}

	Widget _buildAccentOption(String colorName, String label, Color color) {
		final isSelected = accentColorName == colorName;
		return TextButton(
			onPressed: () => _pickAccentColor(colorName),
			style: invertedFocusButtonStyle(isSelected ? color : dulled(color)),
			child: Text(isSelected ? '[$label]' : ' $label '),
		);
	}

	@override
	Widget build(BuildContext context) {
		return CallbackShortcuts(
			bindings: {closeShortcut: () => Navigator.pop(context)},
			child: Focus(
				autofocus: true,
				child: Scaffold(
					body: SafeArea(
						child: Padding(
							padding: const EdgeInsets.all(screenPadding),
							child: AsciiFrame(
								fillsSpace: true,
								label: const TypewriterText(settingsTitle, style: screenTitleStyle, showCursor: false),
								actions: [
									TextButton(onPressed: () => Navigator.pop(context), child: const Text(backLabel)),
								],
								child: ListView(
									children: [
										const Text('theme'),
										Wrap(
											children: [
												for (final themeName in themeNames)
													TextButton(
														onPressed: () => _pickTheme(themeName),
														style: invertedFocusButtonStyle(
															themeName == chosenThemeName ? terminalAccent : terminalDimText,
														),
														child: Text(themeName == chosenThemeName ? '[$themeName]' : ' $themeName '),
													),
											],
										),
										const SizedBox(height: lineGap),
										const Text('accent color'),
										Wrap(
											children: [
												for (final colorName in titleColorNames)
													_buildAccentOption(colorName, colorName, titleColors[colorName]!),
											],
										),
										const SizedBox(height: lineGap),
										const Text('notes folder'),
										Text(
											'every note is a .txt file in this folder. notes already there show up in the list.',
											style: TextStyle(color: terminalDimText),
										),
										const SizedBox(height: lineGap),
										TextField(
											controller: folderController,
											onSubmitted: (_) => _save(),
											decoration: const InputDecoration.collapsed(hintText: 'folder path'),
										),
										if (defaultFolder != null)
											Text('default: $defaultFolder', style: TextStyle(color: terminalDimText)),
										if (errorText != null) ...[
											const SizedBox(height: lineGap),
											Text(errorText!),
										],
										const SizedBox(height: lineGap),
										Row(
											children: [
												TextButton(onPressed: _save, child: const Text(saveLabel)),
												TextButton(onPressed: () => _applyFolder(null), child: const Text(defaultLabel)),
												if (canOpenFolder) TextButton(onPressed: _openFolder, child: const Text(openFolderLabel)),
											],
										),
										const SizedBox(height: lineGap),
										const Text('sync'),
										Text(
											'send every note to another device, one at a time. the other device reviews each one.',
											style: TextStyle(color: terminalDimText),
										),
										Align(
											alignment: Alignment.centerLeft,
											child: TextButton(onPressed: _sendAll, child: const Text(sendAllLabel)),
										),
									],
								),
							),
						),
					),
				),
			),
		);
	}
}
