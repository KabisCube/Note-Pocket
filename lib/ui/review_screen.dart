// Shown when a note is received.
// A new note is shown whole. A note that already exists here is shown whole too, like a diff:
// each difference appears in place as lines tinted blue (this device) or orange (received),
// explained by a color legend at the top. Every line has its own pick mark; tapping a legend
// entry keeps that side in every difference. Picked lines turn green, the rest fade.
// Accept is only enabled once every difference has at least one pick
// ("(nothing)" counts as picking to keep no lines).

import 'package:material_ui/material_ui.dart';

import '../notes/checklist_editing.dart';
import '../notes/line_diff.dart';
import '../notes/note.dart';
import '../notes/note_storage.dart';
import '../transfer/lan_protocol.dart';
import 'ascii_widgets.dart';
import 'checklist_controller.dart';
import 'note_editor.dart';
import 'terminal_theme.dart';

const reviewTitle = 'REVIEW';
const acceptLabel = '[accept]';
const rejectLabel = '[reject]';
const localSideLabel = 'this device';
const emptySideText = '(nothing)';

// The whole note is drawn in a frame, with the pick checkboxes in a column outside its left edge.
// They use the { } shape, so they don't look like the note's own [ ] checkboxes.
const compareCheckboxLevel = 1;
final pickedMark = checkboxText(compareCheckboxLevel, checkedMark);
final unpickedMark = checkboxText(compareCheckboxLevel, uncheckedMark);
const lineGap = 8.0;
const markColumnWidth = 36.0;
const rowPadding = EdgeInsets.symmetric(vertical: 1);
const lineTextPadding = EdgeInsets.symmetric(horizontal: 6, vertical: 1);
const documentInset = 6.0;
const documentBottomPadding = 8.0;
const legendPadding = EdgeInsets.symmetric(horizontal: 6, vertical: 2);
const legendGap = 8.0;
const sideGap = 2.0;
const sideTintOpacity = 0.25;
const fadedOpacity = 0.4;

// Difference colors
Color get localSideColor => titleColors['blue']!;
Color get incomingSideColor => titleColors['orange']!;
Color get pickedSideColor => terminalAccent;

class ReviewScreen extends StatefulWidget {
	const ReviewScreen({super.key, required this.storage, required this.packet, this.localNote});

	final NoteStorage storage;
	final NotePacket packet;
	final Note? localNote;

	@override
	State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
	late final List<DiffChunk> chunks;
	late final Map<int, ChunkPick> picks;

	int get changeCount => picks.length;
	int get decidedCount => picks.values.where((pick) => pick.isDecided).length;
	bool get isComplete => decidedCount == changeCount;

	@override
	void initState() {
		super.initState();
		final incomingLines = splitLines(widget.packet.content);
		final localNote = widget.localNote;
		chunks = localNote == null
			? [DiffChunk.same(incomingLines)]
			: diffLines(splitLines(localNote.content), incomingLines);
		picks = {
			for (var index = 0; index < chunks.length; index++)
				if (chunks[index].isChange) index: pickFor(chunks, index),
		};
	}

	Future<void> _accept() async {
		final savedNote = await widget.storage.saveReceived(mergeChunks(chunks, picks));
		if (mounted) Navigator.pop(context, savedNote.file.path);
	}

	void _pickWholeSide(int chunkIndex, DiffSide side) {
		setState(() => picks[chunkIndex]!.pickWholeSide(side));
	}

	void _toggleLine(int chunkIndex, DiffSide side, int lineIndex) {
		setState(() => picks[chunkIndex]!.toggleLine(side, lineIndex));
	}

	@override
	Widget build(BuildContext context) {
		final packet = widget.packet;
		final tabWidth = tabWidthFor(context, DefaultTextStyle.of(context).style);

		return Scaffold(
			body: SafeArea(
				child: Padding(
					padding: const EdgeInsets.all(screenPadding),
					child: AsciiFrame(
						fillsSpace: true,
						label: const TypewriterText(reviewTitle, style: screenTitleStyle, showCursor: false),
						child: Column(
							crossAxisAlignment: CrossAxisAlignment.stretch,
							children: [
								Text('from ${packet.senderName}${_queueText()}: ${_summary()}', style: TextStyle(color: terminalDimText)),
								const SizedBox(height: lineGap),
								Expanded(
									child: ListView(children: [_buildDocument(tabWidth)]),
								),
								const SizedBox(height: lineGap),
								Row(
									mainAxisAlignment: MainAxisAlignment.end,
									children: [
										TextButton(onPressed: () => Navigator.pop(context), child: const Text(rejectLabel)),
										TextButton(onPressed: isComplete ? _accept : null, child: const Text(acceptLabel)),
									],
								),
							],
						),
					),
				),
			),
		);
	}

	String _queueText() {
		final packet = widget.packet;
		return packet.total > 1 ? ' (note ${packet.position}/${packet.total})' : '';
	}

	String _summary() {
		if (widget.localNote == null) return 'new note';
		if (changeCount == 0) return 'same as your copy';
		return 'pick lines to keep in each difference $decidedCount/$changeCount';
	}

	void _pickSideEverywhere(DiffSide side) {
		setState(() {
			for (final entry in picks.entries) {
				entry.value.pickWholeSide(side);
			}
		});
	}

	Widget _buildDocument(double tabWidth) {
		return Stack(
			children: [
				Positioned.fill(
					left: markColumnWidth,
					top: frameLabelRowHeight / 2,
					child: DecoratedBox(
						decoration: BoxDecoration(border: Border.fromBorderSide(BorderSide(color: terminalDimText))),
					),
				),
				Column(
					crossAxisAlignment: CrossAxisAlignment.stretch,
					children: [
						SizedBox(
							height: frameLabelRowHeight,
							child: Row(
								children: [
									const SizedBox(width: markColumnWidth + frameCornerInset),
									ColoredBox(
										color: terminalBackground,
										child: Padding(padding: frameLabelPadding, child: _buildDocumentLabel()),
									),
								],
							),
						),
						for (var index = 0; index < chunks.length; index++)
							if (chunks[index].isChange)
								..._buildChangeRows(index, tabWidth)
							else
								for (final line in chunks[index].localLines)
									_buildRow(content: _buildLines([line], tabWidth)),
						const SizedBox(height: documentBottomPadding),
					],
				),
			],
		);
	}

	Widget _buildDocumentLabel() {
		if (changeCount == 0) return Text(titleOf(widget.packet.content), style: titleStyle);
		return Row(
			mainAxisSize: MainAxisSize.min,
			children: [
				_buildLegendEntry(localSideLabel, localSideColor, DiffSide.local),
				const SizedBox(width: legendGap),
				_buildLegendEntry(widget.packet.senderName, incomingSideColor, DiffSide.incoming),
			],
		);
	}

	Widget _buildLegendEntry(String label, Color sideColor, DiffSide side) {
		return InkWell(
			onTap: () => _pickSideEverywhere(side),
			child: Container(
				padding: legendPadding,
				color: sideColor.withValues(alpha: sideTintOpacity),
				child: invertedWhenFocusedText(label, sideColor),
			),
		);
	}

	List<Widget> _buildChangeRows(int chunkIndex, double tabWidth) {
		final chunk = chunks[chunkIndex];
		return [
			const SizedBox(height: sideGap),
			..._buildSideRows(chunkIndex, DiffSide.local, chunk.localLines, tabWidth),
			const SizedBox(height: sideGap),
			..._buildSideRows(chunkIndex, DiffSide.incoming, chunk.incomingLines, tabWidth),
			const SizedBox(height: sideGap),
		];
	}

	List<Widget> _buildSideRows(int chunkIndex, DiffSide side, List<String> lines, double tabWidth) {
		final pick = picks[chunkIndex]!;
		final sideColor = side == DiffSide.local ? localSideColor : incomingSideColor;
		final pickedLines = pick.linesFor(side);
		final canKeepNothing = pick.hasPickableLines && pick.pickableLines(side).isEmpty;
		final isNothingPicked = pick.isWholeSide(side);

		return [
			if (canKeepNothing)
				_buildRow(
					pick: (isPicked: isNothingPicked, isFaded: pick.isDecided && !isNothingPicked, sideColor: sideColor),
					onTap: () => _pickWholeSide(chunkIndex, side),
					content: Text(emptySideText, style: TextStyle(color: terminalDimText)),
				),
			for (var lineIndex = 0; lineIndex < lines.length; lineIndex++)
				if (pick.isPickable(side, lineIndex))
					_buildRow(
						pick: (
							isPicked: pickedLines.contains(lineIndex),
							isFaded: pick.isDecided && !pickedLines.contains(lineIndex),
							sideColor: sideColor,
						),
						onTap: () => _toggleLine(chunkIndex, side, lineIndex),
						content: _buildLines([lines[lineIndex]], tabWidth),
					)
				else
					_buildRow(content: _buildLines([lines[lineIndex]], tabWidth)),
		];
	}

	// A line of the note inside the frame. Lines that can be picked also get a tint
	// and a checkbox in the column outside the frame.
	Widget _buildRow({
		required Widget content,
		({bool isPicked, bool isFaded, Color sideColor})? pick,
		VoidCallback? onTap,
	}) {
		final rowColor = pick == null ? null : (pick.isPicked ? pickedSideColor : pick.sideColor);
		final row = IntrinsicHeight(
			child: Row(
				crossAxisAlignment: CrossAxisAlignment.stretch,
				children: [
					SizedBox(
						width: markColumnWidth,
						child: Padding(
							padding: rowPadding,
							child: pick == null
								? null
								: Text(pick.isPicked ? pickedMark : unpickedMark, style: TextStyle(color: rowColor)),
						),
					),
					Expanded(
						child: Padding(
							padding: const EdgeInsets.symmetric(horizontal: documentInset),
							child: Container(
								padding: lineTextPadding,
								color: rowColor?.withValues(alpha: sideTintOpacity),
								child: content,
							),
						),
					),
				],
			),
		);
		if (pick == null) return row;
		return InkWell(
			onTap: onTap,
			child: Opacity(opacity: pick.isFaded ? fadedOpacity : 1, child: row),
		);
	}

	Widget _buildLines(List<String> lines, double tabWidth) {
		return Text.rich(
			checklistSpan(normalizeChecklists(lines.join(lineBreak)), tabWidth: tabWidth),
		);
	}
}
