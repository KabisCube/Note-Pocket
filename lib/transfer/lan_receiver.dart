import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'lan_protocol.dart';

class LanReceiver {
	LanReceiver({required this.onPacket});

	final Future<bool> Function(NotePacket packet) onPacket;

	ServerSocket? _server;
	RawDatagramSocket? _discoverySocket;
	Timer? _announceTimer;

	int? get port => _server?.port;
	int? get queryListenPort => _discoverySocket?.port;

	Future<void> start() async {
		final server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
		_server = server;
		server.listen(_handleConnection);

		final discoverySocket = await _bindDiscoverySocket();
		discoverySocket.broadcastEnabled = true;
		_discoverySocket = discoverySocket;

		final announcement = Announcement(name: deviceName(), port: server.port).toBytes();
		discoverySocket.listen((event) {
			if (event != RawSocketEvent.read) return;
			final datagram = discoverySocket.receive();
			if (datagram == null || !isQuery(datagram.data)) return;
			sendToAll(discoverySocket, announcement, [datagram.address], datagram.port);
		});

		final targets = await broadcastAddresses();
		void announce() => sendToAll(discoverySocket, announcement, targets, discoveryPort);
		announce();
		_announceTimer = Timer.periodic(announceInterval, (_) => announce());
	}

	void stop() {
		_announceTimer?.cancel();
		_discoverySocket?.close();
		_server?.close();
	}

	Future<RawDatagramSocket> _bindDiscoverySocket() async {
		try {
			return await RawDatagramSocket.bind(InternetAddress.anyIPv4, queryPort, reuseAddress: false);
		} on SocketException {
			return RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
		}
	}

	Future<void> _handleConnection(Socket socket) async {
		try {
			final packet = NotePacket.fromBytes(await _readAll(socket));
			final isAccepted = packet != null && await onPacket(packet);
			socket.write(isAccepted ? acceptedReply : declinedReply);
			await socket.flush();
		} on Exception {
			return;
		} finally {
			socket.destroy();
		}
	}

	Future<List<int>> _readAll(Socket socket) async {
		final bytes = BytesBuilder(copy: false);
		await for (final chunk in socket.timeout(transferTimeout)) {
			bytes.add(chunk);
			if (bytes.length > maxPacketBytes) throw const SocketException('note too large');
		}
		return bytes.takeBytes();
	}
}
