import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../notes/checklist_editing.dart';
import '../notes/note.dart';
import '../notes/note_storage.dart';
import '../notes/tag_completion.dart';
import 'ascii_widgets.dart';
import 'checklist_controller.dart';
import 'send_screen.dart';
import 'tags_view.dart';
import 'terminal_theme.dart';

const autosaveDelay = Duration(seconds: 1);
const colorTagDelay = Duration(seconds: 1);
const titlePickerGap = 6.0;
const titleStyle = boldTextStyle;

// Shortcuts
const closeShortcut = SingleActivator(LogicalKeyboardKey.escape);
const toggleCheckboxShortcut = SingleActivator(LogicalKeyboardKey.enter, control: true);
// The same shortcut as in Obsidian
const toggleCheckboxAlternativeShortcut = SingleActivator(LogicalKeyboardKey.keyL, control: true);
// The usual Windows keys for opening a menu
const openMenuShortcut = SingleActivator(LogicalKeyboardKey.f10, shift: true);
const openMenuKeyShortcut = SingleActivator(LogicalKeyboardKey.contextMenu);
const indentShortcut = SingleActivator(LogicalKeyboardKey.tab);
const outdentShortcut = SingleActivator(LogicalKeyboardKey.tab, shift: true);
const completeShortcut = SingleActivator(LogicalKeyboardKey.tab);
const moveUpShortcut = SingleActivator(LogicalKeyboardKey.arrowUp, control: true);
const moveDownShortcut = SingleActivator(LogicalKeyboardKey.arrowDown, control: true);

// Labels
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
const deleteColorName = 'red';

// Phones have no Tab or Ctrl keys, so they get line buttons at the bottom
final isPhone = Platform.isAndroid || Platform.isIOS;
const tagsHint = '#tags';
const titleHint = 'title';
const colorSwatch = '■';
const noColorName = 'none';
const noTooltip = '';

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
	});

	final NoteStorage storage;
	final Note? note;
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
	late final TextEditingController titleController;
	late final ChecklistController bodyController;
	late final TagsController tagsController;
	late final bool isNewNote;
	// An opened note's name types itself out first, then turns into the editable title field
	late bool isTypingTitle;
	final bodyFocus = FocusNode();
	final titleFocus = FocusNode();
	final tagsFocus = FocusNode();
	final moreMenuKey = GlobalKey<PopupMenuButtonState<VoidCallback>>();
	late bool isShowingTags;
	Timer? autosaveTimer;
	Timer? colorTagTimer;
	Future<void> saveQueue = Future.value();
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
		final parts = splitTitle(note?.content ?? '');
		final title = parseTitle(parts.title);
		titleColor = title.color;
		isTypingTitle = !isNewNote && title.text.trim().isNotEmpty;
		titleController = TextEditingController(text: title.text)
			..addListener(_scheduleAutosave)
			..addListener(_handleTitleChange);
		final bodyParts = splitTags(normalizeChecklists(parts.body));
		bodyController = ChecklistController(text: bodyParts.body)..addListener(_scheduleAutosave);
		final tags = note == null ? widget.initialTags : bodyParts.tags;
		tagsController = TagsController(text: formatTags(tags))
			..addListener(_scheduleAutosave)
			..addListener(() => setState(() {}));
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
		bodyController.selection = TextSelection.collapsed(offset: bodyController.text.length);
		bodyFocus.requestFocus();
	}

	@override
	void dispose() {
		autosaveTimer?.cancel();
		colorTagTimer?.cancel();
		titleController.dispose();
		bodyController.dispose();
		tagsController.dispose();
		bodyFocus.dispose();
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

	KeyEventResult _handleBodyArrows(FocusNode _, KeyEvent event) {
		final isDown = event.logicalKey == LogicalKeyboardKey.arrowDown;
		final isUp = event.logicalKey == LogicalKeyboardKey.arrowUp;
		if (event is KeyUpEvent || !(isDown || isUp) || !_isPlainArrow || !bodyController.selection.isCollapsed) {
			return KeyEventResult.ignored;
		}
		final renderEditable = bodyFocus.context?.findAncestorStateOfType<EditableTextState>()?.renderEditable;
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

	Future<void> flush() {
		autosaveTimer?.cancel();
		_applyTypedTagColors();
		return _queueSave(deleteIfEmpty: true);
	}

	void _scheduleAutosave() {
		autosaveTimer?.cancel();
		autosaveTimer = Timer(autosaveDelay, () => _queueSave(deleteIfEmpty: false));
	}

	Future<void> _queueSave({required bool deleteIfEmpty}) {
		return saveQueue = saveQueue.then((_) => _writeNote(deleteIfEmpty: deleteIfEmpty));
	}

	Future<void> _writeNote({required bool deleteIfEmpty}) async {
		final currentContent = deleteIfEmpty ? content : autosaveContent;
		final previousPath = note?.file.path;

		if (currentContent.trim().isEmpty) {
			if (!deleteIfEmpty || note == null) return;
			await widget.storage.delete(note!);
			note = null;
			widget.onDeleted?.call(previousPath);
			return;
		}
		if (currentContent == note?.content) return;

		final savedNote = await widget.storage.save(note, currentContent);
		note = savedNote;
		widget.onSaved?.call(previousPath, savedNote);
	}

	Future<void> _openSend() async {
		await flush();
		final savedNote = note;
		if (savedNote == null || !mounted) return;
		final wasSent = await Navigator.push<bool>(
			context,
			MaterialPageRoute(builder: (_) => SendScreen(contents: [savedNote.content])),
		);
		if (wasSent == true) widget.onApply();
	}

	Future<void> _delete() async {
		final confirmed = await showDialog<bool>(
			context: context,
			builder: (dialogContext) => AlertDialog(
				title: const Text('rm note? [y/n]'),
				actions: [
					TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('[n]')),
					TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('[y]')),
				],
			),
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

	void _fromButton(VoidCallback edit) {
		edit();
		bodyFocus.requestFocus();
	}

	@override
	Widget build(BuildContext context) {
		final accentColor = titleColors[shownTitleColor];
		bodyController.checkboxColor = accentColor ?? terminalAccent;
		tagsController
			..tagColors = tagColors
			..fallbackColor = accentColor == null ? terminalDimText : dulled(accentColor);
		final body = _buildBodyField();

		return CallbackShortcuts(
			bindings: {
				closeShortcut: widget.onApply,
				openMenuShortcut: _openMoreMenu,
				openMenuKeyShortcut: _openMoreMenu,
			},
			child: AsciiFrame(
				fillsSpace: widget.fillsSpace,
				padsContentSides: false,
				accentColor: accentColor,
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
					],
				),
				actions: [
					_buildMoreMenu(accentColor ?? terminalAccent),
					...widget.extraActions,
				],
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
			style: invertedFocusButtonStyle(buttonColor),
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
				PopupMenuItem(height: menuItemHeight, padding: menuItemPadding, value: () => _applyListType(LineType.unchecked), child: invertedWhenFocusedText(checkboxOptionLabel, terminalText)),
				PopupMenuItem(height: menuItemHeight, padding: menuItemPadding, value: () => _applyListType(LineType.bullet), child: invertedWhenFocusedText(bulletOptionLabel, terminalText)),
				PopupMenuItem(height: menuItemHeight, padding: menuItemPadding, value: _openSend, child: invertedWhenFocusedText(sendLabel, terminalText)),
				PopupMenuItem(height: menuItemHeight, padding: menuItemPadding, value: _delete, child: invertedWhenFocusedText(deleteLabel, titleColorFor(deleteColorName))),
			],
			child: InvertedWhenFocused(
				color: buttonColor,
				builder: (textColor) => Padding(
					padding: compactButtonPadding,
					child: Text(moreLabel, style: TextStyle(color: textColor)),
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
			child: InvertedWhenFocused(
				color: titleColorFor(shownTitleColor),
				builder: (textColor) => Padding(
					padding: compactButtonPadding,
					child: Text('[$colorSwatch]', style: TextStyle(color: textColor)),
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
			bindings: {
				indentShortcut: () => _changeIndent(1),
				outdentShortcut: () => _changeIndent(-1),
				moveUpShortcut: () => _moveLines(-1),
				moveDownShortcut: () => _moveLines(1),
				toggleCheckboxShortcut: bodyController.toggleSelectedCheckboxes,
				toggleCheckboxAlternativeShortcut: bodyController.toggleSelectedCheckboxes,
			},
			child: Focus(
				canRequestFocus: false,
				skipTraversal: true,
				onKeyEvent: _handleBodyArrows,
				child: Listener(
					onPointerDown: (_) => bodyController.isTapPending = true,
					child: LayoutBuilder(
						builder: (_, constraints) {
							bodyController.wrapWidth = constraints.maxWidth - frameSidePadding * 2;
							return _buildBodyTextField();
						},
					),
				),
			),
		);
	}

	Widget _buildBodyTextField() {
		return TextField(
			controller: bodyController,
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

