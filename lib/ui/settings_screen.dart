// Settings: theme, accent color, notes folder, saving, spelling, keyboard shortcuts and sync.
// The notes folder can be typed, with Tab completing folder names like a terminal, or picked with
// the system's folder picker.
// A shortcut is changed by pressing [set] and then the new keys; Esc cancels. Keys already used by
// another action are allowed, with a warning.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../notes/note.dart';
import '../notes/note_storage.dart';
import '../notes/notes_folder.dart';
import '../notes/path_completion.dart';
import '../notes/tag_completion.dart';
import '../spelling/spell_checker.dart';
import 'ascii_widgets.dart';
import 'inverted_selection.dart';
import 'checklist_controller.dart';
import 'note_editor.dart';
import 'send_screen.dart';
import 'shortcuts.dart';
import 'tags_view.dart';
import 'terminal_theme.dart';

const settingsTitle = 'SETTINGS';
const saveLabel = '[save]';
const defaultLabel = '[use default]';
const sendAllLabel = '[send all notes]';
const openFolderLabel = '[open folder]';
const browseLabel = '[browse]';
const setShortcutLabel = '[set]';
const cancelShortcutLabel = '[cancel]';
const resetShortcutLabel = '[reset]';
const recordingHint = 'press the new keys, esc to cancel';
const autoSaveOption = 'as you type';
const manualSaveOption = 'on ctrl+s';
const spellingTitle = 'spellchecking';
const addedWordsTitle = 'words added to dictionary';
const onOption = 'on';
const offOption = 'off';
const removeWordLabel = '[x]';

// The file manager command for showing a folder on each desktop system
final fileManagerCommand = Platform.isWindows ? 'explorer' : (Platform.isMacOS ? 'open' : 'xdg-open');
final canOpenFolder = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
// Where spell checking works; without dictionaries the settings tell how to get it
bool get hasSpellingSettings => Platform.isLinux || systemSpellChecker != null;
const lineGap = 8.0;
const categoryGap = 28.0;
const shortcutKeysGap = 12.0;

class SettingsScreen extends StatefulWidget {
	const SettingsScreen({
		super.key,
		required this.currentFolder,
		required this.storage,
		required this.settings,
		required this.onNotesFolderChanged,
		required this.onThemeChanged,
		required this.onAccentColorChanged,
	});

	final String currentFolder;
	final NoteStorage storage;
	final AppSettings settings;
	final Future<void> Function(String? folderPath) onNotesFolderChanged;
	final Future<void> Function(String themeName) onThemeChanged;
	final Future<void> Function(String colorName) onAccentColorChanged;

	@override
	State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
	late final folderController = InvertedSelectionController(text: widget.currentFolder)
		..focusNode = folderFocus
		..addListener(_handleFolderTyped);
	final folderFocus = FocusNode();
	final recordingFocus = FocusNode();
	final pathStyle = PathStyle.current;
	String? defaultFolder;
	String? errorText;
	// The folder whose subfolders are offered for completion, and their names once read
	String? listedFolder;
	List<String> listedFolderNames = const [];
	ShortcutAction? recordingAction;
	String? shortcutNotice;

	@override
	void initState() {
		super.initState();
		folderFocus.addListener(() => setState(() {}));
		// Without a default folder (where the system can't say), the "default:" line is just left out
		defaultNotesFolder().then((folder) {
			if (mounted) setState(() => defaultFolder = folder);
		}, onError: (Object _) {});
	}

	@override
	void dispose() {
		folderController.dispose();
		folderFocus.dispose();
		recordingFocus.dispose();
		super.dispose();
	}

	String get typedFolder => expandHome(folderController.text.trim(), homeFolder, pathStyle);

	Future<void> _save() async {
		final folderPath = typedFolder;
		final problem = await checkUsableFolder(folderPath);
		if (problem != null) {
			setState(() => errorText = "[!] can't use that folder: $problem");
			return;
		}
		await _applyFolder(folderPath == defaultFolder ? null : folderPath);
	}

	Future<void> _browse() async {
		final Uri? picked;
		try {
			final startFolder = typedFolder;
			picked = await FilePicker.pickDirectory(
				dialogTitle: 'notes folder',
				initialDirectory: Directory(startFolder).existsSync() ? startFolder : null,
			);
		} on Object catch (error) {
			if (mounted) setState(() => errorText = "[!] couldn't open the folder picker: $error");
			return;
		}
		if (picked == null || !mounted) return;
		final folderPath = folderPathFromUri(picked);
		if (folderPath == null) {
			setState(() => errorText = "[!] can't use that folder: pick one on the device's own storage");
			return;
		}
		folderController.value = TextEditingValue(
			text: folderPath,
			selection: TextSelection.collapsed(offset: folderPath.length),
		);
		setState(() => errorText = null);
	}

	// Reads the folder being typed into, when it changes, so its subfolders can be offered
	void _handleFolderTyped() {
		final typed = splitTypedPath(folderController.text, pathStyle);
		final folder = typed == null ? null : expandHome(typed.folder, homeFolder, pathStyle);
		if (folder != listedFolder) {
			listedFolder = folder;
			listedFolderNames = const [];
			if (folder != null) {
				folderNamesIn(folder).then((names) {
					if (mounted && listedFolder == folder) setState(() => listedFolderNames = names);
				});
			}
		}
		setState(() {});
	}

	TagCompletion get folderCompletion {
		if (!folderFocus.hasFocus) return TagCompletion.none;
		return completePath(folderController.value, listedFolderNames, pathStyle);
	}

	bool _acceptFolderCompletion() {
		final completion = folderCompletion;
		if (completion.isEmpty) return false;
		folderController.value = acceptPathCompletion(folderController.value, completion, pathStyle);
		folderFocus.requestFocus();
		return true;
	}

	// Tab completes when there is something to complete, and otherwise moves on as usual
	KeyEventResult _handleFolderKeys(FocusNode _, KeyEvent event) {
		final isTab = event is! KeyUpEvent && completeShortcut.accepts(event, HardwareKeyboard.instance);
		return isTab && _acceptFolderCompletion() ? KeyEventResult.handled : KeyEventResult.ignored;
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

	Future<void> _pickSaveMode({required bool onlyOnRequest}) async {
		await widget.settings.setSavesOnlyOnRequest(onlyOnRequest);
		if (mounted) setState(() {});
	}

	void _toggleRecording(ShortcutAction action) {
		setState(() {
			shortcutNotice = null;
			recordingAction = recordingAction == action ? null : action;
		});
		if (recordingAction != null) recordingFocus.requestFocus();
	}

	KeyEventResult _recordShortcut(FocusNode _, KeyEvent event) {
		final action = recordingAction;
		if (action == null) return KeyEventResult.ignored;
		if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
			setState(() => recordingAction = null);
			return KeyEventResult.handled;
		}
		final activator = activatorFromEvent(event);
		if (activator == null) return KeyEventResult.handled;

		keyBindings.changed[action] = [activator];
		widget.settings.setShortcut(action.name, encodeActivators([activator]));
		final alsoUsedBy = keyBindings.actionsUsing(activator, except: action);
		setState(() {
			recordingAction = null;
			shortcutNotice = alsoUsedBy.isEmpty
				? null
				: '[!] ${describeActivator(activator)} is also used to ${alsoUsedBy.map((used) => used.description).join(', ')}';
		});
		return KeyEventResult.handled;
	}

	void _resetShortcut(ShortcutAction action) {
		keyBindings.changed.remove(action);
		widget.settings.setShortcut(action.name, null);
		setState(() {
			shortcutNotice = null;
			if (recordingAction == action) recordingAction = null;
		});
	}

	Widget _buildOption(String label, {required bool isSelected, required VoidCallback onPressed, Color? color}) {
		final shownColor = color ?? terminalAccent;
		return TextButton(
			onPressed: onPressed,
			style: invertedButtonStyle(isSelected ? shownColor : (color == null ? terminalDimText : dulled(color))),
			child: Text(isSelected ? '[$label]' : ' $label '),
		);
	}

	Widget _description(String text) => Text(text, style: TextStyle(color: terminalDimText));

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
								child: Focus(
									focusNode: recordingFocus,
									skipTraversal: true,
									onKeyEvent: _recordShortcut,
									child: ListView(
										children: [
											..._buildLooks(),
											const SizedBox(height: categoryGap),
											..._buildFolder(),
											const SizedBox(height: categoryGap),
											..._buildSaving(),
											if (hasSpellingSettings) ...[
												const SizedBox(height: categoryGap),
												..._buildSpelling(),
											],
											if (!isPhone) ...[
												const SizedBox(height: categoryGap),
												..._buildShortcuts(),
											],
											const SizedBox(height: categoryGap),
											..._buildSync(),
										],
									),
								),
							),
						),
					),
				),
			),
		);
	}

	List<Widget> _buildLooks() {
		return [
			const Text('theme'),
			Wrap(
				children: [
					for (final themeName in themeNames)
						_buildOption(themeName, isSelected: themeName == chosenThemeName, onPressed: () => _pickTheme(themeName)),
				],
			),
			const SizedBox(height: lineGap),
			const Text('accent color'),
			Wrap(
				children: [
					for (final colorName in titleColorNames)
						_buildOption(
							colorName,
							isSelected: accentColorName == colorName,
							color: titleColors[colorName]!,
							onPressed: () => _pickAccentColor(colorName),
						),
				],
			),
		];
	}

	List<Widget> _buildFolder() {
		final completion = folderCompletion;
		return [
			const Text('notes folder'),
			_description('every note is a .txt file in this folder. notes already there show up in the list. tab completes folder names.'),
			const SizedBox(height: lineGap),
			Row(
				children: [
					Flexible(
						child: Focus(
							canRequestFocus: false,
							skipTraversal: true,
							onKeyEvent: _handleFolderKeys,
							child: IntrinsicWidth(
								child: TextField(
									controller: folderController,
									focusNode: folderFocus,
									onSubmitted: (_) => _save(),
									decoration: const InputDecoration.collapsed(hintText: 'folder path'),
								),
							),
						),
					),
					if (!completion.isEmpty)
						TextFieldTapRegion(
							child: GestureDetector(
								onTap: _acceptFolderCompletion,
								child: Transform.translate(
									offset: const Offset(-textFieldCaretMargin, 0),
									child: CompletionGhost(completion: completion),
								),
							),
						),
				],
			),
			if (defaultFolder != null) _description('default: $defaultFolder'),
			if (errorText != null) ...[
				const SizedBox(height: lineGap),
				Text(errorText!),
			],
			const SizedBox(height: lineGap),
			Wrap(
				children: [
					TextButton(onPressed: _save, child: const Text(saveLabel)),
					TextButton(onPressed: _browse, child: const Text(browseLabel)),
					TextButton(onPressed: () => _applyFolder(null), child: const Text(defaultLabel)),
					if (canOpenFolder) TextButton(onPressed: _openFolder, child: const Text(openFolderLabel)),
				],
			),
		];
	}

	List<Widget> _buildSaving() {
		final onlyOnRequest = widget.settings.savesOnlyOnRequest;
		return [
			const Text('saving'),
			_description(
				'notes save as you type, or only with ${describeActivators(keyBindings.of(ShortcutAction.saveNote)).toLowerCase()} '
				'or $saveNoteLabel. leaving a note with unsaved changes then asks first.',
			),
			Wrap(
				children: [
					_buildOption(autoSaveOption, isSelected: !onlyOnRequest, onPressed: () => _pickSaveMode(onlyOnRequest: false)),
					_buildOption(manualSaveOption, isSelected: onlyOnRequest, onPressed: () => _pickSaveMode(onlyOnRequest: true)),
				],
			),
		];
	}

	List<Widget> _buildSpelling() {
		final checker = systemSpellChecker;
		if (checker == null) {
			return [
				const Text(spellingTitle),
				_description('no spell checker found. install enchant and a dictionary for your language, like aspell-en, and restart the app.'),
			];
		}
		final words = checker.addedWords.words;
		return [
			const Text(spellingTitle),
			Wrap(
				children: [
					_buildOption(onOption, isSelected: checker.isOn, onPressed: () => _setChecksSpelling(checker, true)),
					_buildOption(offOption, isSelected: !checker.isOn, onPressed: () => _setChecksSpelling(checker, false)),
				],
			),
			if (words.isNotEmpty) ...[
				const SizedBox(height: lineGap),
				const Text(addedWordsTitle),
				const SizedBox(height: lineGap),
				for (final word in words) _buildWordRow(checker, word),
			],
		];
	}

	// Laid out like the keyboard shortcuts
	Widget _buildWordRow(SpellChecker checker, String word) {
		return Row(
			children: [
				Expanded(
					child: HoverRow(
						children: [
							Expanded(child: Text(word)),
							const SizedBox(width: shortcutKeysGap),
							TextButton(
								onPressed: () => setState(() => checker.remove(word)),
								child: const Text(removeWordLabel),
							),
						],
					),
				),
				_buildResetSpace(),
			],
		);
	}

	// As wide as a [reset] button, to keep the buttons before it lined up
	Widget _buildResetSpace() {
		return Opacity(opacity: 0, child: IgnorePointer(child: TextButton(onPressed: null, child: const Text(resetShortcutLabel))));
	}

	Future<void> _setChecksSpelling(SpellChecker checker, bool isOn) async {
		checker.isOn = isOn;
		await widget.settings.setChecksSpelling(isOn);
		if (mounted) setState(() {});
	}

	List<Widget> _buildShortcuts() {
		return [
			const Text('keyboard shortcuts'),
			const SizedBox(height: lineGap),
			for (final action in ShortcutAction.values) _buildShortcutRow(action),
			if (shortcutNotice != null) ...[
				const SizedBox(height: lineGap),
				Text(shortcutNotice!),
			],
		];
	}

	Widget _buildShortcutRow(ShortcutAction action) {
		final isRecording = recordingAction == action;
		final isChanged = keyBindings.isChanged(action);
		return Row(
			children: [
				Expanded(
					child: HoverRow(
						children: [
							Expanded(child: Text(action.description)),
							const SizedBox(width: shortcutKeysGap),
							Text(
								isRecording ? recordingHint : describeActivators(keyBindings.of(action)),
								style: TextStyle(color: isRecording ? terminalAccent : terminalDimText),
							),
							const SizedBox(width: shortcutKeysGap),
							TextButton(
								onPressed: () => _toggleRecording(action),
								child: Text(isRecording ? cancelShortcutLabel : setShortcutLabel),
							),
							if (isChanged)
								TextButton(onPressed: () => _resetShortcut(action), child: const Text(resetShortcutLabel)),
						],
					),
				),
				if (!isChanged) _buildResetSpace(),
			],
		);
	}

	List<Widget> _buildSync() {
		return [
			const Text('sync'),
			_description('send every note to another device, one at a time. the other device reviews each one.'),
			Align(
				alignment: Alignment.centerLeft,
				child: TextButton(onPressed: _sendAll, child: const Text(sendAllLabel)),
			),
		];
	}
}
