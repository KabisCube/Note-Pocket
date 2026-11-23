import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_pocket/notes/notes_folder.dart';
import 'package:note_pocket/notes/path_completion.dart';

const unix = PathStyle(separator: '/', ignoresCase: false);
const windows = PathStyle(separator: r'\', ignoresCase: true);

TextEditingValue typed(String text) => TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));

void main() {
	const folders = ['Documents', 'Downloads', 'Music', '.config'];

	test('one matching folder is finished with a separator, ready for the next level', () {
		final completion = completePath(typed('/home/kb/Mu'), folders, unix);
		expect(completion.sharedPart, 'sic');
		expect(acceptPathCompletion(typed('/home/kb/Mu'), completion, unix).text, '/home/kb/Music/');
	});

	test('several matches only fill in the part they share', () {
		final completion = completePath(typed('/home/kb/Do'), folders, unix);
		expect(completion.hasOneMatch, isFalse);
		expect(acceptPathCompletion(typed('/home/kb/Do'), completion, unix).text, '/home/kb/Do');
		expect(completePath(typed('/home/kb/Doc'), folders, unix).sharedPart, 'uments');
	});

	test('hidden folders only match once a dot is typed, and case matters except on Windows', () {
		expect(completePath(typed('/home/kb/'), ['.config'], unix).isEmpty, isTrue);
		expect(completePath(typed('/home/kb/.c'), folders, unix).sharedPart, 'onfig');
		expect(completePath(typed('/home/kb/mu'), folders, unix).isEmpty, isTrue);
		final onWindows = completePath(typed(r'C:\Users\kb\mu'), folders, windows);
		expect(acceptPathCompletion(typed(r'C:\Users\kb\mu'), onWindows, windows).text, r'C:\Users\kb\Music\');
	});

	test('~ stands for the home folder', () {
		expect(expandHome('~/Notes', '/home/kb', unix), '/home/kb/Notes');
		expect(expandHome('~', '/home/kb', unix), '/home/kb');
		expect(expandHome('/srv/~/x', '/home/kb', unix), '/srv/~/x');
	});

	test('folders picked on Android become paths on the phone storage', () {
		expect(folderPathFromUri(Uri.parse('content://com.android.externalstorage.documents/tree/primary%3ADocuments%2FNotes')), '/storage/emulated/0/Documents/Notes');
		expect(folderPathFromUri(Uri.parse('content://com.android.externalstorage.documents/tree/1A2B-3C4D%3AMusic')), '/storage/1A2B-3C4D/Music');
		expect(folderPathFromUri(Uri.parse('content://com.google.android.apps.docs.storage/tree/abc')), isNull);
		expect(folderPathFromUri(Uri.file('/home/kb/Notes')), '/home/kb/Notes');
	});
}
