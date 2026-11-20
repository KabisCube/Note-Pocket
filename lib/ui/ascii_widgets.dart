import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'terminal_theme.dart';

// Cursor
const blockCursor = '█';
const cursorBlinkInterval = Duration(milliseconds: 530);

// Typewriter
const typingInterval = Duration(milliseconds: 45);

// Spinner
const spinnerFrames = ['|', '/', '-', '\\'];
const spinnerInterval = Duration(milliseconds: 120);

// New note button
const newNoteButtonLabel = '+ new note';
const newNoteButtonPadding = EdgeInsets.symmetric(horizontal: 10, vertical: 6);

// Shared
const backLabel = '[<]';
const resultDisplayTime = Duration(milliseconds: 800);

// Checkbox
// The mark inside the box, from unchecked to checked; the in-between ones are the toggle animation
const checkboxMarks = [' ', '.', 'o', 'x'];
const uncheckedMark = ' ';
const checkedMark = 'x';
// Each nesting level gets its own box and bullet shape, repeating after the last one
const checkboxBrackets = [('[', ']'), ('{', '}'), ('<', '>')];
const bulletMarks = ['•', '◦', '▪'];

String checkboxText(int indent, String mark) {
	final brackets = checkboxBrackets[indent % checkboxBrackets.length];
	return '${brackets.$1}$mark${brackets.$2}';
}

String bulletMarkFor(int indent) => bulletMarks[indent % bulletMarks.length];
const checkboxFrameInterval = Duration(milliseconds: 60);

// Frame
const frameLabelRowHeight = 26.0;
const frameCornerInset = 10.0;
const frameLabelPadding = EdgeInsets.symmetric(horizontal: 4);
const frameSidePadding = 12.0;
const frameContentPadding = EdgeInsets.fromLTRB(frameSidePadding, 2, frameSidePadding, 12);
const frameContentPaddingAboveLabel = EdgeInsets.fromLTRB(frameSidePadding, 2, frameSidePadding, 0);
const screenTitleStyle = TextStyle(fontWeight: FontWeight.bold);

class BlinkingCursor extends StatefulWidget {
	const BlinkingCursor({super.key, this.style});

	final TextStyle? style;

	@override
	State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor> {
	bool isVisible = true;
	late final Timer timer;

	@override
	void initState() {
		super.initState();
		timer = Timer.periodic(cursorBlinkInterval, (_) => setState(() => isVisible = !isVisible));
	}

	@override
	void dispose() {
		timer.cancel();
		super.dispose();
	}

	@override
	Widget build(BuildContext context) {
		final color = isVisible ? terminalAccent : Colors.transparent;
		return Text(blockCursor, style: (widget.style ?? const TextStyle()).copyWith(color: color));
	}
}

class AsciiSpinner extends StatefulWidget {
	const AsciiSpinner({super.key});

	@override
	State<AsciiSpinner> createState() => _AsciiSpinnerState();
}

class _AsciiSpinnerState extends State<AsciiSpinner> {
	int frameIndex = 0;
	late final Timer timer;

	@override
	void initState() {
		super.initState();
		timer = Timer.periodic(spinnerInterval, (_) {
			setState(() => frameIndex = (frameIndex + 1) % spinnerFrames.length);
		});
	}

	@override
	void dispose() {
		timer.cancel();
		super.dispose();
	}

	@override
	Widget build(BuildContext context) {
		return Text(spinnerFrames[frameIndex], style: TextStyle(color: terminalAccent));
	}
}

class TypewriterText extends StatefulWidget {
	const TypewriterText(this.text, {super.key, this.style, this.showCursor = true, this.onFinished});

	final String text;
	final TextStyle? style;
	final bool showCursor;
	final VoidCallback? onFinished;

	@override
	State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
	int visibleCharacters = 0;
	late final Timer timer;

	@override
	void initState() {
		super.initState();
		timer = Timer.periodic(typingInterval, (_) {
			if (visibleCharacters >= widget.text.length) {
				timer.cancel();
				widget.onFinished?.call();
				return;
			}
			setState(() => visibleCharacters++);
		});
	}

	@override
	void dispose() {
		timer.cancel();
		super.dispose();
	}

	@override
	Widget build(BuildContext context) {
		return Row(
			mainAxisSize: MainAxisSize.min,
			children: [
				Flexible(
					child: Text(
						widget.text.substring(0, visibleCharacters),
						style: widget.style,
						maxLines: 1,
						overflow: TextOverflow.ellipsis,
					),
				),
				if (widget.showCursor) BlinkingCursor(style: widget.style),
			],
		);
	}
}

// A bordered box with a label set into the top-left of the border and actions in the top-right.
// The border is drawn half a label row down, and the label and actions cover it with the
// background color, so the line appears to run into the middle of the text.
// bottomLabel and bottomActions are set into the bottom border the same way.
// accentColor tints the action buttons, and a dimmed version of it the border.
class AsciiFrame extends StatelessWidget {
	const AsciiFrame({
		super.key,
		required this.label,
		required this.child,
		this.actions = const [],
		this.bottomLabel,
		this.bottomActions = const [],
		this.fillsSpace = false,
		this.padsContentSides = true,
		this.accentColor,
	});

	final Widget label;
	final Widget child;
	final List<Widget> actions;
	final Widget? bottomLabel;
	final List<Widget> bottomActions;
	final bool fillsSpace;
	// Off when the content pads itself, like a text field that should be clickable right up to the border
	final bool padsContentSides;
	final Color? accentColor;

	@override
	Widget build(BuildContext context) {
		final hasBottomLabel = bottomLabel != null || bottomActions.isNotEmpty;
		final content = Padding(
			padding: (hasBottomLabel ? frameContentPaddingAboveLabel : frameContentPadding)
				.copyWith(left: padsContentSides ? null : 0, right: padsContentSides ? null : 0),
			child: child,
		);
		final borderColor = accentColor == null ? terminalDimText : dulled(accentColor!);

		return Stack(
			children: [
				Positioned.fill(
					top: frameLabelRowHeight / 2,
					bottom: hasBottomLabel ? frameLabelRowHeight / 2 : 0,
					child: DecoratedBox(
						decoration: BoxDecoration(border: Border.all(color: borderColor)),
					),
				),
				Column(
					mainAxisSize: fillsSpace ? MainAxisSize.max : MainAxisSize.min,
					crossAxisAlignment: CrossAxisAlignment.stretch,
					children: [
						SizedBox(
							height: frameLabelRowHeight,
							child: Row(
								children: [
									const SizedBox(width: frameCornerInset),
									Expanded(
										child: Align(alignment: Alignment.centerLeft, child: _coverBorder(label)),
									),
									if (actions.isNotEmpty) _coverBorder(_tintedActions(context, actions)),
									const SizedBox(width: frameCornerInset),
								],
							),
						),
						fillsSpace ? Expanded(child: content) : content,
						if (hasBottomLabel)
							SizedBox(
								height: frameLabelRowHeight,
								child: Row(
									children: [
										const SizedBox(width: frameCornerInset),
										Expanded(
											child: Align(
												alignment: Alignment.centerLeft,
												child: bottomLabel == null ? null : _coverBorder(bottomLabel!),
											),
										),
										if (bottomActions.isNotEmpty) _coverBorder(_tintedActions(context, bottomActions)),
										const SizedBox(width: frameCornerInset),
									],
								),
							),
					],
				),
			],
		);
	}

	Widget _tintedActions(BuildContext context, List<Widget> buttons) {
		final actionRow = Row(mainAxisSize: MainAxisSize.min, children: buttons);
		if (accentColor == null) return actionRow;
		final baseStyle = Theme.of(context).textButtonTheme.style ?? const ButtonStyle();
		return TextButtonTheme(
			data: TextButtonThemeData(
				style: invertedFocusButtonStyle(accentColor!).merge(baseStyle),
			),
			child: actionRow,
		);
	}

	Widget _coverBorder(Widget child) {
		return ColoredBox(
			color: terminalBackground,
			child: Padding(padding: frameLabelPadding, child: child),
		);
	}
}

// Shows keyboard focus the terminal way, with text and background swapped, for labels inside a
// focusable widget like a menu button or a note. It follows the nearest focusable widget above it.
class InvertedWhenFocused extends StatelessWidget {
	const InvertedWhenFocused({super.key, required this.color, required this.builder});

	final Color color;
	final Widget Function(Color textColor) builder;

	@override
	Widget build(BuildContext context) {
		final hasFocus = Focus.maybeOf(context)?.hasPrimaryFocus ?? false;
		final isUsingKeyboard = FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
		final isInverted = hasFocus && isUsingKeyboard;
		return ColoredBox(
			color: isInverted ? color : Colors.transparent,
			child: builder(isInverted ? terminalBackground : color),
		);
	}
}

Widget invertedWhenFocusedText(String text, Color color, {TextStyle? style}) {
	return InvertedWhenFocused(
		color: color,
		builder: (textColor) => Text(text, style: (style ?? const TextStyle()).copyWith(color: textColor)),
	);
}

// The new note button: a full-width box in the accent color.
// Hovering, pressing or keyboard focus inverts its label, like every other button.
class NewNoteButton extends StatefulWidget {
	const NewNoteButton({super.key, required this.onPressed, this.focusNode});

	final VoidCallback onPressed;
	final FocusNode? focusNode;

	@override
	State<NewNoteButton> createState() => _NewNoteButtonState();
}

class _NewNoteButtonState extends State<NewNoteButton> {
	bool isHovered = false;
	bool isFocused = false;
	bool isPressed = false;

	@override
	Widget build(BuildContext context) {
		final isHighlighted = isHovered || isFocused || isPressed;
		final textColor = isHighlighted ? terminalBackground : terminalAccent;
		final textStyle = TextStyle(color: textColor, fontWeight: FontWeight.bold);

		return FocusableActionDetector(
			focusNode: widget.focusNode,
			mouseCursor: SystemMouseCursors.click,
			onShowHoverHighlight: (value) => setState(() => isHovered = value),
			onShowFocusHighlight: (value) => setState(() => isFocused = value),
			actions: {
				ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
					widget.onPressed();
					return null;
				}),
			},
			child: GestureDetector(
				onTapDown: (_) => setState(() => isPressed = true),
				onTapCancel: () => setState(() => isPressed = false),
				onTapUp: (_) => setState(() => isPressed = false),
				onTap: widget.onPressed,
				child: Container(
					padding: newNoteButtonPadding,
					alignment: Alignment.centerLeft,
					decoration: BoxDecoration(border: Border.all(color: dulled(terminalAccent))),
					child: ColoredBox(
						color: isHighlighted ? terminalAccent : Colors.transparent,
						child: Text(newNoteButtonLabel, style: textStyle),
					),
				),
			),
		);
	}
}
