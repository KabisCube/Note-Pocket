// The menu of spelling suggestions that opens by itself when the cursor rests on a misspelled word,
// or with the spelling shortcut. The note's text field keeps the focus, and passes its keys on:
// Down goes into the menu, Enter picks, Esc closes, and Left, Right, or Up out of the menu close it and
// move the cursor as usual. After Esc it stays closed until the cursor has left the word. Anything else that changes the text, the cursor or the scrolling closes it too.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'ascii_widgets.dart';
import 'checklist_controller.dart';

const spellingMenuDelay = Duration(milliseconds: 500);

class SpellingMenu {
	SpellingMenu({
		required this.controller,
		required this.focusNode,
		required this.scrollController,
		required this.choicesFor,
	}) : lastValue = controller.value {
		controller.addListener(_handleChange);
		focusNode.addListener(_handleFocusChange);
		scrollController.addListener(close);
	}

	final ChecklistController controller;
	final FocusNode focusNode;
	final ScrollController scrollController;
	final List<FieldMenuChoice> Function(TextRange word) choicesFor;
	final highlighted = ValueNotifier<int?>(null);
	TextEditingValue lastValue;
	Timer? restTimer;
	OverlayEntry? entry;
	List<FieldMenuChoice> choices = const [];
	// The list the note is in, which can scroll away under the menu
	ScrollPosition? outerScroll;
	TextRange? openWord;
	// The word the menu was closed on with Esc, until the cursor leaves it
	TextRange? dismissedWord;
	// A right-click opens the field's own menu instead
	bool wasRightClick = false;

	bool get isOpen => entry != null;

	void dispose() {
		close();
		controller.removeListener(_handleChange);
		focusNode.removeListener(_handleFocusChange);
		scrollController.removeListener(close);
		highlighted.dispose();
	}

	void close() {
		restTimer?.cancel();
		outerScroll?.removeListener(close);
		outerScroll = null;
		entry?.remove();
		entry?.dispose();
		entry = null;
	}

	void handlePointerDown({required bool isRightClick}) {
		wasRightClick = isRightClick;
		close();
	}

	void _handleFocusChange() {
		if (focusNode.hasFocus) return;
		dismissedWord = null;
		close();
	}

	// Only moving the cursor opens the menu, not typing
	void _handleChange() {
		final value = controller.value;
		final isMoved = value.selection != lastValue.selection;
		final isTyped = value.text != lastValue.text;
		lastValue = value;
		if (!isMoved && !isTyped) return;
		close();
		final isInDismissedWord = dismissedWord != null && _isCursorIn(dismissedWord!);
		if (isTyped || !isInDismissedWord) dismissedWord = null;
		if (isTyped || !focusNode.hasFocus || !value.selection.isCollapsed) return;
		restTimer = Timer(spellingMenuDelay, _openAtCursor);
	}

	bool _isCursorIn(TextRange word) {
		final cursor = controller.selection.extentOffset;
		return cursor >= word.start && cursor <= word.end;
	}

	void _openAtCursor() {
		if (wasRightClick || !focusNode.hasFocus || dismissedWord != null) return;
		final word = controller.misspelledWords.where(_isCursorIn).firstOrNull;
		if (word != null) _open(word);
	}

	// For the misspelled word at the cursor, or the closest before it, with the first choice highlighted
	Future<void> openNearCursor() async {
		final word = controller.misspelledWordNearCursor;
		if (word == null) return;
		close();
		final text = controller.text;
		_editableState()?.bringIntoView(TextPosition(offset: word.end));
		await WidgetsBinding.instance.endOfFrame;
		if (focusNode.hasFocus && controller.text == text) _open(word, highlightedIndex: 0);
	}

	EditableTextState? _editableState() => focusNode.context?.findAncestorStateOfType<EditableTextState>();

	void _open(TextRange word, {int? highlightedIndex}) {
		close();
		final state = _editableState();
		if (state == null) return;
		// From the second letter on, since the first one of a wrapped line has the indent in it
		final boxes = state.renderEditable.getBoxesForSelection(TextSelection(baseOffset: word.start + 1, extentOffset: word.end));
		if (boxes.isEmpty) return;
		final anchor = state.renderEditable.localToGlobal(Offset(boxes.first.left, boxes.first.bottom));

		openWord = word;
		choices = choicesFor(word);
		highlighted.value = highlightedIndex;
		outerScroll = Scrollable.maybeOf(state.context)?.position?..addListener(close);
		entry = OverlayEntry(
			// Part of the field, so a click in the menu doesn't take the focus from it
			builder: (_) => TextFieldTapRegion(
				child: FieldContextMenu(anchor: anchor, choices: choices, highlighted: highlighted),
			),
		);
		Overlay.of(state.context).insert(entry!);
	}

	KeyEventResult handleKey(KeyEvent event) {
		if (event is KeyUpEvent) return KeyEventResult.ignored;
		wasRightClick = false;
		final keyboard = HardwareKeyboard.instance;
		final hasModifier = keyboard.isShiftPressed || keyboard.isControlPressed || keyboard.isAltPressed || keyboard.isMetaPressed;
		if (!isOpen || hasModifier) return KeyEventResult.ignored;

		final index = highlighted.value;
		final key = event.logicalKey;
		if (key == LogicalKeyboardKey.escape) {
			dismissedWord = openWord;
			close();
			return KeyEventResult.handled;
		}
		if (key == LogicalKeyboardKey.arrowDown) {
			highlighted.value = index == null ? 0 : (index + 1).clamp(0, choices.length - 1);
			return KeyEventResult.handled;
		}
		if (key == LogicalKeyboardKey.arrowUp && index != null) {
			highlighted.value = index == 0 ? null : index - 1;
			return KeyEventResult.handled;
		}
		final isEnter = key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter;
		if (isEnter && index != null) {
			choices[index].onTap?.call();
			return KeyEventResult.handled;
		}
		if (isEnter || key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) close();
		return KeyEventResult.ignored;
	}
}
