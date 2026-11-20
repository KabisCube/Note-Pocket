import 'package:material_ui/material_ui.dart';

import '../notes/note.dart';
import '../notes/note_storage.dart';
import '../transfer/lan_protocol.dart';
import '../transfer/lan_receiver.dart';
import 'ascii_widgets.dart';
import 'review_screen.dart';
import 'terminal_theme.dart';

const receiveTitle = 'RECEIVE';
const lineGap = 8.0;

class ReceiveScreen extends StatefulWidget {
	const ReceiveScreen({super.key, required this.storage});

	final NoteStorage storage;

	@override
	State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
	late final receiver = LanReceiver(onPacket: _askToSave);
	final log = <String>[];
	String? errorText;
	String? lastSavedPath;

	@override
	void initState() {
		super.initState();
		receiver.start().catchError((Object error) {
			if (mounted) setState(() => errorText = '$error');
		});
	}

	@override
	void dispose() {
		receiver.stop();
		super.dispose();
	}

	Future<bool> _askToSave(NotePacket packet) async {
		if (!mounted) return false;
		final title = titleOf(packet.content);
		final localNote = await widget.storage.findSameNamed(packet.content);
		if (!mounted) return false;

		final savedPath = await Navigator.push<String>(
			context,
			MaterialPageRoute(
				builder: (_) => ReviewScreen(storage: widget.storage, packet: packet, localNote: localNote),
			),
		);
		final queueText = packet.total > 1 ? ' (${packet.position}/${packet.total})' : '';
		_addLog(savedPath == null ? '[n] $title$queueText' : '[ok] $title$queueText');
		lastSavedPath = savedPath ?? lastSavedPath;

		final pathToShow = lastSavedPath;
		if (!packet.hasMoreComing && pathToShow != null && mounted) Navigator.pop(context, pathToShow);
		return savedPath != null;
	}

	void _addLog(String line) {
		if (mounted) setState(() => log.add(line));
	}

	@override
	Widget build(BuildContext context) {
		return Scaffold(
			body: SafeArea(
				child: Padding(
					padding: const EdgeInsets.all(screenPadding),
					child: AsciiFrame(
						fillsSpace: true,
						label: const TypewriterText(receiveTitle, style: screenTitleStyle, showCursor: false),
						actions: [
							TextButton(onPressed: () => Navigator.pop(context), child: const Text(backLabel)),
						],
						child: ListView(
							children: [
								if (errorText == null)
									Row(children: [const AsciiSpinner(), Text(' listening as ${deviceName()}')])
								else
									Text('[!] $errorText'),
								const SizedBox(height: lineGap),
								Text('press [send] on a note on the other device', style: TextStyle(color: terminalDimText)),
								const SizedBox(height: lineGap),
								for (final line in log) Text(line),
							],
						),
					),
				),
			),
		);
	}
}
