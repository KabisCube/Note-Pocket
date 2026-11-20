// Text controller for the note body.
// - Draws list prefixes in the note color and checked items dimmed (checklistSpan, also used by previews).
//   Nested checkboxes and bullets get their own shapes: [ ] { } < > and • ◦ ▪.
//   Every shape has the same length as the text it replaces, so the cursor still lines up.
//   The "- " before a checkbox is drawn with no width, so checkboxes look like "[ ]" instead of "- [ ]".
// - Draws **bold** and *italic* text. The stars are shown dimmed on the cursor's line, so they can be
//   edited, and drawn with no width everywhere else. They stay in the text, so the cursor still lines up.
// - Draws each tab as a fixed-width gap, since Flutter would draw it as a single space.
// - Wraps long list lines (and tab-indented lines) with a hanging indent, so wrapped text lines up
//   under the text instead of under the checkbox. Flutter can't indent wrapped lines by itself, so
//   the wrap points are worked out here: the space at each wrap point is drawn as a line break, and
//   the next character is drawn with the indent in front of it. Each still counts as one character,
//   so the cursor and selection keep working. The file itself is not changed.
// - Keeps the cursor out of checkbox prefixes, so they behave like a single symbol.
// - Toggles a checkbox when it is tapped, or the selected ones with a shortcut, with a short ascii animation.

import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../notes/checklist_editing.dart';
import '../notes/note.dart';
import 'ascii_widgets.dart';
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

List<InlineSpan> _styledSpans(String text, List<_StyleRun> runs, int start, int end, double tabWidth) {
	return [
		for (final run in runs)
			if (run.end > start && run.start < end)
				TextSpan(
					style: run.style,
					children: _withTabGaps(text.substring(max(run.start, start), min(run.end, end)), tabWidth),
				),
	];
}

List<InlineSpan> _styledText(String text, TextStyle? textStyle, double tabWidth, {required bool showsMarks}) {
	return _styledSpans(text, _styleRuns(text, textStyle, showsMarks: showsMarks), 0, text.length, tabWidth);
}

TextStyle? _styleAt(List<_StyleRun> runs, int index) {
	return runs.firstWhere((run) => index >= run.start && index < run.end).style;
}

// Positions of the spaces where the text wraps when laid out at the given width.
List<int> _wrapSpaces(String text, List<_StyleRun> runs, double width, WrapSettings wrap) {
	final painter = TextPainter(
		text: TextSpan(
			style: wrap.textStyle,
			children: [
				for (final run in runs)
					TextSpan(text: text.substring(run.start, run.end).replaceAll(tabIndent, ' '), style: run.style),
			],
		),
		textDirection: TextDirection.ltr,
		textScaler: wrap.textScaler,
	)..layout(maxWidth: width);

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
	int? animatingLineStart,
	String? animatingMark,
	Color? checkboxColor,
	WrapSettings? wrap,
	int? lineWithMarksShown,
}) {
	final textColor = style?.color;
	final checkedColor = textColor == null ? terminalDimText : dulled(textColor);
	final children = <InlineSpan>[];
	var lineStart = 0;
	for (final rawLine in text.split(lineBreak)) {
		if (lineStart > 0) children.add(const TextSpan(text: lineBreak));
		final markOverride = lineStart == animatingLineStart ? animatingMark : null;
		final showsMarks = lineStart == lineWithMarksShown;
		children.addAll(_lineSpans(rawLine, markOverride, tabWidth, checkboxColor ?? terminalAccent, checkedColor, wrap, showsMarks));
		lineStart += rawLine.length + lineBreak.length;
	}
	return TextSpan(style: style, children: children);
}

List<InlineSpan> _lineSpans(
	String rawLine,
	String? markOverride,
	double tabWidth,
	Color checkboxColor,
	Color checkedColor,
	WrapSettings? wrap,
	bool showsMarks,
) {
	final line = noteSyntax.parse(rawLine);
	if (!line.isListItem) {
		final leadingTabCount = RegExp('^$tabIndent*').firstMatch(rawLine)![0]!.length;
		if (wrap == null || leadingTabCount == 0) return _styledText(rawLine, null, tabWidth, showsMarks: showsMarks);
		return [
			..._withTabGaps(rawLine.substring(0, leadingTabCount), tabWidth),
			..._withHangingIndent(rawLine.substring(leadingTabCount), leadingTabCount * tabWidth, tabWidth, wrap, null, showsMarks),
		];
	}

	final indentEnd = noteSyntax.indentLength(line);
	final markStart = line.isCheckbox ? indentEnd + bulletPrefix.length : indentEnd;
	final prefixEnd = noteSyntax.prefixLength(line);
	final shownMark = line.isCheckbox
		? checkboxText(line.indent, markOverride ?? (line.isChecked ? checkedMark : uncheckedMark))
		: bulletMarkFor(line.indent);
	final markEnd = markStart + shownMark.length;

	final afterMark = rawLine.substring(markEnd, prefixEnd);
	final textStyle = line.isChecked ? TextStyle(color: checkedColor) : null;
	final hangingIndent = wrap == null ? 0.0 : line.indent * tabWidth + _textWidth('$shownMark$afterMark', wrap);
	return [
		..._withTabGaps(rawLine.substring(0, indentEnd), tabWidth),
		if (markStart > indentEnd) TextSpan(text: rawLine.substring(indentEnd, markStart), style: hiddenTextStyle),
		TextSpan(text: shownMark, style: TextStyle(color: checkboxColor)),
		TextSpan(text: afterMark),
		if (wrap == null)
			..._styledText(line.text, textStyle, tabWidth, showsMarks: showsMarks)
		else
			..._withHangingIndent(line.text, hangingIndent, tabWidth, wrap, textStyle, showsMarks),
	];
}

List<InlineSpan> _withHangingIndent(
	String text,
	double hangingIndent,
	double tabWidth,
	WrapSettings wrap,
	TextStyle? textStyle,
	bool showsMarks,
) {
	final availableWidth = wrap.width - hangingIndent;
	if (text.isEmpty || availableWidth < minimumWrapWidth) {
		return _styledText(text, textStyle, tabWidth, showsMarks: showsMarks);
	}

	final runs = _styleRuns(text, textStyle, showsMarks: showsMarks);
	final spans = <InlineSpan>[];
	var segmentStart = 0;
	for (final space in _wrapSpaces(text, runs, availableWidth, wrap)) {
		final firstCharacter = text[space + 1];
		final characterStyle = _styleAt(runs, space + 1);
		spans.addAll([
			..._styledSpans(text, runs, segmentStart, space, tabWidth),
			const TextSpan(text: lineBreak),
			WidgetSpan(
				alignment: PlaceholderAlignment.baseline,
				baseline: TextBaseline.alphabetic,
				child: Padding(
					padding: EdgeInsets.only(left: hangingIndent),
					child: firstCharacter == tabIndent
						? SizedBox(width: tabWidth)
						: Text(firstCharacter, style: wrap.textStyle?.merge(characterStyle) ?? characterStyle),
				),
			),
		]);
		segmentStart = space + 2;
	}
	spans.addAll(_styledSpans(text, runs, segmentStart, text.length, tabWidth));
	return spans;
}

List<InlineSpan> _withTabGaps(String text, double tabWidth) {
	final parts = text.split(tabIndent);
	return [
		for (var index = 0; index < parts.length; index++) ...[
			if (index > 0)
				WidgetSpan(
					alignment: PlaceholderAlignment.bottom,
					child: SizedBox(width: tabWidth),
				),
			if (parts[index].isNotEmpty) TextSpan(text: parts[index]),
		],
	];
}

class ChecklistController extends TextEditingController {
	ChecklistController({super.text}) {
		addListener(_handleSelectionChange);
	}

	static final lastFrame = checkboxMarks.length - 1;

	Color checkboxColor = terminalAccent;
	double? wrapWidth;
	bool isTapPending = false;
	int previousCursor = -1;
	int? animatingLineStart;
	int animationFrame = 0;
	Timer? animationTimer;

	@override
	void dispose() {
		animationTimer?.cancel();
		super.dispose();
	}

	void _handleSelectionChange() {
		final cursor = selection.baseOffset;
		final wasTap = isTapPending;
		isTapPending = false;
		if (!selection.isCollapsed || cursor < 0) {
			previousCursor = cursor;
			return;
		}

		final tappedCheckboxLine = wasTap ? checkboxLineStartAt(text, cursor) : null;
		if (tappedCheckboxLine != null) {
			_toggleCheckbox(tappedCheckboxLine);
			return;
		}

		final adjustedCursor = cursorOutsidePrefix(text, cursor, previousCursor);
		previousCursor = adjustedCursor ?? cursor;
		if (adjustedCursor != null) selection = TextSelection.collapsed(offset: adjustedCursor);
	}

	void _toggleCheckbox(int lineStart) {
		final line = editorLineAt(text, lineStart);
		final prefixEnd = lineStart + noteSyntax.prefixLength(line);
		previousCursor = prefixEnd;
		_startAnimation(lineStart, toChecked: !line.isChecked);
		value = TextEditingValue(
			text: toggleCheckedAt(text, lineStart),
			selection: TextSelection.collapsed(offset: prefixEnd),
		);
	}

	void toggleSelectedCheckboxes() {
		final updated = toggleCheckedLines(value);
		if (updated.text == text) return;
		final lineStart = lineAt(text, selection.start).start;
		final isOneLine = lineStart == lineAt(text, selection.end).start;
		if (isOneLine) _startAnimation(lineStart, toChecked: !editorLineAt(text, lineStart).isChecked);
		value = updated;
	}

	void _startAnimation(int lineStart, {required bool toChecked}) {
		animationTimer?.cancel();
		final step = toChecked ? 1 : -1;
		animatingLineStart = lineStart;
		animationFrame = toChecked ? 0 : lastFrame;
		animationTimer = Timer.periodic(checkboxFrameInterval, (_) {
			final nextFrame = animationFrame + step;
			if (nextFrame < 0 || nextFrame > lastFrame) {
				animationTimer?.cancel();
				animatingLineStart = null;
			} else {
				animationFrame = nextFrame;
			}
			notifyListeners();
		});
	}

	@override
	TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
		return checklistSpan(
			text,
			tabWidth: tabWidthFor(context, style),
			style: style,
			animatingLineStart: animatingLineStart,
			animatingMark: checkboxMarks[animationFrame],
			checkboxColor: checkboxColor,
			lineWithMarksShown: selection.isValid ? lineAt(text, selection.extentOffset).start : null,
			wrap: wrapWidth == null
				? null
				: WrapSettings(
					width: wrapWidth! - textFieldCaretMargin - wrapSafetyMargin,
					textStyle: style,
					textScaler: MediaQuery.textScalerOf(context),
				),
		);
	}
}
