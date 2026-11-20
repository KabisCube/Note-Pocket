// The list of notes.
// On phones, tapping a note opens it full screen.
// On desktop, clicking a note edits it inline in its frame, and [^] opens it full screen.
// Dragging a note reorders the list; the order is saved by NoteOrder. On phones you hold a note
// first; with a mouse, the note's title is a handle that drags right away.
// Tag tabs at the top filter the list to notes with that tag. Swiping sideways moves between
// tabs, and long-pressing or right-clicking a tab picks that tag's color.
// Swipes are read from raw pointer events instead of a gesture detector, so they never
// compete with the list's scrolling.
// With a keyboard, Up and Down step between [recv] [settings], the tag tabs, the new note button and
// the notes, and Enter opens one. Left and Right switch tag tabs, like swiping, or move between
// [recv] and [settings]. Closing a note puts the focus back on it.
// Arrows typed in a text field are left alone.
// While editing, the list is updated from the editor's save callbacks instead of
// being reloaded, so notes don't jump around under the cursor.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../notes/checklist_editing.dart';
import '../notes/note.dart';
import '../notes/note_order.dart';
import '../notes/note_storage.dart';
import '../notes/notes_folder.dart';
import 'ascii_widgets.dart';
import 'checklist_controller.dart';
import 'note_edit_screen.dart';
import 'note_editor.dart';
import 'receive_screen.dart';
import 'settings_screen.dart';
import 'tags_view.dart';
import 'terminal_theme.dart';

const screenTitle = 'NOTE POCKET';
const emptyText = 'no notes here yet. press +';
const receiveLabel = '[recv]';
const settingsLabel = '[settings]';
const maximizeLabel = '[^]';
const allTagsLabel = 'all';

const listSpacing = 8.0;
const maxPreviewLines = 8;
const scrollDuration = Duration(milliseconds: 300);
const listCacheExtent = 100000.0;
const swipeMinimumSpeed = 300.0;
const swipeMaximumTime = Duration(milliseconds: 400);
const swipeMinimumSidewaysRatio = 2.0;
const focusScrollDuration = Duration(milliseconds: 150);

final opensNotesFullScreen = Platform.isAndroid || Platform.isIOS;

class NoteListScreen extends StatefulWidget {
	const NoteListScreen({
		super.key,
		required this.storage,
		required this.order,
		required this.settings,
		required this.onNotesFolderChanged,
		required this.onThemeChanged,
		required this.onAccentColorChanged,
	});

	final NoteStorage storage;
	final NoteOrder order;
	final AppSettings settings;
	final Future<void> Function(String? folderPath) onNotesFolderChanged;
	final Future<void> Function(String themeName) onThemeChanged;
	final Future<void> Function(String colorName) onAccentColorChanged;

	@override
	State<NoteListScreen> createState() => _NoteListScreenState();
}

class _NoteListScreenState extends State<NoteListScreen> {
	List<Note> notes = [];
	String? editingPath;
	bool isCreatingNote = false;
	GlobalKey<NoteEditorState> editorKey = GlobalKey();
	String? selectedTag;
	String? scrollTargetPath;
	// Bumped when coming back from another screen, so the title types itself out again
	int titleTypingRun = 0;
	Animation<double>? coveringScreenAnimation;
	final scrollTargetKey = GlobalKey();
	// The list rebuilds itself on every touch, to get ready for a possible drag. Reusing the items
	// built since this screen last rebuilt lets Flutter skip them, so a touch doesn't stall scrolling.
	final builtItems = <int, Widget>{};

	int? swipePointer;
	Offset swipeStartPosition = Offset.zero;
	Duration swipeStartTime = Duration.zero;
	VelocityTracker? swipeTracker;

	// Keyboard focus
	final listFocus = FocusNode();
	final newNoteFocus = FocusNode();
	final receiveFocus = FocusNode();
	final settingsFocus = FocusNode();
	// Has focus while anything in the note being edited in the list has it
	final editorAreaFocus = FocusNode(canRequestFocus: false, skipTraversal: true);
	final tabFocusNodes = <String?, FocusNode>{};
	final noteFocusNodes = <String, FocusNode>{};

	List<Note> get visibleNotes {
		if (selectedTag == null) return notes;
		return notes.where((note) => note.tags.contains(selectedTag)).toList();
	}

	List<String> get allTags => {for (final note in notes) ...note.tags}.toList()..sort();

	List<String> get newNoteTags => selectedTag == null ? const [] : [selectedTag!];

	Map<String, String> get tagColors => widget.settings.tagColors;

	@override
	void initState() {
		super.initState();
		_reload();
	}

	Future<void> _reload() async {
		final sortedNotes = await widget.order.sort(await widget.storage.loadAll());
		if (!mounted) return;
		setState(() {
			notes = sortedNotes;
			if (!allTags.contains(selectedTag)) selectedTag = null;
		});
		_saveOrder();
	}

	void _saveOrder() => widget.order.save(notes);

	Future<void> _stopEditing() async {
		await editorKey.currentState?.flush();
		if (!mounted) return;
		setState(() {
			editingPath = null;
			isCreatingNote = false;
			editorKey = GlobalKey();
		});
	}

	Future<void> _editInline(Note? note) async {
		await _stopEditing();
		setState(() {
			editingPath = note?.file.path;
			isCreatingNote = note == null;
		});
	}

	Future<void> _selectTag(String? tag) async {
		await _stopEditing();
		setState(() => selectedTag = tag);
	}

	void _startSwipe(PointerDownEvent event) {
		if (event.kind != PointerDeviceKind.touch) return;
		if (swipePointer != null) {
			swipePointer = null;
			return;
		}
		swipePointer = event.pointer;
		swipeStartPosition = event.position;
		swipeStartTime = event.timeStamp;
		swipeTracker = VelocityTracker.withKind(event.kind)..addPosition(event.timeStamp, event.position);
	}

	void _trackSwipe(PointerMoveEvent event) {
		if (event.pointer != swipePointer) return;
		swipeTracker?.addPosition(event.timeStamp, event.position);
	}

	void _cancelSwipe(PointerCancelEvent event) {
		if (event.pointer == swipePointer) swipePointer = null;
	}

	void _endSwipe(PointerUpEvent event) {
		final tracker = swipeTracker;
		if (event.pointer != swipePointer || tracker == null) return;
		swipePointer = null;

		final movement = event.position - swipeStartPosition;
		final isQuick = event.timeStamp - swipeStartTime <= swipeMaximumTime;
		final isSideways = movement.dx.abs() >= movement.dy.abs() * swipeMinimumSidewaysRatio;
		if (!isQuick || !isSideways) return;

		final speed = tracker.getVelocity().pixelsPerSecond.dx;
		if (speed.abs() < swipeMinimumSpeed) return;
		_swipeTags(speed < 0 ? 1 : -1);
	}

	Future<void> _swipeTags(int direction) async {
		final tabs = <String?>[null, ...allTags];
		final nextIndex = tabs.indexOf(selectedTag) + direction;
		if (nextIndex < 0 || nextIndex >= tabs.length) return;
		await _selectTag(tabs[nextIndex]);
	}

	Future<void> _pickTagColor(BuildContext tabContext, String tag) async {
		final tabBox = tabContext.findRenderObject() as RenderBox;
		await _pickTagColorAt(tag, tabBox.localToGlobal(tabBox.size.bottomLeft(Offset.zero)));
	}

	Future<void> _pickTagColorAt(String tag, Offset globalPosition) async {
		final colorName = await showTagColorMenu(context, globalPosition);
		if (colorName == null) return;
		await _setTagColor(tag, colorName == noTagColorName ? null : colorName);
	}

	Future<void> _setTagColor(String tag, String? colorName) async {
		await widget.settings.setTagColor(tag, colorName);
		if (mounted) setState(() {});
	}

	Future<void> _openReceive() async {
		await _stopEditing();
		if (!mounted) return;
		final receivedPath = await Navigator.push<String>(
			context,
			MaterialPageRoute(builder: (_) => ReceiveScreen(storage: widget.storage)),
		);
		await _reload();
		if (receivedPath != null) _scrollTo(receivedPath);
	}

	Future<void> _openSettings() async {
		await _stopEditing();
		if (!mounted) return;
		await Navigator.push(
			context,
			MaterialPageRoute(
				builder: (_) => SettingsScreen(
					currentFolder: widget.storage.folder.path,
					storage: widget.storage,
					onNotesFolderChanged: widget.onNotesFolderChanged,
					onThemeChanged: widget.onThemeChanged,
					onAccentColorChanged: widget.onAccentColorChanged,
				),
			),
		);
	}

	// Restarts the title the moment a screen on top of this one starts closing, so it never
	// shows fully drawn first.
	@override
	void didChangeDependencies() {
		super.didChangeDependencies();
		coveringScreenAnimation?.removeStatusListener(_handleCoveringScreenStatus);
		coveringScreenAnimation = ModalRoute.of(context)?.secondaryAnimation;
		coveringScreenAnimation?.addStatusListener(_handleCoveringScreenStatus);
	}

	@override
	void dispose() {
		coveringScreenAnimation?.removeStatusListener(_handleCoveringScreenStatus);
		listFocus.dispose();
		newNoteFocus.dispose();
		receiveFocus.dispose();
		settingsFocus.dispose();
		editorAreaFocus.dispose();
		for (final node in [...tabFocusNodes.values, ...noteFocusNodes.values]) {
			node.dispose();
		}
		super.dispose();
	}

	FocusNode _tabFocusFor(String? tag) => tabFocusNodes.putIfAbsent(tag, FocusNode.new);

	FocusNode _noteFocusFor(String path) => noteFocusNodes.putIfAbsent(path, FocusNode.new);

	// Each stop is the area that counts as "here" and the node that gets focus when moving to it
	// The note being edited in the list is a stop too, and moving to it puts the cursor in its text.
	List<({bool Function() isFocused, FocusNode target})> get _arrowKeyStops {
		final editorStop = (isFocused: () => editorAreaFocus.hasFocus, target: editorKey.currentState?.bodyFocus ?? editorAreaFocus);
		return [
			(isFocused: () => _isHeaderFocused, target: receiveFocus),
			if (allTags.isNotEmpty)
				(isFocused: () => tabFocusNodes.values.any((node) => node.hasFocus), target: _tabFocusFor(selectedTag)),
			(isFocused: () => newNoteFocus.hasFocus, target: newNoteFocus),
			if (isCreatingNote) editorStop,
			for (final note in visibleNotes)
				if (note.file.path == editingPath)
					editorStop
				else
					(isFocused: () => _noteFocusFor(note.file.path).hasFocus, target: _noteFocusFor(note.file.path)),
		];
	}

	bool get _isTyping {
		return FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<EditableTextState>() != null;
	}

	KeyEventResult _handleArrowKeys(FocusNode node, KeyEvent event) {
		final hasModifier = HardwareKeyboard.instance.isControlPressed
			|| HardwareKeyboard.instance.isAltPressed
			|| HardwareKeyboard.instance.isShiftPressed;
		if (event is KeyUpEvent || hasModifier || _isTyping) return KeyEventResult.ignored;
		return switch (event.logicalKey) {
			LogicalKeyboardKey.arrowDown => _stepThroughList(1),
			LogicalKeyboardKey.arrowUp => _stepThroughList(-1),
			LogicalKeyboardKey.arrowRight => _stepThroughTabs(1),
			LogicalKeyboardKey.arrowLeft => _stepThroughTabs(-1),
			_ => KeyEventResult.ignored,
		};
	}

	bool get _isHeaderFocused => receiveFocus.hasFocus || settingsFocus.hasFocus;

	// Switches to the next or previous tag tab and puts the focus on it.
	// In the header it moves between [recv] and [settings] instead.
	KeyEventResult _stepThroughTabs(int direction) {
		if (_isHeaderFocused) {
			(direction > 0 ? settingsFocus : receiveFocus).requestFocus();
			return KeyEventResult.handled;
		}
		final isOnListItem = listFocus.hasPrimaryFocus || _arrowKeyStops.any((stop) => stop.isFocused());
		if (!isOnListItem || editorAreaFocus.hasFocus) return KeyEventResult.ignored;
		if (allTags.isEmpty) return KeyEventResult.handled;
		_swipeTags(direction).then((_) {
			if (mounted) _focusAndShow(_tabFocusFor(selectedTag), direction);
		});
		return KeyEventResult.handled;
	}

	KeyEventResult _stepThroughList(int direction) {
		final stops = _arrowKeyStops;
		final current = stops.indexWhere((stop) => stop.isFocused());
		if (current == -1 && !listFocus.hasPrimaryFocus) return KeyEventResult.ignored;
		final firstStopBelowHeader = 1;
		final next = current == -1
			? (direction > 0 ? firstStopBelowHeader : 0)
			: (current + direction).clamp(0, stops.length - 1);
		_focusAndShow(stops[next].target, direction);
		return KeyEventResult.handled;
	}

	void _focusAndShow(FocusNode node, int direction) {
		node.requestFocus();
		final nodeContext = node.context;
		if (nodeContext == null) return;
		Scrollable.ensureVisible(
			nodeContext,
			duration: focusScrollDuration,
			alignmentPolicy: direction > 0
				? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
				: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
		);
	}

	void _focusNoteAfterBuild(String? path) {
		WidgetsBinding.instance.addPostFrameCallback((_) {
			if (!mounted) return;
			final isShown = path != null && visibleNotes.any((note) => note.file.path == path);
			isShown ? _noteFocusFor(path).requestFocus() : newNoteFocus.requestFocus();
		});
	}

	Future<void> _closeEditor() async {
		final closedPath = editingPath;
		await _stopEditing();
		_focusNoteAfterBuild(closedPath);
	}

	void _handleCoveringScreenStatus(AnimationStatus status) {
		if (status == AnimationStatus.reverse && mounted) setState(() => titleTypingRun++);
	}

	void _scrollTo(String path) {
		final isVisible = visibleNotes.any((note) => note.file.path == path);
		setState(() {
			if (!isVisible) selectedTag = null;
			scrollTargetPath = path;
		});
		WidgetsBinding.instance.addPostFrameCallback((_) {
			final targetContext = scrollTargetKey.currentContext;
			if (targetContext == null) return;
			Scrollable.ensureVisible(
				targetContext,
				duration: scrollDuration,
				curve: Curves.easeOut,
				alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
			);
		});
	}

	Future<void> _openFullScreen(Note? note) async {
		await _stopEditing();
		if (!mounted) return;
		var editedPath = note?.file.path;
		await Navigator.push(
			context,
			MaterialPageRoute(
				builder: (_) => NoteEditScreen(
					storage: widget.storage,
					note: note,
					initialTags: newNoteTags,
					tagColors: tagColors,
					knownTags: allTags,
					onTagColorPicked: _setTagColor,
					onSaved: (previousPath, savedNote) {
						editedPath = savedNote.file.path;
						_handleSaved(previousPath, savedNote);
					},
					onDeleted: (deletedPath) {
						editedPath = null;
						_handleDeleted(deletedPath);
					},
				),
			),
		);
		await _reload();
		final scrollPath = editedPath;
		if (scrollPath != null) _scrollTo(scrollPath);
		_focusNoteAfterBuild(scrollPath);
	}

	Future<void> _maximizeEditing() async {
		await editorKey.currentState?.flush();
		final editingNote = notes.where((note) => note.file.path == editingPath).firstOrNull;
		await _openFullScreen(editingNote);
	}

	void _open(Note? note) {
		opensNotesFullScreen ? _openFullScreen(note) : _editInline(note);
	}

	void _handleSaved(String? previousPath, Note savedNote) {
		setState(() {
			final index = notes.indexWhere((note) => note.file.path == previousPath);
			if (index == -1) {
				notes.insert(0, savedNote);
			} else {
				notes[index] = savedNote;
			}
			if (isCreatingNote || editingPath == previousPath) {
				editingPath = savedNote.file.path;
				isCreatingNote = false;
			}
		});
		_saveOrder();
	}

	void _handleDeleted(String? deletedPath) {
		setState(() {
			notes.removeWhere((note) => note.file.path == deletedPath);
			editingPath = null;
			isCreatingNote = false;
			editorKey = GlobalKey();
		});
		_saveOrder();
	}

	void _reorder(int oldIndex, int targetIndex) {
		final visible = visibleNotes;
		if (targetIndex == oldIndex) return;

		final movedNote = visible[oldIndex];
		final targetNote = visible[targetIndex];
		final isMovingDown = targetIndex > oldIndex;
		setState(() {
			notes.remove(movedNote);
			final targetPosition = notes.indexOf(targetNote);
			notes.insert(isMovingDown ? targetPosition + 1 : targetPosition, movedNote);
		});
		_saveOrder();
	}

	@override
	Widget build(BuildContext context) {
		final visible = visibleNotes;
		final tags = allTags;
		builtItems.clear();

		return Focus(
			focusNode: listFocus,
			autofocus: true,
			skipTraversal: true,
			onKeyEvent: _handleArrowKeys,
			child: _buildScaffold(visible, tags),
		);
	}

	Widget _buildScaffold(List<Note> visible, List<String> tags) {
		return Scaffold(
			body: SafeArea(
				child: Padding(
					padding: const EdgeInsets.all(screenPadding),
					child: AsciiFrame(
						fillsSpace: true,
						label: TypewriterText(screenTitle, key: ValueKey(titleTypingRun), style: screenTitleStyle, showCursor: false),
						actions: [
							TextButton(focusNode: receiveFocus, onPressed: _openReceive, child: const Text(receiveLabel)),
							TextButton(focusNode: settingsFocus, onPressed: _openSettings, child: const Text(settingsLabel)),
						],
						child: Column(
							crossAxisAlignment: CrossAxisAlignment.stretch,
							children: [
								if (tags.isNotEmpty) _buildTagTabs(tags),
								Expanded(
									child: Listener(
										onPointerDown: _startSwipe,
										onPointerMove: _trackSwipe,
										onPointerUp: _endSwipe,
										onPointerCancel: _cancelSwipe,
										child: ReorderableListView.builder(
										buildDefaultDragHandles: false,
										scrollCacheExtent: const ScrollCacheExtent.pixels(listCacheExtent),
										padding: const EdgeInsets.only(top: listSpacing),
										header: _buildHeader(visible.isEmpty),
										itemCount: visible.length,
										onReorderItem: _reorder,
										proxyDecorator: (child, _, _) => Material(color: terminalBackground, child: child),
										itemBuilder: (_, index) => builtItems.putIfAbsent(index, () => _buildItem(visible[index], index)),
										),
									),
								),
							],
						),
					),
				),
			),
		);
	}

	Widget _buildTagTabs(List<String> tags) {
		return Wrap(
			children: [
				_buildTagTab(allTagsLabel, null),
				for (final tag in tags) _buildTagTab('$tagMark$tag', tag),
			],
		);
	}

	Widget _buildTagTab(String label, String? tag) {
		final isSelected = selectedTag == tag;
		final tagColor = tag == null ? terminalText : tagColorFor(tag, tagColors, terminalText);
		return Builder(
			builder: (tabContext) => GestureDetector(
				onSecondaryTap: tag == null ? null : () => _pickTagColor(tabContext, tag),
				child: TextButton(
					focusNode: _tabFocusFor(tag),
					onPressed: () => _selectTag(tag),
					onLongPress: tag == null ? null : () => _pickTagColor(tabContext, tag),
					style: invertedFocusButtonStyle(isSelected ? tagColor : dulled(tagColor)),
					child: Text(isSelected ? '[$label]' : ' $label '),
				),
			),
		);
	}

	Widget _buildHeader(bool hasNoVisibleNotes) {
		return Column(
			crossAxisAlignment: CrossAxisAlignment.stretch,
			children: [
				_withSpacing(NewNoteButton(focusNode: newNoteFocus, onPressed: () => _open(null))),
				if (isCreatingNote) _withSpacing(_buildEditor(null)),
				if (hasNoVisibleNotes && !isCreatingNote) _withSpacing(const TypewriterText(emptyText)),
			],
		);
	}

	Widget _buildItem(Note note, int index) {
		final isEditing = note.file.path == editingPath;
		Widget item = isEditing
			? _buildEditor(note)
			: ReorderableDelayedDragStartListener(
				index: index,
				child: _NotePreview(
					note: note,
					focusNode: _noteFocusFor(note.file.path),
					tagColors: tagColors,
					onPickTagColor: _pickTagColorAt,
					dragIndex: index,
					onTap: () => _open(note),
					onMaximize: opensNotesFullScreen ? null : () => _openFullScreen(note),
				),
			);
		if (note.file.path == scrollTargetPath) item = KeyedSubtree(key: scrollTargetKey, child: item);
		return Padding(key: ValueKey(note.file.path), padding: const EdgeInsets.only(bottom: listSpacing), child: item);
	}

	Widget _withSpacing(Widget child) {
		return Padding(padding: const EdgeInsets.only(bottom: listSpacing), child: child);
	}

	Widget _buildEditor(Note? note) {
		return Focus(
			focusNode: editorAreaFocus,
			child: _buildNoteEditor(note),
		);
	}

	Widget _buildNoteEditor(Note? note) {
		return NoteEditor(
			key: editorKey,
			storage: widget.storage,
			note: note,
			initialTags: newNoteTags,
			tagColors: tagColors,
			knownTags: allTags,
			onTagColorPicked: _setTagColor,
			fillsSpace: false,
			onApply: _closeEditor,
			onSaved: _handleSaved,
			onDeleted: _handleDeleted,
			extraActions: [
				TextButton(onPressed: _maximizeEditing, child: const Text(maximizeLabel)),
			],
		);
	}
}

class _NotePreview extends StatelessWidget {
	const _NotePreview({
		required this.note,
		required this.focusNode,
		required this.tagColors,
		required this.onPickTagColor,
		required this.dragIndex,
		required this.onTap,
		this.onMaximize,
	});

	final Note note;
	final FocusNode focusNode;
	final Map<String, String> tagColors;
	final void Function(String tag, Offset globalPosition) onPickTagColor;
	final int dragIndex;
	final VoidCallback onTap;
	final VoidCallback? onMaximize;

	@override
	Widget build(BuildContext context) {
		final accentColor = titleColors[note.titleColor];
		final tags = note.tags;

		return InkWell(
			focusNode: focusNode,
			onTap: onTap,
			child: AsciiFrame(
				accentColor: accentColor,
				label: _buildTitle(),
				actions: [
					if (onMaximize != null)
						TextButton(onPressed: onMaximize, child: const Text(maximizeLabel)),
				],
				bottomLabel: tags.isEmpty
					? null
					: TagsRow(
						tags: tags,
						tagColors: tagColors,
						fallbackColor: accentColor == null ? terminalDimText : dulled(accentColor),
						onPickColor: onPickTagColor,
					),
				child: LayoutBuilder(
					builder: (context, constraints) {
						final textStyle = DefaultTextStyle.of(context).style.copyWith(color: accentColor);
						return Text.rich(
							checklistSpan(
								normalizeChecklists(note.body),
								tabWidth: tabWidthFor(context, textStyle),
								style: textStyle,
								checkboxColor: accentColor ?? terminalAccent,
								wrap: WrapSettings(
									width: constraints.maxWidth - wrapSafetyMargin,
									textStyle: textStyle,
									textScaler: MediaQuery.textScalerOf(context),
								),
							),
							maxLines: maxPreviewLines,
							overflow: TextOverflow.ellipsis,
						);
					},
				),
			),
		);
	}

	Widget _buildTitle() {
		final title = InvertedWhenFocused(
			color: titleColorFor(note.titleColor),
			builder: (textColor) => Text(
				note.title,
				style: titleStyle.copyWith(color: textColor),
				maxLines: 1,
				overflow: TextOverflow.ellipsis,
			),
		);
		if (opensNotesFullScreen) return title;
		return MouseRegion(
			cursor: SystemMouseCursors.grab,
			child: ReorderableDragStartListener(index: dragIndex, child: title),
		);
	}
}
