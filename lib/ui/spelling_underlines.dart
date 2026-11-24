// Draws a straight red line under the misspelled words of the note's text field.
// Text can be underlined by Flutter itself, but not lower down than right under the letters, so the lines
// are painted on top of the field instead, at the places the laid out words ended up.

import 'dart:math';

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import 'checklist_controller.dart';
import 'terminal_theme.dart';

const misspelledColorName = 'red';
// Both as parts of the text line's height
const underlineBottomGap = 0.1;
const underlineThickness = 0.07;

class SpellingUnderlines extends StatelessWidget {
	const SpellingUnderlines({
		super.key,
		required this.controller,
		required this.scrollController,
		required this.findEditable,
		required this.child,
	});

	final ChecklistController controller;
	final ScrollController scrollController;
	final RenderEditable? Function() findEditable;
	final Widget child;

	@override
	Widget build(BuildContext context) {
		return Builder(
			builder: (paintContext) => CustomPaint(
				foregroundPainter: _UnderlinePainter(
					controller: controller,
					findEditable: findEditable,
					findCanvasBox: () => paintContext.findRenderObject(),
					columnWidth: tabWidthFor(context, Theme.of(context).textTheme.bodyMedium) / tabSize,
					color: titleColorFor(misspelledColorName),
					repaint: Listenable.merge([controller, controller.focusNode, controller.spellChecker, scrollController]),
				),
				child: child,
			),
		);
	}
}

class _UnderlinePainter extends CustomPainter {
	_UnderlinePainter({
		required this.controller,
		required this.findEditable,
		required this.findCanvasBox,
		required this.columnWidth,
		required this.color,
		required Listenable repaint,
	}) : super(repaint: repaint);

	final ChecklistController controller;
	final RenderEditable? Function() findEditable;
	final RenderObject? Function() findCanvasBox;
	final double columnWidth;
	final Color color;

	@override
	void paint(Canvas canvas, Size size) {
		final words = controller.misspelledWords;
		final editable = findEditable();
		final canvasBox = findCanvasBox();
		if (words.isEmpty || editable == null || canvasBox == null) return;

		canvas.save();
		canvas.clipRect(Offset.zero & size);
		canvas.transform(editable.getTransformTo(canvasBox).storage);
		final paint = Paint()..color = color;
		for (final word in words) {
			for (final box in _wordBoxes(editable, word)) {
				final height = box.bottom - box.top;
				final bottom = box.bottom - height * underlineBottomGap;
				canvas.drawRect(Rect.fromLTRB(box.left, bottom - max(1, height * underlineThickness), box.right, bottom), paint);
			}
		}
		canvas.restore();
	}

	// A word at the start of a wrapped line has its first letter drawn as a widget, with the hanging indent
	// in it and its own height. Its line is made one column wide, level with the rest of the word.
	List<Rect> _wordBoxes(RenderEditable editable, TextRange word) {
		List<Rect> boxesOf(int start, int end) => [
			for (final box in editable.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end))) box.toRect(),
		];
		final first = boxesOf(word.start, word.start + 1);
		final rest = boxesOf(word.start + 1, word.end);
		if (first.isEmpty || rest.isEmpty) return [...first, ...rest];
		final firstLetter = first.single;
		final isOnSameLine = firstLetter.overlaps(rest.first.inflate(1));
		if (!isOnSameLine) return [firstLetter, ...rest];
		final left = max(firstLetter.left, firstLetter.right - columnWidth);
		return [Rect.fromLTRB(left, rest.first.top, rest.first.right, rest.first.bottom), ...rest.skip(1)];
	}

	// Rebuilt whenever the field is, and then the words may have moved
	@override
	bool shouldRepaint(_UnderlinePainter oldPainter) => true;

	@override
	bool? hitTest(Offset position) => false;
}
