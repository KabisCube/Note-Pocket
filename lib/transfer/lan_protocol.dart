// Wire format for sending one note over the local network.
// Discovery: a receiver broadcasts a small JSON announcement over UDP every second.
// Because VPNs and some routers drop broadcasts, the sender also sends a "query" datagram to
// every address of its local /24 subnets, and receivers answer it directly with an announcement.
// Transfer: the sender opens a TCP connection to the announced port, sends one JSON packet,
// closes its side, and waits for a one-line reply ("accepted" or "declined").

import 'dart:convert';
import 'dart:io';

const appId = 'note_pocket';
const discoveryPort = 53535;
const queryPort = 53536;
const queryType = 'query';
const subnetHostCount = 254;
const limitedBroadcast = '255.255.255.255';
const subnetBroadcastPart = '255';
final lastAddressPart = RegExp(r'\d+$');
const maxPacketBytes = 1024 * 1024;
const acceptedReply = 'accepted';
const declinedReply = 'declined';
const localHostName = 'localhost';

// Timing
const announceInterval = Duration(seconds: 1);
const queryInterval = Duration(seconds: 3);
const deviceTimeout = Duration(seconds: 4);
const connectTimeout = Duration(seconds: 5);
const transferTimeout = Duration(seconds: 10);
const replyTimeout = Duration(minutes: 10);

String deviceName() {
	final hostName = Platform.localHostname;
	final hasUsefulName = hostName.isNotEmpty && hostName != localHostName;
	return hasUsefulName ? hostName : Platform.operatingSystem;
}

Future<List<String>> localIPv4Addresses() async {
	final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
	return [
		for (final networkInterface in interfaces)
			for (final address in networkInterface.addresses) address.address,
	];
}

// Subnets are assumed to be /24, which covers typical home networks.
Future<List<InternetAddress>> broadcastAddresses() async {
	return [
		InternetAddress(limitedBroadcast),
		for (final address in await localIPv4Addresses())
			InternetAddress(address.replaceFirst(lastAddressPart, subnetBroadcastPart)),
	];
}

Future<List<InternetAddress>> subnetHostAddresses() async {
	return [
		for (final address in await localIPv4Addresses())
			for (var host = 1; host <= subnetHostCount; host++)
				InternetAddress(address.replaceFirst(lastAddressPart, '$host')),
	];
}

void sendToAll(RawDatagramSocket socket, List<int> message, List<InternetAddress> targets, int port) {
	for (final target in targets) {
		try {
			socket.send(message, target, port);
		} on SocketException {
			continue;
		}
	}
}

List<int> queryBytes() => _encodeAppJson({'type': queryType});

bool isQuery(List<int> bytes) => _decodeAppJson(bytes)?['type'] == queryType;

Map<String, dynamic>? _decodeAppJson(List<int> bytes) {
	try {
		final decoded = jsonDecode(utf8.decode(bytes));
		if (decoded is Map<String, dynamic> && decoded['app'] == appId) return decoded;
	} on FormatException {
		return null;
	}
	return null;
}

List<int> _encodeAppJson(Map<String, Object> fields) {
	return utf8.encode(jsonEncode({'app': appId, ...fields}));
}

class Announcement {
	const Announcement({required this.name, required this.port});

	final String name;
	final int port;

	List<int> toBytes() => _encodeAppJson({'name': name, 'port': port});

	static Announcement? fromBytes(List<int> bytes) {
		final json = _decodeAppJson(bytes);
		final name = json?['name'];
		final port = json?['port'];
		if (name is! String || port is! int) return null;
		return Announcement(name: name, port: port);
	}
}

// position and total say where this note is in a queue of notes sent together (1 of 1 for a single note).
class NotePacket {
	const NotePacket({required this.senderName, required this.content, this.position = 1, this.total = 1});

	final String senderName;
	final String content;
	final int position;
	final int total;

	bool get hasMoreComing => position < total;

	List<int> toBytes() {
		return _encodeAppJson({'sender': senderName, 'content': content, 'position': position, 'total': total});
	}

	static NotePacket? fromBytes(List<int> bytes) {
		final json = _decodeAppJson(bytes);
		final senderName = json?['sender'];
		final content = json?['content'];
		if (senderName is! String || content is! String) return null;
		final position = json?['position'];
		final total = json?['total'];
		return NotePacket(
			senderName: senderName,
			content: content,
			position: position is int ? position : 1,
			total: total is int ? total : 1,
		);
	}
}
