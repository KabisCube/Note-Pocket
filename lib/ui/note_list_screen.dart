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
// Leaving the note being edited (Esc, another note, a tag tab, a screen on top) first lets the editor
// save, or ask, when notes are only saved on request. If it says to stay, nothing else happens.
// Reminders in the notes are checked every little while and shown as a popup, which can open the note
// at the reminder's line, closing any screen on top first.

import 'dart:async';

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../notes/checklist_editing.dart';
import '../notes/note.dart';
import '../notes/note_order.dart';
import '../notes/note_storage.dart';
import '../notes/notes_folder.dart';
import '../notes/reminders.dart';
import 'ascii_widgets.dart';
import 'checklist_controller.dart';
import 'note_edit_screen.dart';
import 'note_editor.dart';
import 'receive_screen.dart';
import 'settings_screen.dart';
import 'shortcuts.dart';
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
// Shown as the last row of a preview when the note has more than fits
const previewMoreText = '...';
const scrollDuration = Duration(milliseconds: 300);
const listCacheExtent = 100000.0;
const swipeMinimumSpeed = 300.0;
const swipeMaximumTime = Duration(milliseconds: 400);
const swipeMinimumSidewaysRatio = 2.0;
const focusScrollDuration = Duration(milliseconds: 150);
const reminderCheckInterval = Duration(seconds: 15);
const reminderTitle = '[!] reminder';
// Reminders are outlined in red so they stand out, whatever the note's color
const alertColorName = 'red';
const reminderOkLabel = '[ok]';
const reminderOpenLabel = '[open note]';

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
		this.reminderLog,
	});

	final NoteStorage storage;
	// Null leaves reminders off
	final ReminderLog? reminderLog;
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
	// The text whose line the note being opened inline starts at, like a reminder's line
	String? revealText;
	Timer? reminderTimer;
	final dueReminders = <Reminder>[];
	bool isShowingReminder = false;
	// A reminder's note to open once the screen on top of the list has closed
	({String path, String revealText})? pendingOpen;
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

	// Reloads when the app comes back to the front, to pick up notes added to the folder outside the app
	late final AppLifecycleListener lifecycleListener;

	@override
	void initState() {
		super.initState();
		lifecycleListener = AppLifecycleListener(onResume: _reload);
		if (widget.reminderLog != null) reminderTimer = Timer.periodic(reminderCheckInterval, (_) => _checkReminders());
		_reload();
	}

	bool get savesAutomatically => !widget.settings.savesOnlyOnRequest;

	Future<void> _reload() async {
		final loadedNotes = await widget.storage.loadAll();
		if (!mounted) return;
		// The note being edited is newer in memory than on disk, and an autosave may have
		// created or renamed its file while the folder was being read
		final editedNote = notes.where((note) => note.file.path == editingPath).firstOrNull;
		if (editedNote != null) {
			loadedNotes.removeWhere((note) => note.file.path == editedNote.file.path || !note.file.existsSync());
			loadedNotes.add(editedNote);
		}
		final sortedNotes = await widget.order.sort(loadedNotes);
		if (!mounted) return;
		setState(() {
			notes = sortedNotes;
			if (!allTags.contains(selectedTag)) selectedTag = null;
		});
		_saveOrder();
		_checkReminders();
	}

	void _saveOrder() => widget.order.save(notes);

	// Closes the note being edited inline, letting it save (or ask) first.
	// Returns false when it stays open, and the caller should then not go on.
	Future<bool> _stopEditing({bool asks = true}) async {
		final editor = editorKey.currentState;
		if (editor != null && asks && !await editor.confirmLeave()) return false;
		if (!mounted) return false;
		setState(() {
			editingPath = null;
			isCreatingNote = false;
			revealText = null;
			editorKey = GlobalKey();
		});
		return true;
	}

	Future<void> _editInline(Note? note, {String? reveal}) async {
		if (!await _stopEditing() || !mounted) return;
		setState(() {
			editingPath = note?.file.path;
			isCreatingNote = note == null;
			revealText = reveal;
		});
		if (note != null && reveal != null) _scrollTo(note.file.path);
	}

	Future<void> _selectTag(String? tag) async {
		if (!await _stopEditing() || !mounted) return;
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
		if (!await _stopEditing() || !mounted) return;
		final receivedPath = await Navigator.push<String>(
			context,
			MaterialPageRoute(builder: (_) => ReceiveScreen(storage: widget.storage)),
		);
		await _reload();
		if (receivedPath != null) _scrollTo(receivedPath);
		_openPendingReminder();
	}

	Future<void> _openSettings() async {
		if (!await _stopEditing() || !mounted) return;
		await Navigator.push(
			context,
			MaterialPageRoute(
				builder: (_) => SettingsScreen(
					currentFolder: widget.storage.folder.path,
					storage: widget.storage,
					settings: widget.settings,
					onNotesFolderChanged: widget.onNotesFolderChanged,
					onThemeChanged: widget.onThemeChanged,
					onAccentColorChanged: widget.onAccentColorChanged,
				),
			),
		);
		_openPendingReminder();
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
		lifecycleListener.dispose();
		reminderTimer?.cancel();
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

	KeyEventResult _handleKeys(FocusNode node, KeyEvent event) {
		if (_isNewNoteKey(event)) return _newNoteFromKey();
		// The note being edited closes with its shortcut even when the focus has wandered out of it
		final isEditing = editingPath != null || isCreatingNote;
		if (event is KeyDownEvent && isEditing && keyBindings.matches(ShortcutAction.closeNote, event)) {
			_closeEditor();
			return KeyEventResult.handled;
		}
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

	bool _isNewNoteKey(KeyEvent event) {
		return event is KeyDownEvent && keyBindings.matches(ShortcutAction.newNote, event);
	}

	// + starts a new note, but only from the plain list: not while a note is open or being typed in,
	// and not with settings, a maximized note or a popup on top
	KeyEventResult _newNoteFromKey() {
		final isOverview = !_isTyping
			&& editingPath == null
			&& !isCreatingNote
			&& (ModalRoute.of(context)?.isCurrent ?? true)
			&& !HardwareKeyboard.instance.isControlPressed
			&& !HardwareKeyboard.instance.isAltPressed;
		if (!isOverview) return KeyEventResult.ignored;
		_open(null);
		return KeyEventResult.handled;
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
		if (!await _stopEditing() || !mounted) return;
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

	// draft is unsaved text carried over from the note being edited inline, which then isn't asked about
	Future<void> _openFullScreen(Note? note, {String? draft, String? reveal, bool asks = true}) async {
		if (!await _stopEditing(asks: asks) || !mounted) return;
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
					savesAutomatically: savesAutomatically,
					initialContent: draft,
					revealText: reveal,
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
		_openPendingReminder();
	}

	// The note moves to the full-screen editor as it is: saved first when saving automatically,
	// otherwise with its unsaved changes carried along.
	Future<void> _maximizeEditing() async {
		final editor = editorKey.currentState;
		if (editor == null) return;
		if (savesAutomatically) {
			if (!await editor.flush()) return;
			await _openFullScreen(editor.note, asks: false);
			return;
		}
		final draft = editor.hasUnsavedChanges ? editor.content : null;
		await _openFullScreen(editor.note, draft: draft, asks: false);
	}

	void _open(Note? note, {String? reveal}) {
		opensNotesFullScreen ? _openFullScreen(note, reveal: reveal) : _editInline(note, reveal: reveal);
	}

	void _checkReminders() {
		final log = widget.reminderLog;
		if (log == null || !mounted) return;
		dueReminders.addAll(log.takeDue(notes, DateTime.now()));
		_showNextReminder();
	}

	// One popup at a time; ones that come due meanwhile wait their turn
	Future<void> _showNextReminder() async {
		if (isShowingReminder || dueReminders.isEmpty || !mounted) return;
		isShowingReminder = true;
		final reminder = dueReminders.removeAt(0);
		final note = notes.where((note) => note.file.path == reminder.notePath).firstOrNull;
		// Drawn in the note's own color, with its title like at the top of the note
		final noteColor = titleColors[note?.titleColor];
		final wantsNote = await showChoiceDialog<bool>(
			context: context,
			title: reminderTitle,
			accentColor: noteColor,
			outlineColor: titleColorFor(alertColorName),
			body: Column(
				crossAxisAlignment: CrossAxisAlignment.start,
				mainAxisSize: MainAxisSize.min,
				children: [
					Text(note?.title ?? untitledName, style: titleStyle.copyWith(color: titleColorFor(note?.titleColor))),
					Text(reminder.lineText, style: TextStyle(color: noteColor)),
				],
			),
			choices: [
				(label: reminderOkLabel, key: LogicalKeyboardKey.escape, value: false),
				(label: reminderOpenLabel, key: LogicalKeyboardKey.keyO, value: true),
			],
		);
		isShowingReminder = false;
		if (wantsNote == true && note != null && mounted) await _openReminderNote(note, reminder.lineText);
		_showNextReminder();
	}

	// With another screen on top, that screen is closed the usual way first (a note there may ask to save),
	// and the note opens once the list is back.
	Future<void> _openReminderNote(Note note, String lineText) async {
		final isListOnTop = ModalRoute.of(context)?.isCurrent ?? true;
		if (isListOnTop) {
			_open(note, reveal: lineText);
			return;
		}
		pendingOpen = (path: note.file.path, revealText: lineText);
		await Navigator.of(context).maybePop();
	}

	void _openPendingReminder() {
		final pending = pendingOpen;
		pendingOpen = null;
		if (pending == null || !mounted) return;
		final note = notes.where((note) => note.file.path == pending.path).firstOrNull;
		if (note != null) _open(note, reveal: pending.revealText);
	}

	void _handleSaved(String? previousPath, Note savedNote) {
		if (previousPath != null) widget.reminderLog?.renameNote(previousPath, savedNote.file.path);
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
			onKeyEvent: _handleKeys,
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
					style: invertedButtonStyle(isSelected ? tagColor : dulled(tagColor)),
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
			savesAutomatically: savesAutomatically,
			revealText: revealText,
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

// Hovering a note with the mouse inverts its title, the same as keyboard focus does.
class _NotePreview extends StatefulWidget {
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
	State<_NotePreview> createState() => _NotePreviewState();
}

class _NotePreviewState extends State<_NotePreview> {
	bool isHovered = false;
	// The title isn't inverted then, since a click goes to the button
	bool isButtonHovered = false;

	@override
	Widget build(BuildContext context) {
		final note = widget.note;
		final onMaximize = widget.onMaximize;
		final accentColor = titleColors[note.titleColor];
		final tags = note.tags;

		return InkWell(
			focusNode: widget.focusNode,
			onTap: widget.onTap,
			onHover: (hovered) {
				if (hovered != isHovered) setState(() => isHovered = hovered);
			},
			child: AsciiFrame(
				accentColor: accentColor,
				label: _buildTitle(),
				actions: [
					if (onMaximize != null)
						TextButton(
							onPressed: onMaximize,
							onHover: (hovered) => setState(() => isButtonHovered = hovered),
							child: const Text(maximizeLabel),
						),
				],
				bottomLabel: tags.isEmpty
					? null
					: TagsRow(
						tags: tags,
						tagColors: widget.tagColors,
						fallbackColor: accentColor == null ? terminalDimText : dulled(accentColor),
						onPickColor: widget.onPickTagColor,
					),
				child: _PreviewBody(body: note.body, accentColor: accentColor),
			),
		);
	}

	Widget _buildTitle() {
		final title = InvertedLabel(
			followsMouse: false,
			color: titleColorFor(widget.note.titleColor),
			isHighlighted: isHovered && !isButtonHovered,
			builder: (textColor) => Text(
				widget.note.title,
				style: titleStyle.copyWith(color: textColor),
				maxLines: 1,
				overflow: TextOverflow.ellipsis,
			),
		);
		if (opensNotesFullScreen) return title;
		return MouseRegion(
			cursor: SystemMouseCursors.grab,
			child: ReorderableDragStartListener(index: widget.dragIndex, child: title),
		);
	}
}

// A note's text in the list. When it has more than fits, the last row is just "..." instead.
// Whether it fits is only known once the text is laid out (checkboxes and indents are widgets
// inside it), so it is checked after the first frame and rebuilt if needed. Both versions are
// the same height, so the list doesn't move.
class _PreviewBody extends StatefulWidget {
	const _PreviewBody({required this.body, required this.accentColor});

	final String body;
	final Color? accentColor;

	@override
	State<_PreviewBody> createState() => _PreviewBodyState();
}

class _PreviewBodyState extends State<_PreviewBody> {
	final paragraphKey = GlobalKey();
	bool isCut = false;
	double? laidOutWidth;

	@override
	void didUpdateWidget(_PreviewBody oldWidget) {
		super.didUpdateWidget(oldWidget);
		if (widget.body != oldWidget.body || widget.accentColor != oldWidget.accentColor) isCut = false;
	}

	void _checkOverflow() {
		if (!mounted || isCut) return;
		final paragraph = paragraphKey.currentContext?.findRenderObject();
		if (paragraph is RenderParagraph && paragraph.didExceedMaxLines) setState(() => isCut = true);
	}

	@override
	Widget build(BuildContext context) {
		return LayoutBuilder(
			builder: (context, constraints) {
				if (constraints.maxWidth != laidOutWidth) {
					laidOutWidth = constraints.maxWidth;
					isCut = false;
				}
				if (!isCut) WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());

				final textStyle = DefaultTextStyle.of(context).style.copyWith(color: widget.accentColor);
				final text = Text.rich(
					checklistSpan(
						normalizeChecklists(widget.body),
						tabWidth: tabWidthFor(context, textStyle),
						style: textStyle,
						checkboxColor: widget.accentColor,
						wrap: WrapSettings(
							width: constraints.maxWidth - wrapSafetyMargin,
							textStyle: textStyle,
							textScaler: MediaQuery.textScalerOf(context),
						),
					),
					key: paragraphKey,
					maxLines: isCut ? maxPreviewLines - 1 : maxPreviewLines,
					overflow: TextOverflow.clip,
				);
				if (!isCut) return text;
				return Column(
					crossAxisAlignment: CrossAxisAlignment.start,
					mainAxisSize: MainAxisSize.min,
					children: [text, Text(previewMoreText, style: textStyle)],
				);
			},
		);
	}
}
