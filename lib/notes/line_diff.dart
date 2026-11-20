// Line-by-line comparison of the local copy of a note and a received copy.
// Uses the longest common subsequence of lines: lines in it are "same". The lines in between
// are paired line by line into change chunks, each holding one line from this device and
// one received line (either can be missing).

import 'note.dart';

enum DiffSide { local, incoming }

const titleLineIndex = 0;

ChunkPick pickFor(List<DiffChunk> chunks, int chunkIndex) {
	final chunk = chunks[chunkIndex];
	final startsAtTitle = chunkIndex == 0 && chunk.localLines.isNotEmpty && chunk.incomingLines.isNotEmpty;
	return ChunkPick(chunk, hasTitleLines: startsAtTitle);
}

class DiffChunk {
	const DiffChunk.same(List<String> lines) : localLines = lines, incomingLines = lines, isChange = false;

	const DiffChunk.change(this.localLines, this.incomingLines) : isChange = true;

	final List<String> localLines;
	final List<String> incomingLines;
	final bool isChange;

	List<String> linesFor(DiffSide side) => side == DiffSide.local ? localLines : incomingLines;
}

List<DiffChunk> diffLines(List<String> local, List<String> incoming) {
	final commonAfter = List.generate(local.length + 1, (_) => List.filled(incoming.length + 1, 0));
	for (var localIndex = local.length - 1; localIndex >= 0; localIndex--) {
		for (var incomingIndex = incoming.length - 1; incomingIndex >= 0; incomingIndex--) {
			commonAfter[localIndex][incomingIndex] = local[localIndex] == incoming[incomingIndex]
				? commonAfter[localIndex + 1][incomingIndex + 1] + 1
				: _longer(commonAfter[localIndex + 1][incomingIndex], commonAfter[localIndex][incomingIndex + 1]);
		}
	}

	final chunks = <DiffChunk>[];
	var sameLines = <String>[];
	var localOnly = <String>[];
	var incomingOnly = <String>[];

	void closeChange() {
		if (localOnly.isEmpty && incomingOnly.isEmpty) return;
		chunks.addAll(_pairLineByLine(localOnly, incomingOnly));
		localOnly = [];
		incomingOnly = [];
	}

	void closeSame() {
		if (sameLines.isEmpty) return;
		chunks.add(DiffChunk.same(sameLines));
		sameLines = [];
	}

	var localIndex = 0;
	var incomingIndex = 0;
	while (localIndex < local.length || incomingIndex < incoming.length) {
		final hasBoth = localIndex < local.length && incomingIndex < incoming.length;
		if (hasBoth && local[localIndex] == incoming[incomingIndex]) {
			closeChange();
			sameLines.add(local[localIndex]);
			localIndex++;
			incomingIndex++;
			continue;
		}
		closeSame();
		final isLocalOnly = incomingIndex >= incoming.length
			|| (localIndex < local.length
				&& commonAfter[localIndex + 1][incomingIndex] >= commonAfter[localIndex][incomingIndex + 1]);
		if (isLocalOnly) {
			localOnly.add(local[localIndex++]);
		} else {
			incomingOnly.add(incoming[incomingIndex++]);
		}
	}
	closeChange();
	closeSame();
	return chunks;
}

// Which lines of one difference are kept. Lines from this device come first, then received ones.
// Blank lines are always kept and can't be picked.
// When the difference includes the title line, only one of the two titles can be kept.
class ChunkPick {
	ChunkPick(this.chunk, {this.hasTitleLines = false});

	final DiffChunk chunk;
	final bool hasTitleLines;
	final localLines = <int>{};
	final incomingLines = <int>{};
	bool keepsNothing = false;

	bool get hasPickableLines => pickableLines(DiffSide.local).isNotEmpty || pickableLines(DiffSide.incoming).isNotEmpty;

	bool get isDecided => !hasPickableLines || keepsNothing || localLines.isNotEmpty || incomingLines.isNotEmpty;

	Set<int> linesFor(DiffSide side) => side == DiffSide.local ? localLines : incomingLines;

	bool isPickable(DiffSide side, int lineIndex) => !isBlankLine(chunk.linesFor(side)[lineIndex]);

	List<int> pickableLines(DiffSide side) {
		final lines = chunk.linesFor(side);
		return [
			for (var lineIndex = 0; lineIndex < lines.length; lineIndex++)
				if (!isBlankLine(lines[lineIndex])) lineIndex,
		];
	}

	bool isWholeSide(DiffSide side) {
		final pickable = pickableLines(side);
		if (pickable.isEmpty) return keepsNothing;
		return pickable.every(linesFor(side).contains);
	}

	void pickWholeSide(DiffSide side) {
		localLines.clear();
		incomingLines.clear();
		final pickable = pickableLines(side);
		keepsNothing = pickable.isEmpty;
		linesFor(side).addAll(pickable);
	}

	void toggleLine(DiffSide side, int lineIndex) {
		if (!isPickable(side, lineIndex)) return;
		keepsNothing = false;
		final pickedLines = linesFor(side);
		if (pickedLines.remove(lineIndex)) return;
		pickedLines.add(lineIndex);
		if (hasTitleLines && lineIndex == titleLineIndex) linesFor(_otherSide(side)).remove(titleLineIndex);
	}

	List<String> keptLines() => [..._keptLinesOf(DiffSide.local), ..._keptLinesOf(DiffSide.incoming)];

	List<String> _keptLinesOf(DiffSide side) {
		final lines = chunk.linesFor(side);
		return [
			for (var lineIndex = 0; lineIndex < lines.length; lineIndex++)
				if (isBlankLine(lines[lineIndex]) || linesFor(side).contains(lineIndex)) lines[lineIndex],
		];
	}

	DiffSide _otherSide(DiffSide side) => side == DiffSide.local ? DiffSide.incoming : DiffSide.local;
}

bool isBlankLine(String line) => line.trim().isEmpty;

String mergeChunks(List<DiffChunk> chunks, Map<int, ChunkPick> picks) {
	return [
		for (var index = 0; index < chunks.length; index++)
			...chunks[index].isChange ? picks[index]!.keptLines() : chunks[index].localLines,
	].join(lineBreak);
}

// Splits a run of differing lines into one difference per line: the first text line on each
// side are paired, then the second, and so on. Blank lines between them are always kept,
// so they become unchanged lines (the longer run of the two sides is used).
List<DiffChunk> _pairLineByLine(List<String> localLines, List<String> incomingLines) {
	final local = _splitAtBlankLines(localLines);
	final incoming = _splitAtBlankLines(incomingLines);
	final pairCount = _longer(local.textLines.length, incoming.textLines.length);

	final chunks = <DiffChunk>[];
	for (var index = 0; index <= pairCount; index++) {
		final localGap = index < local.blankRuns.length ? local.blankRuns[index] : const <String>[];
		final incomingGap = index < incoming.blankRuns.length ? incoming.blankRuns[index] : const <String>[];
		final gap = localGap.length >= incomingGap.length ? localGap : incomingGap;
		if (gap.isNotEmpty) chunks.add(DiffChunk.same(gap));
		if (index == pairCount) break;

		chunks.add(DiffChunk.change(
			index < local.textLines.length ? [local.textLines[index]] : const [],
			index < incoming.textLines.length ? [incoming.textLines[index]] : const [],
		));
	}
	return chunks;
}

// blankRuns has one entry before each text line and one after the last.
({List<String> textLines, List<List<String>> blankRuns}) _splitAtBlankLines(List<String> lines) {
	final textLines = <String>[];
	final blankRuns = <List<String>>[[]];
	for (final line in lines) {
		if (isBlankLine(line)) {
			blankRuns.last.add(line);
		} else {
			textLines.add(line);
			blankRuns.add([]);
		}
	}
	return (textLines: textLines, blankRuns: blankRuns);
}

int _longer(int first, int second) => first > second ? first : second;
