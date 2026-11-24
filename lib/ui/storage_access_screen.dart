// Shown on Android when the notes folder needs "All files access".
// Rechecks automatically when the user comes back from the system settings.

import 'package:material_ui/material_ui.dart';

import '../notes/notes_folder.dart';
import 'ascii_widgets.dart';
import 'terminal_theme.dart';

const accessTitle = 'ACCESS';
const grantLabel = '[grant access]';
const useAppFolderLabel = '[use app folder instead]';
const lineGap = 8.0;

class StorageAccessScreen extends StatefulWidget {
	const StorageAccessScreen({super.key, required this.onRetry, required this.onUseAppFolder});

	final VoidCallback onRetry;
	final VoidCallback onUseAppFolder;

	@override
	State<StorageAccessScreen> createState() => _StorageAccessScreenState();
}

class _StorageAccessScreenState extends State<StorageAccessScreen> with WidgetsBindingObserver {
	@override
	void initState() {
		super.initState();
		WidgetsBinding.instance.addObserver(this);
	}

	@override
	void dispose() {
		WidgetsBinding.instance.removeObserver(this);
		super.dispose();
	}

	@override
	void didChangeAppLifecycleState(AppLifecycleState state) {
		if (state == AppLifecycleState.resumed) widget.onRetry();
	}

	@override
	Widget build(BuildContext context) {
		return Scaffold(
			body: SafeArea(
				child: Padding(
					padding: const EdgeInsets.all(screenPadding),
					child: AsciiFrame(
						fillsSpace: true,
						label: const TypewriterText(accessTitle, style: screenTitleStyle, showCursor: false),
						child: ListView(
							children: [
								const Text('notes are kept as .txt files in Documents/$notesFolderName.'),
								const SizedBox(height: lineGap),
								Text(
									"allow 'All files access' so Note Pocket can read and write that folder.",
									style: TextStyle(color: terminalDimText),
								),
								const SizedBox(height: lineGap),
								Align(
									alignment: Alignment.centerLeft,
									child: TextButton(onPressed: requestStorageAccess, child: const Text(grantLabel)),
								),
								Align(
									alignment: Alignment.centerLeft,
									child: TextButton(
										onPressed: widget.onUseAppFolder,
										style: invertedButtonStyle(terminalDimText),
										child: const Text(useAppFolderLabel),
									),
								),
							],
						),
					),
				),
			),
		);
	}
}
