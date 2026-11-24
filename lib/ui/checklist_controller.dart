// Text controller for the note body.
// - Draws list prefixes in the note color (plain text color for notes without one) and checked items
//   dimmed (checklistSpan, also used by previews).
//   Nested checkboxes and bullets get their own shapes: [ ] { } < > and • ◦ ▪.
//   Every shape has the same length as the text it replaces, so the cursor still lines up.
//   The "- " before a checkbox is drawn with no width, so checkboxes look like "[ ]" instead of "- [ ]".
// - Draws **bold** and *italic* text. The stars are shown dimmed on the cursor's line, so they can be
//   edited, and drawn with no width everywhere else. They stay in the text, so the cursor still lines up.
// - Draws each tab as a gap reaching to the next tab stop, like a text editor, since Flutter would draw
//   it as a single space. Stops are every tabSize columns from the start of the line; the font is
//   monospaced, so columns are counted, leaving out characters drawn with no width.
// - Wraps long list lines (and tab-indented lines) with a hanging indent, so wrapped text lines up
//   under the text instead of under the checkbox. Flutter can't indent wrapped lines by itself, so
//   the wrap points are worked out here: the space at each wrap point is drawn as a line break, and
//   the next character is drawn with the indent in front of it. Each still counts as one character,
//   so the cursor and selection keep working. The file itself is not changed.
// - Keeps the cursor out of checkbox prefixes, so they behave like a single symbol. Left from the
//   start of an item's text selects its box instead, drawn inverted, so x or space can toggle it.
// - Toggles a checkbox when it is tapped, or the selected ones with a shortcut, with a short ascii animation.
//   Tapping a box while several lines are selected sets all their boxes the same way.

import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../notes/checklist_editing.dart';
import '../notes/note.dart';
import 'ascii_widgets.dart';
import 'inverted_selection.dart';
import 'terminal_theme.dart';

const tabSize = 4;
// Wrapping is worked out a little narrower than the field, so Flutter never wraps a line first
const wrapSafetyMargin = 6.0;
const textFieldCaretMargin = 3.0;
const minimumWrapWidth = 40.0;
const hiddenTextStyle = TextStyle(fontSize: 0.01, color: Color(0x00000000));

class WrapSettings {
	const WrapSettings({required this.width, required this.textStyle, required this.textScaler});

	final double width;
	final TextStyle? textStyle;
	final TextScaler textScaler;
}

// The width of each tab in one line, by its position in the line.
// offset is where the text being drawn starts in that line, so parts of the line can look up their own tabs.
class _TabStops {
	const _TabStops(this.widths, this.tabWidth, [this.offset = 0]);

	final Map<int, double> widths;
	final double tabWidth;
	final int offset;

	_TabStops from(int start) => _TabStops(widths, tabWidth, offset + start);

	double at(int index) => widths[offset + index] ?? tabWidth;
}

// Walks the line counting the columns it takes up, and gives each tab the width that reaches the next stop.
_TabStops _tabStopsFor(String rawLine, List<({int start, int end})> hiddenRanges, double tabWidth) {
	if (!rawLine.contains(tabIndent)) return _TabStops(const {}, tabWidth);
	final columnWidth = tabWidth / tabSize;
	final widths = <int, double>{};
	var column = 0;
	for (var index = 0; index < rawLine.length; index++) {
		if (hiddenRanges.any((range) => index >= range.start && index < range.end)) continue;
		if (rawLine[index] == tabIndent) {
			final columns = tabSize - column % tabSize;
			widths[index] = columns * columnWidth;
			column += columns;
		} else {
			column++;
		}
	}
	return _TabStops(widths, tabWidth);
}

// The emphasis stars that are drawn with no width, as positions in the line.
List<({int start, int end})> _hiddenMarkRanges(String text, int textStart, {required bool showsMarks}) {
	if (showsMarks) return const [];
	return [
		for (final match in emphasisPattern.allMatches(text)) ...[
			(start: textStart + match.start, end: textStart + match.start + match[1]!.length),
			(start: textStart + match.end - match[1]!.length, end: textStart + match.end),
		],
	];
}

double _textWidth(String text, WrapSettings wrap) {
	final painter = TextPainter(
		text: TextSpan(text: text, style: wrap.textStyle),
		textDirection: TextDirection.ltr,
		textScaler: wrap.textScaler,
	)..layout();
	final width = painter.width;
	painter.dispose();
	return width;
}

class _StyleRun {
	const _StyleRun(this.start, this.end, this.style);

	final int start;
	final int end;
	final TextStyle? style;
}

// Splits text into plain parts, bold and italic parts, and the stars around them.
List<_StyleRun> _styleRuns(String text, TextStyle? textStyle, {required bool showsMarks}) {
	final baseStyle = textStyle ?? const TextStyle();
	final boldStyle = baseStyle.merge(boldTextStyle);
	final italicStyle = baseStyle.merge(italicTextStyle);
	final markStyle = showsMarks ? baseStyle.copyWith(color: terminalDimText) : baseStyle.merge(hiddenTextStyle);
	final runs = <_StyleRun>[];
	var position = 0;
	for (final match in emphasisPattern.allMatches(text)) {
		if (match.start > position) runs.add(_StyleRun(position, match.start, textStyle));
		final mark = match[1]!;
		final textStart = match.start + mark.length;
		final textEnd = match.end - mark.length;
		runs.addAll([
			_StyleRun(match.start, textStart, markStyle),
			_StyleRun(textStart, textEnd, mark == boldMark ? boldStyle : italicStyle),
			_StyleRun(textEnd, match.end, markStyle),
		]);
		position = match.end;
	}
	if (position < text.length) runs.add(_StyleRun(position, text.length, textStyle));
	return runs;
}

List<InlineSpan> _styledSpans(String text, List<_StyleRun> runs, int start, int end, _TabStops tabs) {
	return [
		for (final run in runs)
			if (run.end > start && run.start < end)
				TextSpan(
					style: run.style,
					children: _withTabGaps(text.substring(max(run.start, start), min(run.end, end)), tabs.from(max(run.start, start))),
				),
	];
}

List<InlineSpan> _styledText(String text, TextStyle? textStyle, _TabStops tabs, {required bool showsMarks}) {
	return _styledSpans(text, _styleRuns(text, textStyle, showsMarks: showsMarks), 0, text.length, tabs);
}

TextStyle? _styleAt(List<_StyleRun> runs, int index) {
	return runs.firstWhere((run) => index >= run.start && index < run.end).style;
}

// Positions of the spaces where the text wraps when laid out at the given width.
// Tabs are measured as placeholders of their real width; each still counts as one character.
List<int> _wrapSpaces(String text, List<_StyleRun> runs, double width, WrapSettings wrap, _TabStops tabs) {
	final tabWidths = <double>[];
	final painter = TextPainter(
		text: TextSpan(
			style: wrap.textStyle,
			children: [
				for (final run in runs)
					TextSpan(
						style: run.style,
						children: [
							for (final (index, part) in text.substring(run.start, run.end).split(tabIndent).indexed) ...[
								if (index > 0) const WidgetSpan(child: SizedBox.shrink()),
								if (part.isNotEmpty) TextSpan(text: part),
							],
						],
					),
			],
		),
		textDirection: TextDirection.ltr,
		textScaler: wrap.textScaler,
	);
	for (var index = 0; index < text.length; index++) {
		if (text[index] == tabIndent) tabWidths.add(tabs.at(index));
	}
	painter
		..setPlaceholderDimensions([
			for (final tabWidth in tabWidths)
				PlaceholderDimensions(size: Size(tabWidth, 0), alignment: PlaceholderAlignment.bottom),
		])
		..layout(maxWidth: width);

	final spaces = <int>[];
	var offset = 0;
	while (offset < text.length) {
		final lineEnd = painter.getLineBoundary(TextPosition(offset: offset)).end;
		if (lineEnd <= offset || lineEnd >= text.length) break;
		final space = text[lineEnd - 1] == ' ' ? lineEnd - 1 : (text[lineEnd] == ' ' ? lineEnd : null);
		if (space == null || space + 1 >= text.length) break;
		spaces.add(space);
		offset = space + 1;
	}
	painter.dispose();
	return spaces;
}

double tabWidthFor(BuildContext context, TextStyle? style) {
	final painter = TextPainter(
		text: TextSpan(text: ' ' * tabSize, style: style),
		textDirection: TextDirection.ltr,
		textScaler: MediaQuery.textScalerOf(context),
	)..layout();
	final width = painter.width;
	painter.dispose();
	return width;
}

TextSpan checklistSpan(
	String text, {
	required double tabWidth,
	TextStyle? style,
	Set<int> animatingLineStarts = const {},
	String? animatingMark,
	Color? checkboxColor,
	WrapSettings? wrap,
	int? lineWithMarksShown,
	int? lineWithBoxSelected,
}) {
	final textColor = style?.color;
	final checkedColor = textColor == null ? terminalDimText : dulled(textColor);
	final children = <InlineSpan>[];
	var lineStart = 0;
	for (final rawLine in text.split(lineBreak)) {
		if (lineStart > 0) children.add(const TextSpan(text: lineBreak));
		children.addAll(_lineSpans(
			rawLine,
			markOverride: animatingLineStarts.contains(lineStart) ? animatingMark : null,
			tabWidth: tabWidth,
			checkboxColor: checkboxColor ?? textColor ?? terminalText,
			checkedColor: checkedColor,
			wrap: wrap,
			showsMarks: lineStart == lineWithMarksShown,
			isBoxSelected: lineStart == lineWithBoxSelected,
		));
		lineStart += rawLine.length + lineBreak.length;
	}
	return TextSpan(style: style, children: children);
}

List<InlineSpan> _lineSpans(
	String rawLine, {
	required String? markOverride,
	required double tabWidth,
	required Color checkboxColor,
	required Color checkedColor,
	required WrapSettings? wrap,
	required bool showsMarks,
	required bool isBoxSelected,
}) {
	final line = noteSyntax.parse(rawLine);
	if (!line.isListItem) {
		final tabs = _tabStopsFor(rawLine, _hiddenMarkRanges(rawLine, 0, showsMarks: showsMarks), tabWidth);
		final leadingTabCount = RegExp('^$tabIndent*').firstMatch(rawLine)![0]!.length;
		if (wrap == null || leadingTabCount == 0) return _styledText(rawLine, null, tabs, showsMarks: showsMarks);
		return [
			..._withTabGaps(rawLine.substring(0, leadingTabCount), tabs),
			..._withHangingIndent(rawLine.substring(leadingTabCount), leadingTabCount * tabWidth, tabs.from(leadingTabCount), wrap, null, showsMarks),
		];
	}

	final indentEnd = noteSyntax.indentLength(line);
	final markStart = line.isCheckbox ? indentEnd + bulletPrefix.length : indentEnd;
	final prefixEnd = noteSyntax.prefixLength(line);
	final tabs = _tabStopsFor(rawLine, [
		(start: indentEnd, end: markStart),
		..._hiddenMarkRanges(line.text, prefixEnd, showsMarks: showsMarks),
	], tabWidth);
	final shownMark = line.isCheckbox
		? checkboxText(line.indent, markOverride ?? (line.isChecked ? checkedMark : uncheckedMark))
		: bulletMarkFor(line.indent);
	final markEnd = markStart + shownMark.length;
	final markStyle = isBoxSelected
		? TextStyle(color: terminalBackground, backgroundColor: checkboxColor)
		: TextStyle(color: checkboxColor);

	final afterMark = rawLine.substring(markEnd, prefixEnd);
	final textStyle = line.isChecked ? TextStyle(color: checkedColor) : null;
	final hangingIndent = wrap == null ? 0.0 : line.indent * tabWidth + _textWidth('$shownMark$afterMark', wrap);
	return [
		..._withTabGaps(rawLine.substring(0, indentEnd), tabs),
		if (markStart > indentEnd) TextSpan(text: rawLine.substring(indentEnd, markStart), style: hiddenTextStyle),
		TextSpan(text: shownMark, style: markStyle),
		TextSpan(text: afterMark),
		if (wrap == null)
			..._styledText(line.text, textStyle, tabs.from(prefixEnd), showsMarks: showsMarks)
		else
			..._withHangingIndent(line.text, hangingIndent, tabs.from(prefixEnd), wrap, textStyle, showsMarks),
	];
}

List<InlineSpan> _withHangingIndent(
	String text,
	double hangingIndent,
	_TabStops tabs,
	WrapSettings wrap,
	TextStyle? textStyle,
	bool showsMarks,
) {
	final availableWidth = wrap.width - hangingIndent;
	if (text.isEmpty || availableWidth < minimumWrapWidth) {
		return _styledText(text, textStyle, tabs, showsMarks: showsMarks);
	}

	final runs = _styleRuns(text, textStyle, showsMarks: showsMarks);
	final spans = <InlineSpan>[];
	var segmentStart = 0;
	for (final space in _wrapSpaces(text, runs, availableWidth, wrap, tabs)) {
		final firstCharacter = text[space + 1];
		final characterStyle = _styleAt(runs, space + 1);
		spans.addAll([
			..._styledSpans(text, runs, segmentStart, space, tabs),
			const TextSpan(text: lineBreak),
			WidgetSpan(
				alignment: PlaceholderAlignment.baseline,
				baseline: TextBaseline.alphabetic,
				child: Padding(
					padding: EdgeInsets.only(left: hangingIndent),
					child: firstCharacter == tabIndent
						? SizedBox(width: tabs.at(space + 1))
						: Text(firstCharacter, style: wrap.textStyle?.merge(characterStyle) ?? characterStyle),
				),
			),
		]);
		segmentStart = space + 2;
	}
	spans.addAll(_styledSpans(text, runs, segmentStart, text.length, tabs));
	return spans;
}

List<InlineSpan> _withTabGaps(String text, _TabStops tabs) {
	final spans = <InlineSpan>[];
	var partStart = 0;
	for (final part in text.split(tabIndent)) {
		if (partStart > 0) {
			spans.add(WidgetSpan(
				alignment: PlaceholderAlignment.bottom,
				child: SizedBox(width: tabs.at(partStart - 1)),
			));
		}
		if (part.isNotEmpty) spans.add(TextSpan(text: part));
		partStart += part.length + tabIndent.length;
	}
	return spans;
}

class ChecklistController extends TextEditingController with InvertedSelection {
	ChecklistController({super.text}) {
		addListener(_handleSelectionChange);
	}

	static final lastFrame = checkboxMarks.length - 1;

	// Null draws prefixes in the text color
	Color? checkboxColor;
	double? wrapWidth;
	bool isTapPending = false;
	// What was selected when the pointer went down, so a tap on a box can apply to all selected lines
	TextSelection? selectionBeforeTap;
	TextSelection previousSelection = const TextSelection.collapsed(offset: -1);
	Set<int> animatingLineStarts = {};
	int animationFrame = 0;
	Timer? animationTimer;

	@override
	void dispose() {
		animationTimer?.cancel();
		super.dispose();
	}

	// Called when a pointer goes down on the field, before the tap moves the cursor
	void startTap() {
		isTapPending = true;
		selectionBeforeTap = selection.isValid && !selection.isCollapsed ? selection : null;
	}

	bool get isBoxSelected => selectedCheckboxBox(value) != null;

	void _handleSelectionChange() {
		final wasTap = isTapPending;
		final selectionAtTap = selectionBeforeTap;
		final before = previousSelection;
		isTapPending = false;
		previousSelection = selection;
		if (!selection.isValid || !selection.isCollapsed) return;
		selectionBeforeTap = null;
		final cursor = selection.baseOffset;

		final tappedCheckboxLine = wasTap ? checkboxLineStartAt(text, cursor) : null;
		if (tappedCheckboxLine != null) {
			final isInSelection = selectionAtTap != null && isLineSelected(text, selectionAtTap, tappedCheckboxLine);
			isInSelection ? _setSelectedCheckboxes(tappedCheckboxLine, selectionAtTap) : _toggleCheckbox(tappedCheckboxLine);
			return;
		}

		final adjusted = selectionOutsidePrefix(text, cursor, before, isTap: wasTap);
		if (adjusted != null) selection = adjusted;
	}

	void _toggleCheckbox(int lineStart) {
		final line = editorLineAt(text, lineStart);
		final prefixEnd = lineStart + noteSyntax.prefixLength(line);
		final updated = toggleCheckedAt(text, lineStart);
		_startAnimation(changedLineStarts(text, updated), toChecked: !line.isChecked);
		value = TextEditingValue(
			text: updated,
			selection: TextSelection.collapsed(offset: prefixEnd),
		);
	}

	// The tapped box decides: all selected boxes become what it becomes. The selection is kept.
	void _setSelectedCheckboxes(int tappedLineStart, TextSelection selectionAtTap) {
		final toChecked = !editorLineAt(text, tappedLineStart).isChecked;
		final updated = setCheckedLines(text, selectionAtTap, checked: toChecked);
		_startAnimation(updated.changedLineStarts.toSet(), toChecked: toChecked);
		value = TextEditingValue(text: updated.text, selection: selectionAtTap);
	}

	void toggleSelectedCheckboxes() {
		final updated = toggleCheckedLines(value);
		if (updated.text == text) return;
		final changed = changedLineStarts(text, updated.text);
		_startAnimation(changed, toChecked: editorLineAt(updated.text, changed.first).isChecked);
		value = updated;
	}

	// Toggles the checkbox whose box is selected, keeping it selected. Returns false when no box is selected.
	bool toggleSelectedBox() {
		final box = selectedCheckboxBox(value);
		if (box == null) return false;
		final updated = toggleCheckedAt(text, box.lineStart);
		_startAnimation(changedLineStarts(text, updated), toChecked: !editorLineAt(text, box.lineStart).isChecked);
		value = value.copyWith(text: updated);
		return true;
	}

	void _startAnimation(Set<int> lineStarts, {required bool toChecked}) {
		animationTimer?.cancel();
		if (lineStarts.isEmpty) return;
		final step = toChecked ? 1 : -1;
		animatingLineStarts = lineStarts;
		animationFrame = toChecked ? 0 : lastFrame;
		animationTimer = Timer.periodic(checkboxFrameInterval, (_) {
			final nextFrame = animationFrame + step;
			if (nextFrame < 0 || nextFrame > lastFrame) {
				animationTimer?.cancel();
				animatingLineStarts = {};
			} else {
				animationFrame = nextFrame;
			}
			notifyListeners();
		});
	}

	@override
	TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
		return withInvertedSelection(checklistSpan(
			text,
			tabWidth: tabWidthFor(context, style),
			style: style,
			animatingLineStarts: animatingLineStarts,
			animatingMark: checkboxMarks[animationFrame],
			checkboxColor: checkboxColor,
			lineWithMarksShown: selection.isValid ? lineAt(text, selection.extentOffset).start : null,
			lineWithBoxSelected: selectedCheckboxBox(value)?.lineStart,
			wrap: wrapWidth == null
				? null
				: WrapSettings(
					width: wrapWidth! - textFieldCaretMargin - wrapSafetyMargin,
					textStyle: style,
					textScaler: MediaQuery.textScalerOf(context),
				),
		));
	}
}
