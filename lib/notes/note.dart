import 'dart:io';

const untitledName = 'Untitled';
const lineBreak = '\n';
const tabIndent = '\t';
const spaceIndent = '    ';

enum LineType { text, unchecked, checked, bullet }

class NoteLine {
	const NoteLine(this.type, this.indent, this.text);

	final LineType type;
	final int indent;
	final String text;

	bool get isListItem => type != LineType.text;
	bool get isCheckbox => type == LineType.unchecked || type == LineType.checked;
	bool get isChecked => type == LineType.checked;

	NoteLine toggled() => switch (type) {
		LineType.unchecked => withType(LineType.checked),
		LineType.checked => withType(LineType.unchecked),
		_ => this,
	};

	NoteLine withIndent(int newIndent) => NoteLine(type, newIndent, text);

	NoteLine withType(LineType newType) => NoteLine(newType, indent, text);
}

class LineSyntax {
	const LineSyntax({required this.indentUnits, required this.prefixes, this.aliases = const {}});

	final List<String> indentUnits;
	final Map<LineType, String> prefixes;
	final Map<String, LineType> aliases;

	String get writtenIndent => indentUnits.first;

	String prefixFor(LineType type) => prefixes[type] ?? '';

	NoteLine parse(String rawLine) {
		var rest = rawLine;
		var indent = 0;
		for (var unit = _leadingIndentUnit(rest); unit != null; unit = _leadingIndentUnit(rest)) {
			rest = rest.substring(unit.length);
			indent++;
		}
		for (final (prefix, type) in _prefixesLongestFirst()) {
			if (rest.startsWith(prefix)) return NoteLine(type, indent, rest.substring(prefix.length));
		}
		return NoteLine(LineType.text, 0, rawLine);
	}

	List<(String, LineType)> _prefixesLongestFirst() {
		final all = [
			for (final entry in prefixes.entries) (entry.value, entry.key),
			for (final entry in aliases.entries) (entry.key, entry.value),
		];
		return all..sort((first, second) => second.$1.length.compareTo(first.$1.length));
	}

	String format(NoteLine line) {
		if (!line.isListItem) return line.text;
		return '${writtenIndent * line.indent}${prefixFor(line.type)}${line.text}';
	}

	int indentLength(NoteLine line) => writtenIndent.length * line.indent;

	int prefixLength(NoteLine line) {
		if (!line.isListItem) return 0;
		return indentLength(line) + prefixFor(line.type).length;
	}

	String? _leadingIndentUnit(String text) {
		for (final unit in indentUnits) {
			if (text.startsWith(unit)) return unit;
		}
		return null;
	}
}

const bulletPrefix = '- ';
const uncheckedPrefix = '$bulletPrefix[ ] ';
const checkedPrefix = '$bulletPrefix[x] ';

// Older and shorthand forms, still read and rewritten in the forms above
const checkboxAliases = {
	'[ ] ': LineType.unchecked,
	'[] ': LineType.unchecked,
	'$bulletPrefix[] ': LineType.unchecked,
	'[x] ': LineType.checked,
	'[X] ': LineType.checked,
	'$bulletPrefix[X] ': LineType.checked,
};

const noteSyntax = LineSyntax(
	indentUnits: [tabIndent, spaceIndent],
	prefixes: {
		LineType.unchecked: uncheckedPrefix,
		LineType.checked: checkedPrefix,
		LineType.bullet: bulletPrefix,
	},
	aliases: checkboxAliases,
);

String normalizeLineBreaks(String content) => content.replaceAll('\r\n', lineBreak);

List<String> splitLines(String content) => normalizeLineBreaks(content).split(lineBreak);

({String title, String body}) splitTitle(String content) {
	final normalized = normalizeLineBreaks(content);
	final titleEnd = normalized.indexOf(lineBreak);
	if (titleEnd == -1) return (title: normalized, body: '');
	return (title: normalized.substring(0, titleEnd), body: normalized.substring(titleEnd + 1));
}

String joinTitle(String title, String body) => body.isEmpty ? title : '$title$lineBreak$body';

// Title color, written at the end of the title line: "fix songs @green".
// "#green" is still read, since older notes used # before it was taken by tags.
const titleColorNames = ['green', 'yellow', 'orange', 'red', 'pink', 'purple', 'blue', 'cyan'];
const colorTagMark = '@';
final colorTagPattern = RegExp(r'\s+[@#](\w+)$');

// Tags, written as the last line of the note: "#work #music"
const tagMark = '#';
final tagLinePattern = RegExp(r'^\s*#\S+(\s+#\S+)*\s*$');
final tagSeparator = RegExp(r'[\s,]+');
final leadingTagMarks = RegExp(r'^#+');

({String body, List<String> tags}) splitTags(String body) {
	final lastBreak = body.lastIndexOf(lineBreak);
	final lastLine = body.substring(lastBreak + 1);
	if (!tagLinePattern.hasMatch(lastLine)) return (body: body, tags: const []);
	final bodyWithoutTags = lastBreak == -1 ? '' : body.substring(0, lastBreak);
	return (body: bodyWithoutTags, tags: parseTagInput(lastLine));
}

// A color typed after a tag, "#work@yellow", sets that tag's color. It is never saved in the note.
final tagColorPattern = RegExp('^(.+)$colorTagMark(\\w+)\$');

({String tag, String? color}) splitTagColor(String tagWithColor) {
	final match = tagColorPattern.firstMatch(tagWithColor);
	final color = match?.group(2);
	if (match == null || !titleColorNames.contains(color)) return (tag: tagWithColor, color: null);
	return (tag: match.group(1)!, color: color);
}

List<({String tag, String? color})> _typedTags(String input) {
	return [
		for (final word in input.split(tagSeparator))
			if (word.replaceFirst(leadingTagMarks, '').isNotEmpty) splitTagColor(word.replaceFirst(leadingTagMarks, '')),
	];
}

List<String> parseTagInput(String input) => [for (final typed in _typedTags(input)) typed.tag];

Map<String, String> typedTagColors(String input) {
	return {
		for (final typed in _typedTags(input))
			if (typed.color != null) typed.tag: typed.color!,
	};
}

String formatTags(List<String> tags) => tags.map((tag) => '$tagMark$tag').join(' ');

String joinTags(String body, List<String> tags) {
	if (tags.isEmpty) return body;
	return body.isEmpty ? formatTags(tags) : '$body$lineBreak${formatTags(tags)}';
}

// Bold and italic text, as in Markdown: "**buy milk**", "*buy milk*".
// The title is always bold, so it is saved that way too. Older titles used single stars.
const boldMark = '**';
const italicMark = '*';
final emphasisPattern = RegExp(r'(\*\*?)(?=[^*\s])[^*\n]*?[^*\s]\1');
final boldTitlePattern = RegExp(r'^\s*(\*\*?)(.+)\1\s*$');

String _withoutBoldMarks(String text) => boldTitlePattern.firstMatch(text)?.group(2) ?? text;

({String text, String? color}) parseTitle(String titleLine) {
	final match = colorTagPattern.firstMatch(titleLine);
	final color = match?.group(1);
	if (match == null || !titleColorNames.contains(color)) return (text: _withoutBoldMarks(titleLine), color: null);
	return (text: _withoutBoldMarks(titleLine.substring(0, match.start)), color: color);
}

String formatTitle(String text, String? color) {
	final trimmed = text.trim();
	final boldText = trimmed.isEmpty ? '' : '$boldMark$trimmed$boldMark';
	return color == null ? boldText : '$boldText $colorTagMark$color';
}

String titleOf(String content) {
	final title = parseTitle(splitTitle(content).title).text.trim();
	return title.isEmpty ? untitledName : title;
}

class Note {
	const Note({required this.file, required this.content, required this.modified});

	final File file;
	final String content;
	final DateTime modified;

	String get title => titleOf(content);
	String? get titleColor => parseTitle(splitTitle(content).title).color;
	String get body => splitTags(splitTitle(content).body).body;
	List<String> get tags => splitTags(splitTitle(content).body).tags;
}
