// Sends one or more notes to a receiver picked from the list of devices found on the network.
// Several notes are sent one at a time; the receiver reviews each before the next one is sent.

import 'package:material_ui/material_ui.dart';

import '../notes/note.dart';
import '../transfer/lan_sender.dart';
import 'ascii_widgets.dart';
import 'terminal_theme.dart';

const sendTitle = 'SEND';
const lineGap = 8.0;

class SendScreen extends StatefulWidget {
	const SendScreen({super.key, required this.contents});

	final List<String> contents;

	@override
	State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
	late final discovery = LanDiscovery(onDevicesChanged: _updateDevices);
	List<ReceiverDevice> devices = [];
	String? statusText;
	bool isSending = false;

	int get noteCount => widget.contents.length;

	@override
	void initState() {
		super.initState();
		discovery.start().catchError((Object error) {
			if (mounted) setState(() => statusText = '[!] $error');
		});
	}

	@override
	void dispose() {
		discovery.stop();
		super.dispose();
	}

	void _updateDevices(List<ReceiverDevice> foundDevices) {
		if (mounted) setState(() => devices = foundDevices);
	}

	Future<void> _send(ReceiverDevice device) async {
		setState(() => isSending = true);
		var acceptedCount = 0;
		var declinedCount = 0;

		for (var index = 0; index < noteCount; index++) {
			final content = widget.contents[index];
			final position = index + 1;
			setState(() => statusText = 'sending $position/$noteCount: ${titleOf(content)}... waiting for ${device.name}');
			final result = await sendNote(device.address, device.port, content, position: position, total: noteCount);
			if (!mounted) return;
			if (result == SendResult.failed) {
				setState(() {
					isSending = false;
					statusText = '[!] could not reach ${device.name} ($acceptedCount/$noteCount sent)';
				});
				return;
			}
			if (result == SendResult.accepted) {
				acceptedCount++;
			} else {
				declinedCount++;
			}
		}

		setState(() {
			isSending = false;
			statusText = declinedCount == 0
				? '[ok] sent $acceptedCount/$noteCount to ${device.name}'
				: '[ok] sent $acceptedCount/$noteCount, ${device.name} declined $declinedCount';
		});
		if (acceptedCount == 0) return;
		await Future.delayed(resultDisplayTime);
		if (mounted) Navigator.pop(context, true);
	}

	@override
	Widget build(BuildContext context) {
		final summary = noteCount == 1 ? 'note: ${titleOf(widget.contents.single)}' : 'notes: $noteCount';

		return Scaffold(
			body: SafeArea(
				child: Padding(
					padding: const EdgeInsets.all(screenPadding),
					child: AsciiFrame(
						fillsSpace: true,
						label: const TypewriterText(sendTitle, style: screenTitleStyle, showCursor: false),
						actions: [
							TextButton(onPressed: () => Navigator.pop(context), child: const Text(backLabel)),
						],
						child: ListView(
							children: [
								Text(summary),
								const SizedBox(height: lineGap),
								const Row(children: [AsciiSpinner(), Text(' looking for receivers')]),
								Text('press [recv] on the other device', style: TextStyle(color: terminalDimText)),
								const SizedBox(height: lineGap),
								for (final device in devices)
									Align(
										alignment: Alignment.centerLeft,
										child: TextButton(
											onPressed: isSending ? null : () => _send(device),
											child: Text('> ${device.name}  (${device.address.address})'),
										),
									),
								if (statusText != null) ...[
									const SizedBox(height: lineGap),
									Text(statusText!),
								],
							],
						),
					),
				),
			),
		);
	}
}
