// Reminders written in a note's text:
//   reminder: 2026-12-24 13:50   at that moment
//   reminder: 2026-12-24         at 09:00 that day
//   reminder: 13:50              at the next 13:50 after the line was written, once
// "reminder", "reminder:" and "reminder=" all work, in any case.
// The app shows a popup when one comes due while it is open, and on the next start for ones that came due
// while it was closed. Which reminders have been shown is kept by the app (reminders.json in its own
// data folder), so the notes stay clean.
// Each reminder is known by its note's file, its own text and how many of the same come before it in the
// note, so editing the rest of the line doesn't bring it back.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'note.dart';

const remindersFileName = 'reminders.json';
const dateOnlyReminderHour = 9;
final reminderPattern = RegExp(
	r'\breminder\s*[:=]?\s*(?:(\d{4})-(\d{2})-(\d{2})(?:\s+(\d{1,2}):(\d{2}))?|(\d{1,2}):(\d{2}))\b',
	caseSensitive: false,
);

class Reminder {
	const Reminder({required this.notePath, required this.token, required this.occurrence, required this.lineText, this.date, this.hour, this.minute});

	final String notePath;
	// The matched text, like "reminder: 13:50"
	final String token;
	// How many of the same token come before this one in the note
	final int occurrence;
	// The whole line it is on, without list prefixes or surrounding spaces
	final String lineText;
	final DateTime? date;
	final int? hour;
	final int? minute;

	String get key => '$notePath\n${token.toLowerCase()}\n$occurrence';

	bool get hasDate => date != null;

	// When it comes due. A time without a date is the next time it is that time of day after "since".
	DateTime dueAfter(DateTime since) {
		final day = date;
		if (day != null) return DateTime(day.year, day.month, day.day, hour ?? dateOnlyReminderHour, minute ?? 0);
		final sameDay = DateTime(since.year, since.month, since.day, hour!, minute!);
		return sameDay.isAfter(since) ? sameDay : DateTime(since.year, since.month, since.day + 1, hour!, minute!);
	}
}

List<Reminder> remindersIn(Note note) => remindersInText(note.file.path, note.content);

List<Reminder> remindersInText(String notePath, String content) {
	final reminders = <Reminder>[];
	final seen = <String, int>{};
	for (final rawLine in splitLines(content)) {
		for (final match in reminderPattern.allMatches(rawLine)) {
			final parsed = _parseWhen(match);
			if (parsed == null) continue;
			final token = match[0]!;
			final occurrence = seen.update(token.toLowerCase(), (count) => count + 1, ifAbsent: () => 0);
			reminders.add(Reminder(
				notePath: notePath,
				token: token,
				occurrence: occurrence,
				lineText: noteSyntax.parse(rawLine).text.trim(),
				date: parsed.date,
				hour: parsed.hour,
				minute: parsed.minute,
			));
		}
	}
	return reminders;
}

({DateTime? date, int? hour, int? minute})? _parseWhen(RegExpMatch match) {
	final hourText = match[4] ?? match[6];
	final minuteText = match[5] ?? match[7];
	final hour = hourText == null ? null : int.parse(hourText);
	final minute = minuteText == null ? null : int.parse(minuteText);
	if (hour != null && (hour > 23 || minute! > 59)) return null;
	if (match[1] == null) return (date: null, hour: hour, minute: minute);

	final year = int.parse(match[1]!);
	final month = int.parse(match[2]!);
	final day = int.parse(match[3]!);
	final date = DateTime(year, month, day);
	// DateTime rolls invalid dates over (2026-02-30 becomes March 2nd), so those are left out
	if (date.month != month || date.day != day) return null;
	return (date: date, hour: hour, minute: minute);
}

class _Entry {
	_Entry(this.due, {this.isDone = false});

	final DateTime due;
	bool isDone;

	Map<String, Object> toJson() => {'due': due.toIso8601String(), 'done': isDone};

	static _Entry? fromJson(Object? json) {
		if (json is! Map) return null;
		final due = DateTime.tryParse('${json['due']}');
		return due == null ? null : _Entry(due, isDone: json['done'] == true);
	}
}

// Remembers when each reminder is due and whether it has been shown.
class ReminderLog {
	// With no file, nothing is kept between runs (used by tests)
	ReminderLog(this.file) : _entries = {};

	ReminderLog._withEntries(this.file, this._entries);

	final File? file;
	final Map<String, _Entry> _entries;

	static Future<ReminderLog> openDefault() async {
		final appFolder = await getApplicationSupportDirectory();
		await appFolder.create(recursive: true);
		return read(File(p.join(appFolder.path, remindersFileName)));
	}

	static Future<ReminderLog> read(File file) async {
		final entries = <String, _Entry>{};
		try {
			if (await file.exists()) {
				final json = jsonDecode(await file.readAsString());
				if (json is Map) {
					for (final item in json.entries) {
						final entry = _Entry.fromJson(item.value);
						if (entry != null) entries['${item.key}'] = entry;
					}
				}
			}
		} on FormatException {
			// A damaged file starts over; at worst a past reminder shows once more
		}
		return ReminderLog._withEntries(file, entries);
	}

	// The reminders that have come due and not been shown yet, oldest first. They are marked as shown.
	// Reminders seen for the first time get their due time:
	// - a time without a date counts from when the note was last changed, so one written while the app was
	//   closed still comes due;
	// - one that was already past when its note was written is never shown, so writing down an old date
	//   doesn't pop up.
	// Reminders whose line is gone from a note in the list are forgotten.
	List<Reminder> takeDue(List<Note> notes, DateTime now) {
		final due = <(DateTime, Reminder)>[];
		final present = <String>{};
		var isChanged = false;
		for (final note in notes) {
			final firstSeenAt = note.modified.isBefore(now) ? note.modified : now;
			for (final reminder in remindersIn(note)) {
				present.add(reminder.key);
				var entry = _entries[reminder.key];
				if (entry == null) {
					final dueAt = reminder.dueAfter(firstSeenAt);
					entry = _Entry(dueAt, isDone: !note.modified.isBefore(dueAt));
					_entries[reminder.key] = entry;
					isChanged = true;
				}
				if (!entry.isDone && !entry.due.isAfter(now)) {
					entry.isDone = true;
					isChanged = true;
					due.add((entry.due, reminder));
				}
			}
		}

		final notePaths = {for (final note in notes) note.file.path};
		final forgotten = _entries.keys.where((key) => notePaths.contains(_notePathOf(key)) && !present.contains(key)).toList();
		for (final key in forgotten) {
			_entries.remove(key);
		}
		if (isChanged || forgotten.isNotEmpty) _save();
		due.sort((first, second) => first.$1.compareTo(second.$1));
		return [for (final (_, reminder) in due) reminder];
	}

	// Keeps reminders with their note when its title changes and the file is renamed
	void renameNote(String previousPath, String newPath) {
		if (previousPath == newPath) return;
		final moved = _entries.keys.where((key) => _notePathOf(key) == previousPath).toList();
		for (final key in moved) {
			_entries['$newPath${key.substring(previousPath.length)}'] = _entries.remove(key)!;
		}
		if (moved.isNotEmpty) _save();
	}

	String _notePathOf(String key) => key.substring(0, key.indexOf(lineBreak));

	void _save() {
		file?.writeAsString(jsonEncode({for (final entry in _entries.entries) entry.key: entry.value.toJson()}));
	}
}
