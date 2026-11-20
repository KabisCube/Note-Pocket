import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../notes/note.dart';
import '../notes/tag_completion.dart';
import 'ascii_widgets.dart';
import 'terminal_theme.dart';

// The marker shown when more than one tag continues after the completed part
const moreTagsFrames = ['*..', '.*.', '..*', '.*.'];
const moreTagsFrameInterval = Duration(milliseconds: 180);

final tagWordPattern = RegExp(r'#?[^\s,]+');
const noTagColorName = 'none';
const tagColorSwatch = '\u25a0';

// Color menus: left-aligned and only as wide as the longest color name
const colorMenuConstraints = BoxConstraints();

Widget colorMenuLabel(String colorName) {
	return invertedWhenFocusedText('$tagColorSwatch $colorName', titleColorFor(colorName));
}

List<PopupMenuEntry<String>> colorMenuItems() {
	return [
		for (final name in [noTagColorName, ...titleColorNames])
			PopupMenuItem(
				value: name,
				height: menuItemHeight,
				padding: menuItemPadding,
				child: colorMenuLabel(name),
			),
	];
}

// The color picked for a tag: a color name, noTagColorName to clear it, or null if the menu was closed.
Future<String?> showTagColorMenu(BuildContext context, Offset globalPosition) {
	final overlayBox = Overlay.of(context).context.findRenderObject() as RenderBox;
	final position = overlayBox.globalToLocal(globalPosition);
	return showMenu<String>(
		context: context,
		position: RelativeRect.fromRect(position & Size.zero, Offset.zero & overlayBox.size),
		constraints: colorMenuConstraints,
		items: colorMenuItems(),
	);
}

// The same color menu, shown as a text field's right-click menu at the given anchor.
class ColorContextMenu extends StatelessWidget {
	const ColorContextMenu({super.key, required this.anchor, required this.onPicked});

	final Offset anchor;
	final ValueChanged<String> onPicked;

	@override
	Widget build(BuildContext context) {
		return CustomSingleChildLayout(
			delegate: DesktopTextSelectionToolbarLayoutDelegate(anchor: anchor),
			child: Container(
				decoration: BoxDecoration(color: terminalBackground, border: Border.fromBorderSide(squareShape.side)),
				child: IntrinsicWidth(
					child: Column(
						mainAxisSize: MainAxisSize.min,
						crossAxisAlignment: CrossAxisAlignment.stretch,
						children: [
							for (final name in [noTagColorName, ...titleColorNames])
								InkWell(
									onTap: () => onPicked(name),
									child: Container(
										height: menuItemHeight,
										padding: menuItemPadding,
										alignment: Alignment.centerLeft,
										child: colorMenuLabel(name),
									),
								),
						],
					),
				),
			),
		);
	}
}

// The tag the cursor is in, without its "#", or null when the cursor isn't in a tag.
String? tagAtCursor(TextEditingValue value) {
	final cursor = value.selection.baseOffset;
	if (cursor < 0) return null;
	for (final match in tagWordPattern.allMatches(value.text)) {
		if (cursor >= match.start && cursor <= match.end) {
			final tag = match[0]!.replaceFirst(leadingTagMarks, '');
			return tag.isEmpty ? null : tag;
		}
	}
	return null;
}

Color tagColorFor(String tag, Map<String, String> tagColors, Color fallbackColor) {
	return titleColors[tagColors[tag]] ?? fallbackColor;
}

// "#work #music", each tag in its own color.
TextSpan tagsSpan(List<String> tags, Map<String, String> tagColors, Color fallbackColor) {
	return TextSpan(
		children: [
			for (var index = 0; index < tags.length; index++) ...[
				if (index > 0) const TextSpan(text: ' '),
				TextSpan(
					text: '$tagMark${tags[index]}',
					style: TextStyle(color: tagColorFor(tags[index], tagColors, fallbackColor)),
				),
			],
		],
	);
}

// A note's tags as separate words, so each can be right-clicked to pick its color.
class TagsRow extends StatelessWidget {
	const TagsRow({
		super.key,
		required this.tags,
		required this.tagColors,
		required this.fallbackColor,
		required this.onPickColor,
	});

	final List<String> tags;
	final Map<String, String> tagColors;
	final Color fallbackColor;
	final void Function(String tag, Offset globalPosition) onPickColor;

	@override
	Widget build(BuildContext context) {
		return SingleChildScrollView(
			scrollDirection: Axis.horizontal,
			physics: const NeverScrollableScrollPhysics(),
			child: Row(
				children: [
					for (var index = 0; index < tags.length; index++) ...[
						if (index > 0) const Text(' '),
						GestureDetector(
							onSecondaryTapDown: (details) => onPickColor(tags[index], details.globalPosition),
							child: Text(
								'$tagMark${tags[index]}',
								style: TextStyle(color: tagColorFor(tags[index], tagColors, fallbackColor)),
							),
						),
					],
				],
			),
		);
	}
}

// The tags field in the editor, coloring each typed tag like it is shown everywhere else.
class TagsController extends TextEditingController {
	TagsController({super.text});

	Map<String, String> tagColors = const {};
	Color fallbackColor = terminalDimText;

	@override
	TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
		final children = <TextSpan>[];
		var position = 0;
		for (final match in tagWordPattern.allMatches(text)) {
			if (match.start > position) children.add(TextSpan(text: text.substring(position, match.start)));
			final tag = match[0]!.replaceFirst(leadingTagMarks, '');
			children.add(TextSpan(
				text: match[0],
				style: TextStyle(color: tagColorFor(tag, tagColors, fallbackColor)),
			));
			position = match.end;
		}
		if (position < text.length) children.add(TextSpan(text: text.substring(position)));
		return TextSpan(style: style, children: children);
	}
}

// The darker completion text shown right after the cursor in the tags field.
// With one matching tag it shows the rest of that tag. With several, it shows the part they share,
// followed by a small animation that tells more than one tag continues from there.
class CompletionGhost extends StatefulWidget {
	const CompletionGhost({super.key, required this.completion});

	final TagCompletion completion;

	@override
	State<CompletionGhost> createState() => _CompletionGhostState();
}

class _CompletionGhostState extends State<CompletionGhost> {
	int frameIndex = 0;
	late final Timer timer;

	@override
	void initState() {
		super.initState();
		timer = Timer.periodic(moreTagsFrameInterval, (_) {
			if (!widget.completion.hasOneMatch) setState(() => frameIndex = (frameIndex + 1) % moreTagsFrames.length);
		});
	}

	@override
	void dispose() {
		timer.cancel();
		super.dispose();
	}

	@override
	Widget build(BuildContext context) {
		final completion = widget.completion;
		final shownEnd = completion.hasOneMatch ? completion.endings.single : moreTagsFrames[frameIndex];
		return Text.rich(
			TextSpan(children: [
				TextSpan(text: completion.sharedPart, style: TextStyle(color: terminalDimText)),
				TextSpan(text: shownEnd, style: TextStyle(color: dulled(terminalDimText))),
			]),
			softWrap: false,
		);
	}
}
