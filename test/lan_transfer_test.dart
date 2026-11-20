import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_pocket/notes/note_storage.dart';
import 'package:note_pocket/transfer/lan_protocol.dart';
import 'package:note_pocket/transfer/lan_receiver.dart';
import 'package:note_pocket/transfer/lan_sender.dart';

const testNote = 'Groceries #green\n[ ] milk\n\t[x] oat';

Future<SendResult> sendThroughReceiver(bool isAccepted, List<NotePacket> receivedPackets) async {
	final receiver = LanReceiver(onPacket: (packet) async {
		receivedPackets.add(packet);
		return isAccepted;
	});
	await receiver.start();
	try {
		return await sendNote(InternetAddress.loopbackIPv4, receiver.port!, testNote);
	} finally {
		receiver.stop();
	}
}

void main() {
	test('packets survive encoding', () {
		final packet = NotePacket.fromBytes(const NotePacket(senderName: 'pc', content: testNote).toBytes());
		expect(packet?.content, testNote);
		expect(Announcement.fromBytes(const Announcement(name: 'pc', port: 5000).toBytes())?.port, 5000);
		expect(Announcement.fromBytes('not json'.codeUnits), isNull);
	});

	test('receivers answer direct queries with their announcement', () async {
		final receiver = LanReceiver(onPacket: (_) async => true);
		await receiver.start();
		final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
		try {
			final reply = Completer<Announcement?>();
			socket.listen((event) {
				final datagram = event == RawSocketEvent.read ? socket.receive() : null;
				if (datagram != null && !reply.isCompleted) reply.complete(Announcement.fromBytes(datagram.data));
			});
			socket.send(queryBytes(), InternetAddress.loopbackIPv4, receiver.queryListenPort!);
			final announcement = await reply.future.timeout(connectTimeout);
			expect(announcement?.port, receiver.port);
		} finally {
			socket.close();
			receiver.stop();
		}
	});

	test('a note is sent and accepted', () async {
		final received = <NotePacket>[];
		expect(await sendThroughReceiver(true, received), SendResult.accepted);
		expect(received.single.content, testNote);
	});

	test('a declined note reports declined', () async {
		expect(await sendThroughReceiver(false, []), SendResult.declined);
	});

	test('nobody listening reports failed', () async {
		final unusedSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
		final closedPort = unusedSocket.port;
		await unusedSocket.close();
		expect(await sendNote(InternetAddress.loopbackIPv4, closedPort, testNote), SendResult.failed);
	});

	test('received notes find the local copy and are saved over it', () async {
		final folder = await Directory.systemTemp.createTemp('note_pocket_receive');
		final storage = NoteStorage(folder);
		expect(await storage.findSameNamed(testNote), isNull);
		await storage.save(null, 'Groceries\nold');
		expect((await storage.findSameNamed(testNote))?.content, 'Groceries\nold');

		final saved = await storage.saveReceived(testNote);
		expect(saved.file.path, endsWith('Groceries.txt'));
		expect(await saved.file.readAsString(), testNote);
		expect(folder.listSync(), hasLength(1));
		await folder.delete(recursive: true);
	});
}
