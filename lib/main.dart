import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'notes/note_order.dart';
import 'notes/note_storage.dart';
import 'notes/notes_folder.dart';
import 'ui/font_size_control.dart';
import 'ui/note_list_screen.dart';
import 'ui/storage_access_screen.dart';
import 'ui/terminal_theme.dart';

const appName = 'Note Pocket';

Future<void> main() async {
	WidgetsFlutterBinding.ensureInitialized();
	final settings = await AppSettings.load();
	applyThemeName(settings.theme);
	accentColorName = settings.accentColor ?? defaultAccentColorName;
	final order = await NoteOrder.openDefault();
	runApp(NotePocketApp(settings: settings, order: order));
}

class NotePocketApp extends StatefulWidget {
	const NotePocketApp({super.key, required this.settings, required this.order});

	final AppSettings settings;
	final NoteOrder order;

	@override
	State<NotePocketApp> createState() => _NotePocketAppState();
}

class _NotePocketAppState extends State<NotePocketApp> with WidgetsBindingObserver {
	NoteStorage? storage;
	bool isWaitingForAccess = false;

	@override
	void initState() {
		super.initState();
		WidgetsBinding.instance.addObserver(this);
		_openNotes();
	}

	@override
	void dispose() {
		WidgetsBinding.instance.removeObserver(this);
		super.dispose();
	}

	@override
	void didChangePlatformBrightness() {
		if (chosenThemeName == systemThemeName) _applyColors(() => applyThemeName(systemThemeName));
	}

	Future<void> _openNotes() async {
		final folderPath = widget.settings.notesFolder ?? await defaultNotesFolder();
		if (await needsStorageAccess(folderPath)) {
			if (mounted) setState(() => isWaitingForAccess = true);
			return;
		}

		final openedStorage = await _openOrFallBack(folderPath);
		await copyPrivateNotesOnce(widget.settings, openedStorage.folder.path);
		if (!mounted) return;
		setState(() {
			storage = openedStorage;
			isWaitingForAccess = false;
		});
	}

	Future<NoteStorage> _openOrFallBack(String folderPath) async {
		try {
			return await NoteStorage.open(folderPath);
		} on FileSystemException {
			return NoteStorage.open(await privateNotesFolder());
		}
	}

	Future<void> _useAppFolder() async {
		await widget.settings.setNotesFolder(await privateNotesFolder());
		await _openNotes();
	}

	Future<void> _changeTheme(String themeName) async {
		await widget.settings.setTheme(themeName);
		_applyColors(() => applyThemeName(themeName));
	}

	Future<void> _changeAccentColor(String colorName) async {
		await widget.settings.setAccentColor(colorName);
		_applyColors(() => accentColorName = colorName);
	}

	// Colors are read straight from the palette, so every widget is rebuilt to pick up the change.
	void _applyColors(VoidCallback change) {
		setState(change);
		void rebuild(Element element) {
			element.markNeedsBuild();
			element.visitChildren(rebuild);
		}
		(context as Element).visitChildren(rebuild);
	}

	Future<void> _changeNotesFolder(String? folderPath) async {
		await widget.settings.setNotesFolder(folderPath);
		await _openNotes();
	}

	@override
	Widget build(BuildContext context) {
		return MaterialApp(
			title: appName,
			theme: buildTerminalTheme(),
			scrollBehavior: const MaterialScrollBehavior().copyWith(scrollbars: false),
			builder: (context, child) => FontSizeControl(settings: widget.settings, child: child!),
			home: _buildHome(),
		);
	}

	Widget _buildHome() {
		final openedStorage = storage;
		if (openedStorage != null) {
			return NoteListScreen(
				key: ValueKey(openedStorage.folder.path),
				storage: openedStorage,
				order: widget.order,
				settings: widget.settings,
				onNotesFolderChanged: _changeNotesFolder,
				onThemeChanged: _changeTheme,
				onAccentColorChanged: _changeAccentColor,
			);
		}
		if (isWaitingForAccess) {
			return StorageAccessScreen(onRetry: _openNotes, onUseAppFolder: _useAppFolder);
		}
		return const Scaffold();
	}
}
