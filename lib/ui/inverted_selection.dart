// Draws selected text the terminal way, with text and background swapped, like focused titles and buttons.
// Flutter paints the selection's background itself (selectionColor, in the text's color), so only the
// selected text's color is changed here.

import 'package:material_ui/material_ui.dart';

import 'terminal_theme.dart';

mixin InvertedSelection on TextEditingController {
	// Flutter hides the selection's background in a field without focus, so the text isn't inverted then either
	FocusNode? focusNode;

	TextSpan withInvertedSelection(TextSpan span) {
		final isShown = focusNode?.hasFocus ?? false;
		if (!isShown || !selection.isValid || selection.isCollapsed) return span;
		return _SelectionInverter(selection).invert(span) as TextSpan;
	}
}

class InvertedSelectionController extends TextEditingController with InvertedSelection {
	InvertedSelectionController({super.text});

	@override
	TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
		return withInvertedSelection(super.buildTextSpan(context: context, style: style, withComposing: withComposing));
	}
}

// Walks the spans in order, counting characters, and recolors the parts inside the selection.
class _SelectionInverter {
	_SelectionInverter(this.selection);

	final TextSelection selection;
	int position = 0;

	InlineSpan invert(InlineSpan span) {
		if (span is WidgetSpan) return _invertWidget(span);
		if (span is! TextSpan) return span;
		return TextSpan(
			style: span.style,
			children: [
				if (span.text case final text?) ..._invertText(text, span.style),
				for (final child in span.children ?? const <InlineSpan>[]) invert(child),
			],
		);
	}

	List<InlineSpan> _invertText(String text, TextStyle? style) {
		final start = (selection.start - position).clamp(0, text.length);
		final end = (selection.end - position).clamp(0, text.length);
		position += text.length;
		// Characters drawn with no width stay invisible
		final isHidden = style?.color?.a == 0;
		if (start == end || isHidden) return [TextSpan(text: text)];
		return [
			if (start > 0) TextSpan(text: text.substring(0, start)),
			TextSpan(text: text.substring(start, end), style: TextStyle(color: terminalBackground)),
			if (end < text.length) TextSpan(text: text.substring(end)),
		];
	}

	// A widget counts as one character
	WidgetSpan _invertWidget(WidgetSpan span) {
		final isSelected = position >= selection.start && position < selection.end;
		position++;
		if (!isSelected) return span;
		return WidgetSpan(
			alignment: span.alignment,
			baseline: span.baseline,
			style: span.style,
			child: ColorFiltered(colorFilter: ColorFilter.mode(terminalBackground, BlendMode.srcIn), child: span.child),
		);
	}
}
