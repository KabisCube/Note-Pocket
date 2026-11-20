import 'package:material_ui/material_ui.dart';

import '../notes/note.dart';
import '../notes/note_storage.dart';
import 'note_editor.dart';
import 'terminal_theme.dart';

const shrinkLabel = '[v]';

class NoteEditScreen extends StatefulWidget {
	const NoteEditScreen({
		super.key,
		required this.storage,
		this.note,
		this.initialTags = const [],
		this.tagColors = const {},
		this.knownTags = const [],
		this.onTagColorPicked,
		this.onSaved,
		this.onDeleted,
	});

	final NoteStorage storage;
	final Note? note;
	final List<String> initialTags;
	final Map<String, String> tagColors;
	final List<String> knownTags;
	final Future<void> Function(String tag, String? colorName)? onTagColorPicked;
	final void Function(String? previousPath, Note savedNote)? onSaved;
	final void Function(String? deletedPath)? onDeleted;

	@override
	State<NoteEditScreen> createState() => _NoteEditScreenState();
}

class _NoteEditScreenState extends State<NoteEditScreen> {
	final editorKey = GlobalKey<NoteEditorState>();

	Future<void> _close() async {
		await editorKey.currentState?.flush();
		if (mounted) Navigator.pop(context);
	}

	void _handleDeleted(String? deletedPath) {
		widget.onDeleted?.call(deletedPath);
		Navigator.pop(context);
	}

	@override
	Widget build(BuildContext context) {
		return PopScope(
			canPop: false,
			onPopInvokedWithResult: (didPop, _) {
				if (!didPop) _close();
			},
			child: Scaffold(
				body: SafeArea(
					child: Padding(
						padding: const EdgeInsets.all(screenPadding),
						child: NoteEditor(
							key: editorKey,
							storage: widget.storage,
							note: widget.note,
							initialTags: widget.initialTags,
							tagColors: widget.tagColors,
							knownTags: widget.knownTags,
							onTagColorPicked: widget.onTagColorPicked,
							fillsSpace: true,
							onApply: _close,
							onSaved: widget.onSaved,
							onDeleted: _handleDeleted,
							extraActions: [
								if (!isPhone) TextButton(onPressed: _close, child: const Text(shrinkLabel)),
							],
						),
					),
				),
			),
		);
	}
}
