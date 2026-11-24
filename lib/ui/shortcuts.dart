// Keyboard shortcuts that can be changed in settings.
// Each action has default keys. Only changed ones are kept, in settings.ini as "shortcut.<action>=<keys>",
// where keys is a JSON list like [{"key":4294967309,"ctrl":true}], or [{"char":"+"}] for a typed character.
// keyBindings holds the keys in use, read once at startup and updated by the settings screen.
// Arrow keys, Enter and Tab completion are fixed, so they aren't listed here.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum ShortcutAction {
	closeNote('close the note', [SingleActivator(LogicalKeyboardKey.escape)]),
	saveNote('save the note', [SingleActivator(LogicalKeyboardKey.keyS, control: true)]),
	toggleCheckbox('check the selected lines', [
		SingleActivator(LogicalKeyboardKey.enter, control: true),
		// The same shortcut as in Obsidian
		SingleActivator(LogicalKeyboardKey.keyL, control: true),
	]),
	bold('bold', [SingleActivator(LogicalKeyboardKey.keyB, control: true)]),
	italic('italic', [SingleActivator(LogicalKeyboardKey.keyI, control: true)]),
	// The usual Windows keys for opening a menu
	openMenu('open the [...] menu', [
		SingleActivator(LogicalKeyboardKey.f10, shift: true),
		SingleActivator(LogicalKeyboardKey.contextMenu),
	]),
	indent('indent', [SingleActivator(LogicalKeyboardKey.tab)]),
	outdent('outdent', [SingleActivator(LogicalKeyboardKey.tab, shift: true)]),
	moveLinesUp('move lines up', [SingleActivator(LogicalKeyboardKey.arrowUp, control: true)]),
	moveLinesDown('move lines down', [SingleActivator(LogicalKeyboardKey.arrowDown, control: true)]),
	// + is shift+= on some keyboards and its own key on others, so the typed character counts
	newNote('new note (in the list)', [CharacterActivator('+'), SingleActivator(LogicalKeyboardKey.numpadAdd)]);

	const ShortcutAction(this.description, this.defaults);

	final String description;
	final List<ShortcutActivator> defaults;
}

class KeyBindings {
	KeyBindings([Map<ShortcutAction, List<ShortcutActivator>>? changed]) : changed = {...?changed};

	// Reads the changed shortcuts from their saved form, by action name. Unreadable ones are skipped.
	factory KeyBindings.fromSaved(Map<String, String> saved) {
		return KeyBindings({
			for (final action in ShortcutAction.values)
				if (decodeActivators(saved[action.name]) case final activators?) action: activators,
		});
	}

	final Map<ShortcutAction, List<ShortcutActivator>> changed;

	List<ShortcutActivator> of(ShortcutAction action) => changed[action] ?? action.defaults;

	bool isChanged(ShortcutAction action) => changed.containsKey(action);

	bool matches(ShortcutAction action, KeyEvent event) {
		return of(action).any((activator) => activator.accepts(event, HardwareKeyboard.instance));
	}

	// The bindings for CallbackShortcuts, for the actions given
	Map<ShortcutActivator, VoidCallback> callbacks(Map<ShortcutAction, VoidCallback> actions) {
		return {
			for (final entry in actions.entries)
				for (final activator in of(entry.key)) activator: entry.value,
		};
	}

	// The other actions that already use this key
	List<ShortcutAction> actionsUsing(ShortcutActivator activator, {required ShortcutAction except}) {
		final described = describeActivator(activator);
		return [
			for (final action in ShortcutAction.values)
				if (action != except && of(action).any((used) => describeActivator(used) == described)) action,
		];
	}
}

KeyBindings keyBindings = KeyBindings();

// Keys

final _modifierKeys = {
	LogicalKeyboardKey.control, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight,
	LogicalKeyboardKey.shift, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight,
	LogicalKeyboardKey.alt, LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight,
	LogicalKeyboardKey.meta, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight,
	LogicalKeyboardKey.capsLock, LogicalKeyboardKey.numLock, LogicalKeyboardKey.fn,
};

// The shortcut a key press makes, or null for a modifier key pressed on its own (or a key being let go).
SingleActivator? activatorFromEvent(KeyEvent event) {
	if (event is! KeyDownEvent || _modifierKeys.contains(event.logicalKey)) return null;
	final keyboard = HardwareKeyboard.instance;
	return SingleActivator(
		event.logicalKey,
		control: keyboard.isControlPressed,
		shift: keyboard.isShiftPressed,
		alt: keyboard.isAltPressed,
		meta: keyboard.isMetaPressed,
	);
}

String describeActivator(ShortcutActivator activator) {
	return switch (activator) {
		SingleActivator(:final trigger, :final control, :final alt, :final shift, :final meta) =>
			_withModifiers(_keyName(trigger), control: control, alt: alt, shift: shift, meta: meta),
		CharacterActivator(:final character, :final control, :final alt, :final meta) =>
			_withModifiers(character, control: control, alt: alt, shift: false, meta: meta),
		_ => '?',
	};
}

String describeActivators(List<ShortcutActivator> activators) {
	return activators.isEmpty ? 'none' : activators.map(describeActivator).join(', ');
}

String _withModifiers(String key, {required bool control, required bool alt, required bool shift, required bool meta}) {
	return [if (control) 'Ctrl', if (alt) 'Alt', if (shift) 'Shift', if (meta) 'Meta', key].join('+');
}

String _keyName(LogicalKeyboardKey key) {
	if (key == LogicalKeyboardKey.space) return 'Space';
	if (key == LogicalKeyboardKey.numpadAdd) return 'Num +';
	final label = key.keyLabel;
	if (label.isNotEmpty) return label.replaceFirst('Arrow ', '');
	return key.debugName ?? 'key ${key.keyId}';
}

// Saved form

String encodeActivators(List<ShortcutActivator> activators) {
	return jsonEncode([
		for (final activator in activators)
			switch (activator) {
				SingleActivator(:final trigger, :final control, :final alt, :final shift, :final meta) => {
					'key': trigger.keyId,
					if (control) 'ctrl': true,
					if (alt) 'alt': true,
					if (shift) 'shift': true,
					if (meta) 'meta': true,
				},
				CharacterActivator(:final character, :final control, :final alt, :final meta) => {
					'char': character,
					if (control) 'ctrl': true,
					if (alt) 'alt': true,
					if (meta) 'meta': true,
				},
				_ => throw ArgumentError('Unsupported shortcut: $activator'),
			},
	]);
}

List<ShortcutActivator>? decodeActivators(String? saved) {
	if (saved == null) return null;
	try {
		return [
			for (final item in jsonDecode(saved) as List)
				_decodeActivator(item as Map<String, dynamic>),
		];
	} on Object {
		return null;
	}
}

ShortcutActivator _decodeActivator(Map<String, dynamic> item) {
	final control = item['ctrl'] == true;
	final alt = item['alt'] == true;
	final meta = item['meta'] == true;
	final character = item['char'];
	if (character is String) return CharacterActivator(character, control: control, alt: alt, meta: meta);
	final keyId = item['key'] as int;
	return SingleActivator(
		LogicalKeyboardKey.findKeyByKeyId(keyId) ?? LogicalKeyboardKey(keyId),
		control: control,
		alt: alt,
		shift: item['shift'] == true,
		meta: meta,
	);
}
