import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lan_protocol.dart';

enum SendResult { accepted, declined, failed }

class ReceiverDevice {
	const ReceiverDevice({required this.name, required this.address, required this.port});

	final String name;
	final InternetAddress address;
	final int port;

	String get id => '$name:$port';
}

class LanDiscovery {
	LanDiscovery({required this.onDevicesChanged});

	final void Function(List<ReceiverDevice> devices) onDevicesChanged;

	final _devices = <String, ReceiverDevice>{};
	final _lastSeen = <String, DateTime>{};
	RawDatagramSocket? _socket;
	Timer? _pruneTimer;
	Timer? _queryTimer;

	Future<void> start() async {
		final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort, reuseAddress: true);
		_socket = socket;
		socket.listen((event) {
			if (event == RawSocketEvent.read) _handleDatagram(socket.receive());
		});
		_pruneTimer = Timer.periodic(announceInterval, (_) => _pruneStaleDevices());

		final query = queryBytes();
		final hosts = await subnetHostAddresses();
		void askSubnet() => sendToAll(socket, query, hosts, queryPort);
		askSubnet();
		_queryTimer = Timer.periodic(queryInterval, (_) => askSubnet());
	}

	void stop() {
		_pruneTimer?.cancel();
		_queryTimer?.cancel();
		_socket?.close();
	}

	void _handleDatagram(Datagram? datagram) {
		if (datagram == null) return;
		final announcement = Announcement.fromBytes(datagram.data);
		if (announcement == null) return;

		final device = ReceiverDevice(name: announcement.name, address: datagram.address, port: announcement.port);
		final isNewDevice = !_devices.containsKey(device.id);
		_devices.putIfAbsent(device.id, () => device);
		_lastSeen[device.id] = DateTime.now();
		if (isNewDevice) onDevicesChanged(_devices.values.toList());
	}

	void _pruneStaleDevices() {
		final cutoff = DateTime.now().subtract(deviceTimeout);
		final staleIds = [
			for (final entry in _lastSeen.entries)
				if (entry.value.isBefore(cutoff)) entry.key,
		];
		if (staleIds.isEmpty) return;
		for (final id in staleIds) {
			_devices.remove(id);
			_lastSeen.remove(id);
		}
		onDevicesChanged(_devices.values.toList());
	}
}

Future<SendResult> sendNote(
	InternetAddress address,
	int port,
	String content, {
	int position = 1,
	int total = 1,
}) async {
	Socket? socket;
	try {
		socket = await Socket.connect(address, port, timeout: connectTimeout);
		final packet = NotePacket(senderName: deviceName(), content: content, position: position, total: total);
		socket.add(packet.toBytes());
		await socket.flush();
		unawaited(socket.close());
		final reply = await utf8.decoder.bind(socket).join().timeout(replyTimeout);
		return reply == acceptedReply ? SendResult.accepted : SendResult.declined;
	} on Exception {
		return SendResult.failed;
	} finally {
		socket?.destroy();
	}
}
