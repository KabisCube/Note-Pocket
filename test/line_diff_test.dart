import 'package:flutter_test/flutter_test.dart';
import 'package:note_pocket/notes/line_diff.dart';

List<int> changeIndexesOf(List<DiffChunk> chunks) {
	return [
		for (var index = 0; index < chunks.length; index++)
			if (chunks[index].isChange) index,
	];
}

void main() {
	test('same notes have no differences', () {
		expect(changeIndexesOf(diffLines(['a', 'b'], ['a', 'b'])), isEmpty);
	});

	test('changed, added and removed lines become separate differences', () {
		final local = ['Groceries', '[ ] milk', '[ ] bread', '[ ] oat'];
		final incoming = ['Groceries', '[x] milk', '[ ] bread', '[ ] eggs', '[ ] oat'];
		final chunks = diffLines(local, incoming);
		final changes = changeIndexesOf(chunks).map((index) => chunks[index]).toList();
		expect(changes, hasLength(2));
		expect(changes[0].localLines, ['[ ] milk']);
		expect(changes[0].incomingLines, ['[x] milk']);
		expect(changes[1].localLines, isEmpty);
		expect(changes[1].incomingLines, ['[ ] eggs']);
	});

	test('differing lines are paired line by line', () {
		final chunks = diffLines(['note', "other text that's different"], ['note', 'other text', '', 'I wrote this too']);
		final changes = changeIndexesOf(chunks).map((index) => chunks[index]).toList();
		expect(changes, hasLength(2));
		expect(changes[0].localLines, ["other text that's different"]);
		expect(changes[0].incomingLines, ['other text']);
		expect(changes[1].localLines, isEmpty);
		expect(changes[1].incomingLines, ['I wrote this too']);
	});

	test('merging uses the picked side of each difference', () {
		final chunks = diffLines(['note', "other text that's different"], ['note', 'other text', '', 'I wrote this too']);
		final changeIndexes = changeIndexesOf(chunks);
		final firstPick = ChunkPick(chunks[changeIndexes[0]])..pickWholeSide(DiffSide.local);
		final secondPick = ChunkPick(chunks[changeIndexes[1]])..pickWholeSide(DiffSide.incoming);

		final merged = mergeChunks(chunks, {changeIndexes[0]: firstPick, changeIndexes[1]: secondPick});
		expect(merged, "note\nother text that's different\n\nI wrote this too");
	});

	test('picking nothing on an empty side keeps no lines', () {
		final chunks = diffLines(['a'], ['a', 'extra']);
		final changeIndex = changeIndexesOf(chunks).single;
		final pick = ChunkPick(chunks[changeIndex])..pickWholeSide(DiffSide.local);
		expect(pick.isDecided, isTrue);
		expect(pick.keepsNothing, isTrue);
		expect(mergeChunks(chunks, {changeIndex: pick}), 'a');
	});

	test('both lines of a pair can be kept', () {
		final chunks = diffLines(['note', 'mine'], ['note', 'theirs']);
		final changeIndex = changeIndexesOf(chunks).single;
		final pick = ChunkPick(chunks[changeIndex])
			..toggleLine(DiffSide.local, 0)
			..toggleLine(DiffSide.incoming, 0);
		expect(mergeChunks(chunks, {changeIndex: pick}), 'note\nmine\ntheirs');
	});

	test('only one of two different titles can be kept', () {
		final chunks = diffLines(['title @pink', 'same'], ['title @cyan', 'same']);
		final pick = pickFor(chunks, 0)
			..toggleLine(DiffSide.local, titleLineIndex)
			..toggleLine(DiffSide.incoming, titleLineIndex);
		expect(pick.localLines, isEmpty);
		expect(mergeChunks(chunks, {0: pick}), 'title @cyan\nsame');
	});

	test('blank-line-only changes are kept without any pick', () {
		final chunks = diffLines(['a', 'b'], ['a', '', 'b']);
		expect(changeIndexesOf(chunks), isEmpty);
		expect(mergeChunks(chunks, {}), 'a\n\nb');
	});
}
