import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_pocket/notes/note.dart';
import 'package:note_pocket/notes/reminders.dart';

Note noteWith(String content, {required DateTime modified, String path = 'Plans.txt'}) {
	return Note(file: File(path), content: content, modified: modified);
}

void main() {
	group('reading reminders', () {
		test('a date, a date with a time, and a time alone are found', () {
			final reminders = remindersInText('a.txt', '**Plans**\n- [ ] gifts reminder: 2026-12-24\ncall reminder 2026-12-24 13:50\nREMINDER=8:05');
			expect(reminders.map((reminder) => reminder.token), ['reminder: 2026-12-24', 'reminder 2026-12-24 13:50', 'REMINDER=8:05']);
			expect(reminders[0].lineText, 'gifts reminder: 2026-12-24');
			expect(reminders[0].dueAfter(DateTime(2026)), DateTime(2026, 12, 24, dateOnlyReminderHour));
			expect(reminders[1].dueAfter(DateTime(2026)), DateTime(2026, 12, 24, 13, 50));
			expect(reminders[2].hour, 8);
			expect(reminders[2].minute, 5);
		});

		test('dates and times that do not exist are left out', () {
			expect(remindersInText('a.txt', 'reminder 2026-02-30\nreminder 24:00\nreminder 12:60\nreminders 12:00'), isEmpty);
		});

		test('a time alone comes due at the next time it is that time of day', () {
			final reminder = remindersInText('a.txt', 'reminder 13:50').single;
			expect(reminder.dueAfter(DateTime(2026, 5, 1, 9)), DateTime(2026, 5, 1, 13, 50));
			expect(reminder.dueAfter(DateTime(2026, 5, 1, 14)), DateTime(2026, 5, 2, 13, 50));
		});
	});

	group('showing reminders', () {
		test('a reminder shows once, when it comes due', () {
			final log = ReminderLog(null);
			final notes = [noteWith('**Plans**\ncall reminder 13:50', modified: DateTime(2026, 5, 1, 9))];
			expect(log.takeDue(notes, DateTime(2026, 5, 1, 13, 49)), isEmpty);
			expect(log.takeDue(notes, DateTime(2026, 5, 1, 13, 50)).single.lineText, 'call reminder 13:50');
			expect(log.takeDue(notes, DateTime(2026, 5, 1, 13, 51)), isEmpty);
			expect(log.takeDue(notes, DateTime(2026, 5, 2, 13, 51)), isEmpty);
		});

		test('one that came due while the app was closed shows on the next start', () {
			final log = ReminderLog(null);
			final notes = [noteWith('reminder 2026-12-24', modified: DateTime(2026, 12, 1))];
			expect(log.takeDue(notes, DateTime(2026, 12, 26)), hasLength(1));
		});

		test('a date that was already past when the note was written never shows', () {
			final log = ReminderLog(null);
			final notes = [noteWith('reminder 2020-01-01', modified: DateTime(2026, 5, 1))];
			expect(log.takeDue(notes, DateTime(2026, 5, 1, 0, 1)), isEmpty);
		});

		test('editing the rest of the line does not bring a shown reminder back', () {
			final log = ReminderLog(null);
			final written = DateTime(2026, 5, 1, 9);
			log.takeDue([noteWith('call reminder 13:50', modified: written)], DateTime(2026, 5, 1, 14));
			final edited = [noteWith('call mum reminder 13:50', modified: DateTime(2026, 5, 1, 15))];
			expect(log.takeDue(edited, DateTime(2026, 5, 2, 14)), isEmpty);
		});

		test('a renamed note keeps its reminders', () {
			final log = ReminderLog(null);
			final written = DateTime(2026, 5, 1, 9);
			log.takeDue([noteWith('reminder 13:50', modified: written, path: 'Old.txt')], DateTime(2026, 5, 1, 14));
			log.renameNote('Old.txt', 'New.txt');
			expect(log.takeDue([noteWith('reminder 13:50', modified: written, path: 'New.txt')], DateTime(2026, 5, 2, 14)), isEmpty);
		});

		test('shown reminders are remembered between runs', () async {
			final folder = await Directory.systemTemp.createTemp('note_pocket_reminders');
			final file = File('${folder.path}/$remindersFileName');
			final notes = [noteWith('reminder 2026-12-24', modified: DateTime(2026, 12, 1))];
			final first = await ReminderLog.read(file);
			expect(first.takeDue(notes, DateTime(2026, 12, 26)), hasLength(1));
			await Future<void>.delayed(const Duration(milliseconds: 50));
			final second = await ReminderLog.read(file);
			expect(second.takeDue(notes, DateTime(2026, 12, 27)), isEmpty);
			await folder.delete(recursive: true);
		});
	});
}
