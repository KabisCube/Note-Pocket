import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_pocket/ui/terminal_theme.dart';

const halfwayThroughTransition = Duration(milliseconds: 150);

class CountingPage extends StatefulWidget {
	const CountingPage({super.key});

	@override
	State<CountingPage> createState() => CountingPageState();
}

class CountingPageState extends State<CountingPage> {
	int count = 0;

	@override
	Widget build(BuildContext context) {
		return Scaffold(
			body: Column(
				children: [
					Text('count $count'),
					TextButton(onPressed: () => setState(() => count++), child: const Text('add')),
					TextButton(
						onPressed: () => Navigator.push(
							context,
							MaterialPageRoute(builder: (_) => const Scaffold(body: Text('second screen'))),
						),
						child: const Text('open'),
					),
				],
			),
		);
	}
}

void main() {
	testWidgets('screens change without animation and keep their state', (tester) async {
		await tester.pumpWidget(MaterialApp(theme: buildTerminalTheme(), home: const CountingPage()));
		await tester.tap(find.text('add'));
		await tester.pump();

		await tester.tap(find.text('open'));
		await tester.pump();
		await tester.pump(halfwayThroughTransition);
		expect(find.text('second screen'), findsOneWidget);
		await tester.pumpAndSettle();

		Navigator.of(tester.element(find.text('second screen'))).pop();
		await tester.pump();
		await tester.pump(halfwayThroughTransition);
		await tester.pumpAndSettle();

		expect(find.text('second screen'), findsNothing);
		expect(find.text('count 1'), findsOneWidget);
		expect(tester.takeException(), isNull);
	});
}
