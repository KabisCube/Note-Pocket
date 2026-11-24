import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../notes/checklist_editing.dart';
import '../notes/emphasis_editing.dart';
import '../notes/note.dart';
import '../notes/note_storage.dart';
import '../notes/tag_completion.dart';
import '../spelling/spell_checker.dart';
import 'ascii_widgets.dart';
import 'checklist_controller.dart';
import 'inverted_selection.dart';
import 'send_screen.dart';
import 'shortcuts.dart';
import 'spelling_menu.dart';
import 'spelling_underlines.dart';
import 'tags_view.dart';
import 'terminal_theme.dart';

const autosaveDelay = Duration(seconds: 1);
const colorTagDelay = Duration(seconds: 1);
const titlePickerGap = 6.0;
const titleStyle = boldTextStyle;

// Fixed keys; the rest are in shortcuts.dart and can be changed in settings
// Esc leaves screens like settings, while closing a note uses its own changeable shortcut
const closeShortcut = SingleActivator(LogicalKeyboardKey.escape);
const completeShortcut = SingleActivator(LogicalKeyboardKey.tab);

// Labels
const saveNoteLabel = '[save]';
const unsavedMark = '*';
const saveErrorLabel = '[!]';
const deleteLabel = '[del]';
const sendLabel = '[send]';
const moreLabel = '[...]';
const addTagLabel = '#';
const outdentLabel = '[<<]';
const indentLabel = '[>>]';
const moveUpLabel = '[↑]';
const moveDownLabel = '[↓]';
const checkboxOptionLabel = '[ ] checkbox';
const bulletOptionLabel = '• bullet';
const addToDictionaryLabel = '[+] add to dictionary';
const deleteColorName = 'red';

const tagsHint = '#tags';
const titleHint = 'title';
const colorSwatch = '■';
const noColorName = 'none';
const noTooltip = '';

// A note's text split into what the editor's fields show
({String title, String? color, String body, List<String> tags}) parseEditorContent(String content) {
	final parts = splitTitle(content);
	final title = parseTitle(parts.title);
	final bodyParts = splitTags(normalizeChecklists(parts.body));
	return (title: title.text, color: title.color, body: bodyParts.body, tags: bodyParts.tags);
}

// A note's text as the editor would save it, which can differ from the file in small ways
// (older title forms, space indents), so opening a note never counts as a change by itself.
String editorFormOf(String content) {
	final parts = parseEditorContent(content);
	return joinTitle(formatTitle(parts.title, parts.color), joinTags(parts.body, parts.tags));
}

class NoteEditor extends StatefulWidget {
	const NoteEditor({
		super.key,
		required this.storage,
		this.note,
		required this.fillsSpace,
		required this.onApply,
		this.onSaved,
		this.onDeleted,
		this.extraActions = const [],
		this.initialTags = const [],
		this.tagColors = const {},
		this.knownTags = const [],
		this.onTagColorPicked,
		this.savesAutomatically = true,
		this.initialContent,
		this.revealText,
	});

	final NoteStorage storage;
	final Note? note;
	// Off when notes are only saved with the save shortcut; leaving with changes then asks first
	final bool savesAutomatically;
	// Unsaved text to start from instead of the note's file, like when a note being edited is maximized
	final String? initialContent;
	// The cursor starts at the end of the line with this text, like a reminder's line
	final String? revealText;
	final bool fillsSpace;
	final VoidCallback onApply;
	final void Function(String? previousPath, Note savedNote)? onSaved;
	final void Function(String? deletedPath)? onDeleted;
	final List<Widget> extraActions;
	final List<String> initialTags;
	final Map<String, String> tagColors;
	final List<String> knownTags;
	final Future<void> Function(String tag, String? colorName)? onTagColorPicked;

	@override
	State<NoteEditor> createState() => NoteEditorState();
}

class NoteEditorState extends State<NoteEditor> {
	Note? note;
	late final InvertedSelectionController titleController;
	late final ChecklistController bodyController;
	late final TagsController tagsController;
	late final SpellingMenu spellingMenu;
	late final bool isNewNote;
	// An opened note's name types itself out first, then turns into the editable title field
	late bool isTypingTitle;
	final bodyFocus = FocusNode();
	final bodyScroll = ScrollController();
	final titleFocus = FocusNode();
	final tagsFocus = FocusNode();
	final moreMenuKey = GlobalKey<PopupMenuButtonState<VoidCallback>>();
	late bool isShowingTags;
	Timer? autosaveTimer;
	Timer? colorTagTimer;
	// Saves run one after another. Each one catches its own errors, so a failed save never blocks the next.
	Future<void> saveQueue = Future.value();
	// What the file holds, in the editor's own form, to tell whether there are unsaved changes
	late String lastSavedContent;
	bool isShowingUnsaved = false;
	// Why the last save failed, until one succeeds
	String? saveError;
	late final AppLifecycleListener exitListener;
	String? titleColor;
	// Starts as the colors passed in, and follows colors picked here (a full-screen editor isn't rebuilt by the list)
	late Map<String, String> tagColors = {...widget.tagColors};

	({String text, String? color}) get typedTitle => parseTitle(titleController.text);
	String? get shownTitleColor => typedTitle.color ?? titleColor;

	// While tags are being typed, autosave keeps the tags from before, so the note doesn't move to another tag tab mid-typing
	List<String>? tagsBeforeTyping;

	String get content => contentWith(parseTagInput(tagsController.text));

	String get autosaveContent => contentWith(tagsBeforeTyping ?? parseTagInput(tagsController.text));

	String contentWith(List<String> tags) {
		final body = joinTags(bodyController.text, tags);
		return joinTitle(formatTitle(typedTitle.text, shownTitleColor), body);
	}

	@override
	void initState() {
		super.initState();
		note = widget.note;
		isNewNote = note == null;
		final draft = widget.initialContent;
		final parts = parseEditorContent(draft ?? note?.content ?? '');
		titleColor = parts.color;
		isTypingTitle = !isNewNote && parts.title.trim().isNotEmpty;
		titleController = InvertedSelectionController(text: parts.title)
			..focusNode = titleFocus
			..addListener(_scheduleAutosave)
			..addListener(_handleTitleChange);
		bodyController = ChecklistController(text: parts.body)
			..focusNode = bodyFocus
			..spellChecker = systemSpellChecker
			..addListener(_scheduleAutosave);
		spellingMenu = SpellingMenu(
			controller: bodyController,
			focusNode: bodyFocus,
			scrollController: bodyScroll,
			choicesFor: (word) => _spellingChoices(word, close: () => spellingMenu.close()),
		);
		final tags = note == null && draft == null ? widget.initialTags : parts.tags;
		lastSavedContent = note == null
			? contentWith(tags)
			: (draft == null ? contentWith(tags) : editorFormOf(note!.content));
		exitListener = AppLifecycleListener(onExitRequested: _handleExitRequest);
		tagsController = TagsController(text: formatTags(tags))
			..focusNode = tagsFocus
			..addListener(_scheduleAutosave)
			..addListener(() => setState(() {}));
		isShowingUnsaved = hasUnsavedChanges;
		isShowingTags = tags.isNotEmpty;
		titleFocus.addListener(() {
			if (!titleFocus.hasFocus) _applyTypedColorTag();
		});
		tagsFocus.addListener(() => setState(() {}));
		tagsFocus.addListener(() {
			if (tagsFocus.hasFocus) {
				tagsBeforeTyping ??= parseTagInput(tagsController.text);
				return;
			}
			tagsBeforeTyping = null;
			_tidyTags();
			_scheduleAutosave();
		});
		WidgetsBinding.instance.addPostFrameCallback((_) => _focusFirstField());
	}

	// Autofocus is skipped while something else has focus, like the note that was just opened with Enter,
	// so the field is focused by hand. An opened note gets the cursor at the end of its text.
	void _focusFirstField() {
		if (!mounted) return;
		if (isNewNote) {
			titleFocus.requestFocus();
			return;
		}
		bodyController.selection = TextSelection.collapsed(offset: _revealOffset() ?? bodyController.text.length);
		bodyFocus.requestFocus();
	}

	// The end of the first line holding revealText, if the body has one
	int? _revealOffset() {
		final reveal = widget.revealText;
		if (reveal == null || reveal.isEmpty) return null;
		final text = bodyController.text;
		final index = text.indexOf(reveal);
		return index == -1 ? null : lineAt(text, index).end;
	}

	@override
	void dispose() {
		exitListener.dispose();
		autosaveTimer?.cancel();
		colorTagTimer?.cancel();
		spellingMenu.dispose();
		titleController.dispose();
		bodyController.dispose();
		tagsController.dispose();
		bodyFocus.dispose();
		bodyScroll.dispose();
		titleFocus.dispose();
		tagsFocus.dispose();
		super.dispose();
	}

	void _handleTitleChange() {
		setState(() {});
		colorTagTimer?.cancel();
		colorTagTimer = Timer(colorTagDelay, _applyTypedColorTag);
	}

	void _applyTypedColorTag() {
		final title = typedTitle;
		if (title.color == null) return;
		titleColor = title.color;
		titleController.value = TextEditingValue(
			text: title.text,
			selection: TextSelection.collapsed(offset: title.text.length),
		);
	}

	void _applyTypedTagColors() {
		final typedColors = typedTagColors(tagsController.text);
		if (typedColors.isEmpty) return;
		if (mounted) setState(() => tagColors.addAll(typedColors));
		for (final entry in typedColors.entries) {
			widget.onTagColorPicked?.call(entry.key, entry.value);
		}
	}

	void _tidyTags() {
		_applyTypedTagColors();
		final tags = parseTagInput(tagsController.text);
		tagsController.text = formatTags(tags);
		if (tags.isEmpty) setState(() => isShowingTags = false);
	}

	void _showTags() {
		setState(() => isShowingTags = true);
		WidgetsBinding.instance.addPostFrameCallback((_) => tagsFocus.requestFocus());
	}

	// Up and Down move between the title, the body and the tags when the cursor can't go further in a field.
	// Lines are the ones drawn on screen, so wrapped lines are stepped through first.
	bool get _isPlainArrow {
		final keyboard = HardwareKeyboard.instance;
		return !keyboard.isShiftPressed && !keyboard.isControlPressed && !keyboard.isAltPressed && !keyboard.isMetaPressed;
	}

	// With a checkbox's box selected, x or space toggles it (caught here, before it is typed, so it animates)
	KeyEventResult _handleBodyKeys(FocusNode node, KeyEvent event) {
		if (spellingMenu.handleKey(event) == KeyEventResult.handled) return KeyEventResult.handled;
		final keyboard = HardwareKeyboard.instance;
		final isPlainCharacter = !keyboard.isControlPressed && !keyboard.isAltPressed && !keyboard.isMetaPressed;
		if (event is KeyDownEvent && isPlainCharacter && boxToggleCharacters.contains(event.character)) {
			if (bodyController.toggleSelectedBox()) return KeyEventResult.handled;
		}
		return _handleBodyArrows(node, event);
	}

	KeyEventResult _handleBodyArrows(FocusNode _, KeyEvent event) {
		final isDown = event.logicalKey == LogicalKeyboardKey.arrowDown;
		final isUp = event.logicalKey == LogicalKeyboardKey.arrowUp;
		if (event is KeyUpEvent || !(isDown || isUp) || !_isPlainArrow || !bodyController.selection.isCollapsed) {
			return KeyEventResult.ignored;
		}
		final renderEditable = _bodyEditable();
		if (renderEditable == null) return KeyEventResult.ignored;

		final shownLine = renderEditable.getLineAtOffset(bodyController.selection.extent);
		if (isDown && shownLine.end >= bodyController.text.length) {
			_focusTags();
			return KeyEventResult.handled;
		}
		if (isUp && shownLine.start == 0 && !isTypingTitle) {
			titleController.selection = TextSelection.collapsed(offset: titleController.text.length);
			titleFocus.requestFocus();
			return KeyEventResult.handled;
		}
		return KeyEventResult.ignored;
	}

	RenderEditable? _bodyEditable() => bodyFocus.context?.findAncestorStateOfType<EditableTextState>()?.renderEditable;

	void _openMoreMenu() => moreMenuKey.currentState?.showButtonMenu();

	// Right at the end of the title goes to the buttons beside it (the color button comes right after
	// the title), where Left and Right move between them. Up leaves the note, to whatever is above it.
	KeyEventResult _handleTitleArrows(FocusNode _, KeyEvent event) {
		if (event is KeyUpEvent || !_isPlainArrow) return KeyEventResult.ignored;
		final selection = titleController.selection;
		final isAtEnd = selection.isCollapsed && selection.baseOffset == titleController.text.length;
		if (event.logicalKey == LogicalKeyboardKey.arrowRight && isAtEnd) {
			titleFocus.nextFocus();
			return KeyEventResult.handled;
		}
		if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
			titleFocus.focusInDirection(TraversalDirection.up);
			return KeyEventResult.handled;
		}
		return _handleFieldArrow(event, LogicalKeyboardKey.arrowDown, 0);
	}

	KeyEventResult _handleFieldArrow(KeyEvent event, LogicalKeyboardKey key, int bodyCursor) {
		if (event is KeyUpEvent || event.logicalKey != key || !_isPlainArrow) return KeyEventResult.ignored;
		bodyController.selection = TextSelection.collapsed(offset: bodyCursor);
		bodyFocus.requestFocus();
		return KeyEventResult.handled;
	}

	void _focusTags() {
		if (!isShowingTags) {
			_showTags();
			return;
		}
		tagsController.selection = TextSelection.collapsed(offset: tagsController.text.length);
		tagsFocus.requestFocus();
	}

	bool get hasUnsavedChanges => content != lastSavedContent;

	// Saves now, with whatever tags are typed. Returns whether it worked.
	Future<bool> save() {
		autosaveTimer?.cancel();
		_applyTypedTagColors();
		return _queueSave(deleteIfEmpty: false, withTypedTags: true);
	}

	// Saves any changes before the note closes; a note left empty is deleted. Returns whether it worked.
	Future<bool> flush() {
		autosaveTimer?.cancel();
		_applyTypedTagColors();
		return _queueSave(deleteIfEmpty: true, withTypedTags: true);
	}

	// Called before the note closes. Saves (or asks first, when saving only on request), and
	// returns false when the note should stay open: the person chose to keep editing, or saving failed
	// and they don't want to lose the changes.
	Future<bool> confirmLeave() async {
		autosaveTimer?.cancel();
		// Nothing changed: nothing to write, so a new note left untouched isn't created either
		if (!hasUnsavedChanges) return true;
		final focusBefore = FocusManager.instance.primaryFocus;
		if (!widget.savesAutomatically) {
			final choice = await _askToSave();
			if (choice == null) return _stayAndRefocus(focusBefore);
			if (choice == _SaveChoice.discard) return true;
		}
		while (true) {
			if (await flush()) return true;
			if (!mounted) return true;
			final choice = await _askAfterSaveError();
			if (choice == null || choice == _SaveErrorChoice.keepEditing) return _stayAndRefocus(focusBefore);
			if (choice == _SaveErrorChoice.closeAnyway) return true;
		}
	}

	// Staying in the note puts the cursor back where it was (in the body when it was outside the note,
	// like on another note that was clicked), so typing goes on in the note instead of in the list.
	// The closing popup hands the focus back by itself at the end of the frame, so this waits for that.
	Future<bool> _stayAndRefocus(FocusNode? focusBefore) async {
		await WidgetsBinding.instance.endOfFrame;
		if (!mounted) return false;
		final wasInNote = focusBefore?.context?.findAncestorStateOfType<NoteEditorState>() == this;
		(wasInNote ? focusBefore! : bodyFocus).requestFocus();
		return false;
	}

	Future<AppExitResponse> _handleExitRequest() async {
		return await confirmLeave() ? AppExitResponse.exit : AppExitResponse.cancel;
	}

	void _scheduleAutosave() {
		_updateUnsavedMark();
		if (!widget.savesAutomatically) return;
		autosaveTimer?.cancel();
		autosaveTimer = Timer(autosaveDelay, () => _queueSave(deleteIfEmpty: false, withTypedTags: false));
	}

	void _updateUnsavedMark() {
		if (widget.savesAutomatically || !mounted) return;
		final isUnsaved = hasUnsavedChanges;
		if (isUnsaved != isShowingUnsaved) setState(() => isShowingUnsaved = isUnsaved);
	}

	Future<bool> _queueSave({required bool deleteIfEmpty, required bool withTypedTags}) {
		final result = saveQueue
			.then((_) => _writeNote(deleteIfEmpty: deleteIfEmpty, withTypedTags: withTypedTags))
			.then((_) {
				_showSaveError(null);
				return true;
			}, onError: (Object error) {
				_showSaveError(describeSaveError(error));
				return false;
			});
		saveQueue = result;
		return result;
	}

	void _showSaveError(String? error) {
		if (error == saveError) return;
		saveError = error;
		if (mounted) setState(() {});
	}

	Future<void> _writeNote({required bool deleteIfEmpty, required bool withTypedTags}) async {
		final currentContent = withTypedTags ? content : autosaveContent;
		final previousPath = note?.file.path;

		if (currentContent.trim().isEmpty) {
			if (!deleteIfEmpty || note == null) return;
			await widget.storage.delete(note!);
			note = null;
			lastSavedContent = currentContent;
			widget.onDeleted?.call(previousPath);
			return;
		}
		if (currentContent == note?.content) {
			_markSaved(currentContent);
			return;
		}

		final savedNote = await widget.storage.save(note, currentContent);
		note = savedNote;
		_markSaved(currentContent);
		widget.onSaved?.call(previousPath, savedNote);
	}

	void _markSaved(String savedContent) {
		lastSavedContent = savedContent;
		_updateUnsavedMark();
	}

	Future<_SaveChoice?> _askToSave() {
		return showChoiceDialog<_SaveChoice>(
			context: context,
			title: 'save changes? [y/n]',
			message: titleController.text.trim().isEmpty ? untitledName : titleController.text.trim(),
			accentColor: noteColor,
			choices: [
				(label: '[cancel]', key: LogicalKeyboardKey.escape, value: null),
				(label: '[n]', key: LogicalKeyboardKey.keyN, value: _SaveChoice.discard),
				(label: '[y]', key: LogicalKeyboardKey.keyY, value: _SaveChoice.save),
			],
		);
	}

	Future<_SaveErrorChoice?> _askAfterSaveError() {
		return showChoiceDialog<_SaveErrorChoice>(
			context: context,
			title: "[!] couldn't save this note",
			message: '$saveError\n\n[discard] closes it and loses the changes.',
			accentColor: titleColorFor(deleteColorName),
			outlineColor: titleColorFor(deleteColorName),
			choices: [
				(label: '[edit]', key: LogicalKeyboardKey.escape, value: _SaveErrorChoice.keepEditing),
				(label: '[discard]', key: null, value: _SaveErrorChoice.closeAnyway),
				(label: '[retry]', key: LogicalKeyboardKey.keyR, value: _SaveErrorChoice.retry),
			],
		);
	}

	void _showSaveErrorDetails() {
		showChoiceDialog<void>(
			context: context,
			title: "[!] couldn't save this note",
			message: '${saveError ?? ''}\n\nit is tried again with the next change.',
			accentColor: titleColorFor(deleteColorName),
			outlineColor: titleColorFor(deleteColorName),
			choices: [(label: '[ok]', key: LogicalKeyboardKey.escape, value: null)],
		);
	}

	Future<void> _openSend() async {
		final String sentContent;
		if (widget.savesAutomatically) {
			if (!await flush()) return;
			final savedNote = note;
			if (savedNote == null) return;
			sentContent = savedNote.content;
		} else {
			// The note is sent as it is in the editor, saved or not
			sentContent = content;
			if (sentContent.trim().isEmpty) return;
		}
		if (!mounted) return;
		final wasSent = await Navigator.push<bool>(
			context,
			MaterialPageRoute(builder: (_) => SendScreen(contents: [sentContent])),
		);
		if (wasSent == true) widget.onApply();
	}

	Future<void> _delete() async {
		// Enter keeps the note: the focus starts on [n]
		final confirmed = await showChoiceDialog<bool>(
			context: context,
			title: 'rm note? [y/n]',
			message: titleController.text.trim().isEmpty ? untitledName : titleController.text.trim(),
			accentColor: titleColorFor(deleteColorName),
			outlineColor: titleColorFor(deleteColorName),
			focusedChoice: 0,
			choices: [
				(label: '[n]', key: LogicalKeyboardKey.keyN, value: false),
				(label: '[y]', key: LogicalKeyboardKey.keyY, value: true),
			],
		);
		if (confirmed != true) return;

		await saveQueue;
		titleController.clear();
		bodyController.clear();
		tagsController.clear();
		autosaveTimer?.cancel();

		final deletedPath = note?.file.path;
		if (note != null) await widget.storage.delete(note!);
		note = null;
		widget.onDeleted?.call(deletedPath);
	}

	void _applyListType(LineType listType) {
		bodyController.value = toggleListType(bodyController.value, listType);
		bodyFocus.requestFocus();
	}

	void _changeIndent(int indentChange) {
		bodyController.value = changeIndent(bodyController.value, indentChange);
	}

	void _moveLines(int direction) {
		bodyController.value = moveLines(bodyController.value, direction);
	}

	void _toggleEmphasis(String mark) {
		bodyController.value = toggleEmphasis(bodyController.value, mark);
	}

	void _fromButton(VoidCallback edit) {
		edit();
		bodyFocus.requestFocus();
	}

	@override
	Widget build(BuildContext context) {
		final accentColor = titleColors[shownTitleColor];
		bodyController.checkboxColor = accentColor;
		tagsController
			..tagColors = tagColors
			..fallbackColor = accentColor == null ? terminalDimText : dulled(accentColor);
		final body = _buildBodyField();

		return CallbackShortcuts(
			bindings: keyBindings.callbacks({
				ShortcutAction.closeNote: widget.onApply,
				ShortcutAction.openMenu: _openMoreMenu,
				ShortcutAction.saveNote: save,
			}),
			child: TextSelectionTheme(
				data: TextSelectionTheme.of(context).copyWith(selectionColor: noteColor ?? terminalText),
				child: AsciiFrame(
					fillsSpace: widget.fillsSpace,
					padsContentSides: false,
					accentColor: accentColor,
					labelPadding: const EdgeInsets.only(left: frameLabelGap),
					label: Row(
						mainAxisSize: MainAxisSize.min,
						children: [
							Flexible(
								child: isTypingTitle
									? TypewriterText(
										titleController.text,
										style: _titleTextStyle(),
										showCursor: false,
										onFinished: () {
											if (mounted) setState(() => isTypingTitle = false);
										},
									)
									: IntrinsicWidth(child: _buildTitleField()),
							),
							const SizedBox(width: titlePickerGap),
							_buildColorPicker(),
							// In the title's own color, so it is easy to spot
							if (isShowingUnsaved)
								Padding(
									padding: EdgeInsets.only(right: saveError == null ? frameLabelGap : 0),
									child: Text(unsavedMark, style: TextStyle(color: titleColorFor(shownTitleColor))),
								),
							if (saveError != null)
								TextButton(
									onPressed: _showSaveErrorDetails,
									style: invertedButtonStyle(titleColorFor(deleteColorName)),
									child: const Text(saveErrorLabel),
								),
						],
					),
					actions: [
						if (!widget.savesAutomatically) TextButton(onPressed: save, child: const Text(saveNoteLabel)),
						_buildMoreMenu(accentColor ?? terminalAccent),
						...widget.extraActions,
					],
					bottomLabelPadding: isShowingTags
						? const EdgeInsets.only(left: frameLabelGap, right: frameLabelGap - textFieldCaretMargin)
						: frameButtonPadding,
					bottomLabel: isShowingTags ? _buildTagsRow() : _buildAddTagButton(accentColor ?? terminalAccent),
					bottomActions: [
						if (isPhone) ...[
							TextButton(onPressed: () => _fromButton(() => _moveLines(-1)), child: const Text(moveUpLabel)),
							TextButton(onPressed: () => _fromButton(() => _moveLines(1)), child: const Text(moveDownLabel)),
							TextButton(onPressed: () => _fromButton(() => _changeIndent(-1)), child: const Text(outdentLabel)),
							TextButton(onPressed: () => _fromButton(() => _changeIndent(1)), child: const Text(indentLabel)),
						],
					],
					child: body,
				),
			),
		);
	}

	TagCompletion get tagCompletion {
		if (!tagsFocus.hasFocus) return TagCompletion.none;
		return completeTag(tagsController.value, widget.knownTags);
	}

	void _acceptTagCompletion() {
		final completion = completeTag(tagsController.value, widget.knownTags);
		if (completion.isEmpty) return;
		tagsController.value = acceptTagCompletion(tagsController.value, completion);
		tagsFocus.requestFocus();
	}

	Widget _buildTagsRow() {
		return Row(
			mainAxisSize: MainAxisSize.min,
			children: [
				Flexible(child: IntrinsicWidth(child: _buildTagsField())),
				if (!tagCompletion.isEmpty)
					TextFieldTapRegion(
						child: GestureDetector(
							onTap: _acceptTagCompletion,
							child: Transform.translate(
								offset: const Offset(-textFieldCaretMargin, 0),
								child: CompletionGhost(completion: tagCompletion),
							),
						),
					),
			],
		);
	}

	Widget _buildAddTagButton(Color buttonColor) {
		return TextButton(
			onPressed: _showTags,
			style: invertedButtonStyle(buttonColor),
			child: const Text(addTagLabel),
		);
	}

	Widget _buildMoreMenu(Color buttonColor) {
		return PopupMenuButton<VoidCallback>(
			key: moreMenuKey,
			tooltip: noTooltip,
			padding: EdgeInsets.zero,
			onSelected: (action) => action(),
			itemBuilder: (_) => [
				TerminalMenuItem(value: () => _applyListType(LineType.unchecked), label: checkboxOptionLabel, color: terminalText),
				TerminalMenuItem(value: () => _applyListType(LineType.bullet), label: bulletOptionLabel, color: terminalText),
				TerminalMenuItem(value: _openSend, label: sendLabel, color: terminalText),
				TerminalMenuItem(value: _delete, label: deleteLabel, color: titleColorFor(deleteColorName)),
			],
			child: Padding(
				padding: compactButtonPadding,
				child: InvertedLabel(
					color: buttonColor,
					builder: (textColor) => Text(moreLabel, style: TextStyle(color: textColor)),
				),
			),
		);
	}

	@override
	void didUpdateWidget(NoteEditor oldWidget) {
		super.didUpdateWidget(oldWidget);
		tagColors = {...tagColors, ...widget.tagColors};
	}

	// Right-click (or long-press) on a tag offers its colors instead of the usual copy and paste.
	Widget _buildTagsContextMenu(BuildContext menuContext, EditableTextState editableTextState) {
		final tag = tagAtCursor(editableTextState.textEditingValue);
		final onTagColorPicked = widget.onTagColorPicked;
		if (tag == null || onTagColorPicked == null) {
			return AdaptiveTextSelectionToolbar.editableText(editableTextState: editableTextState);
		}
		return ColorContextMenu(
			anchor: editableTextState.contextMenuAnchors.primaryAnchor,
			onPicked: (name) {
				editableTextState.hideToolbar();
				final colorName = name == noTagColorName ? null : name;
				setState(() {
					if (colorName == null) {
						tagColors.remove(tag);
					} else {
						tagColors[tag] = colorName;
					}
				});
				onTagColorPicked(tag, colorName);
			},
		);
	}

	// The note color, or null for the app's accent color.
	Color? get noteColor => titleColors[shownTitleColor];

	// In a tag with its own color, the cursor takes that color.
	Color? get tagsCursorColor {
		final tag = tagAtCursor(tagsController.value);
		final tagColor = tag == null ? null : titleColors[tagColors[tag]];
		return tagColor ?? noteColor;
	}

	Widget _buildTagsField() {
		return CallbackShortcuts(
			bindings: {completeShortcut: _acceptTagCompletion},
			child: Focus(
				canRequestFocus: false,
				skipTraversal: true,
				onKeyEvent: (_, event) => _handleFieldArrow(event, LogicalKeyboardKey.arrowUp, bodyController.text.length),
				child: _buildTagsTextField(),
			),
		);
	}

	Widget _buildTagsTextField() {
		return TextField(
			controller: tagsController,
			focusNode: tagsFocus,
			contextMenuBuilder: _buildTagsContextMenu,
			cursorColor: tagsCursorColor,
			style: Theme.of(context).textTheme.bodyMedium,
			onSubmitted: (_) => bodyFocus.requestFocus(),
			decoration: InputDecoration.collapsed(
				hintText: tagsController.text.isEmpty ? tagsHint : null,
				hintStyle: TextStyle(color: terminalDimText),
			),
		);
	}

	void _setTitleColor(String colorName) {
		_applyTypedColorTag();
		setState(() => titleColor = colorName == noColorName ? null : colorName);
		_scheduleAutosave();
	}

	Widget _buildColorPicker() {
		return PopupMenuButton<String>(
			tooltip: noTooltip,
			padding: EdgeInsets.zero,
			onSelected: _setTitleColor,
			constraints: colorMenuConstraints,
			itemBuilder: (_) => colorMenuItems(),
			child: Padding(
				padding: compactButtonPadding,
				child: InvertedLabel(
					color: titleColorFor(shownTitleColor),
					builder: (textColor) => Text('[$colorSwatch]', style: TextStyle(color: textColor)),
				),
			),
		);
	}

	TextStyle? _titleTextStyle() {
		return Theme.of(context).textTheme.bodyMedium?.merge(titleStyle).copyWith(color: titleColorFor(shownTitleColor));
	}

	Widget _buildTitleField() {
		return Focus(
			canRequestFocus: false,
			skipTraversal: true,
			onKeyEvent: _handleTitleArrows,
			child: TextField(
				controller: titleController,
				focusNode: titleFocus,
				cursorColor: noteColor,
				style: _titleTextStyle(),
				textInputAction: TextInputAction.next,
				onSubmitted: (_) => bodyFocus.requestFocus(),
				decoration: InputDecoration.collapsed(hintText: titleHint, hintStyle: TextStyle(color: terminalDimText)),
			),
		);
	}

	Widget _buildBodyField() {
		return CallbackShortcuts(
			bindings: keyBindings.callbacks({
				ShortcutAction.indent: () => _changeIndent(1),
				ShortcutAction.outdent: () => _changeIndent(-1),
				ShortcutAction.moveLinesUp: () => _moveLines(-1),
				ShortcutAction.moveLinesDown: () => _moveLines(1),
				ShortcutAction.spelling: spellingMenu.openNearCursor,
				ShortcutAction.bold: () => _toggleEmphasis(boldMark),
				ShortcutAction.italic: () => _toggleEmphasis(italicMark),
				ShortcutAction.toggleCheckbox: bodyController.toggleSelectedCheckboxes,
			}),
			child: Focus(
				canRequestFocus: false,
				skipTraversal: true,
				onKeyEvent: _handleBodyKeys,
				child: Listener(
					onPointerDown: (event) {
						// A right-click only opens the menu
						final isRightClick = event.buttons == kSecondaryButton;
						spellingMenu.handlePointerDown(isRightClick: isRightClick);
						if (!isRightClick) bodyController.startTap();
					},
					child: LayoutBuilder(
						builder: (_, constraints) {
							bodyController.wrapWidth = constraints.maxWidth - frameSidePadding * 2;
							return SpellingUnderlines(
								controller: bodyController,
								scrollController: bodyScroll,
								findEditable: _bodyEditable,
								child: _buildBodyTextField(),
							);
						},
					),
				),
			),
		);
	}

	// Right-click (or long-press) on a misspelled word offers suggestions above the usual copy and paste.
	Widget _buildBodyContextMenu(BuildContext menuContext, EditableTextState editableTextState) {
		final editable = editableTextState.renderEditable;
		final clickPosition = editable.lastSecondaryTapDownPosition;
		final offset = clickPosition == null
			? bodyController.selection.extentOffset
			: editable.getPositionForPoint(clickPosition).offset;
		final word = bodyController.misspelledWordAt(offset);
		if (word == null) return AdaptiveTextSelectionToolbar.editableText(editableTextState: editableTextState);

		return FieldContextMenu(
			anchor: editableTextState.contextMenuAnchors.primaryAnchor,
			choices: [
				..._spellingChoices(word, close: editableTextState.hideToolbar),
				for (final item in editableTextState.contextMenuButtonItems)
					(
						label: AdaptiveTextSelectionToolbar.getButtonLabel(menuContext, item).toLowerCase(),
						color: terminalDimText,
						onTap: item.onPressed,
					),
			],
		);
	}

	List<FieldMenuChoice> _spellingChoices(TextRange word, {required VoidCallback close}) {
		final checker = bodyController.spellChecker;
		if (checker == null) return const [];
		final text = bodyController.text;
		final wordText = word.textInside(text);
		final line = lineAt(text, word.start);
		void pick(VoidCallback action) {
			close();
			action();
			bodyFocus.requestFocus();
		}

		return [
			for (final suggestion in checker.suggestionsFor(wordText, contexts: [text.substring(line.start, line.end), text]))
				(
					label: suggestion,
					color: noteColor ?? terminalAccent,
					onTap: () => pick(() => bodyController.replaceWord(word, suggestion)),
				),
			(label: addToDictionaryLabel, color: terminalText, onTap: () => pick(() => checker.add(wordText))),
		];
	}

	Widget _buildBodyTextField() {
		return TextField(
			controller: bodyController,
			scrollController: bodyScroll,
			contextMenuBuilder: _buildBodyContextMenu,
			focusNode: bodyFocus,
			cursorColor: noteColor,
			style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: noteColor),
			maxLines: null,
			expands: widget.fillsSpace,
			keyboardType: TextInputType.multiline,
			inputFormatters: [ChecklistFormatter()],
			decoration: const InputDecoration(
				isCollapsed: true,
				border: InputBorder.none,
				contentPadding: EdgeInsets.symmetric(horizontal: frameSidePadding),
			),
		);
	}
}


enum _SaveChoice { save, discard }

enum _SaveErrorChoice { keepEditing, closeAnyway, retry }

// A short reason for a failed save, like "Permission denied (/home/me/Notes/Groceries.txt)"
String describeSaveError(Object error) {
	if (error is FileSystemException) {
		final reason = error.osError?.message ?? error.message;
		return error.path == null ? reason : '$reason (${error.path})';
	}
	return '$error';
}
