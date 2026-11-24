import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_pocket/ui/whole_pixel_scrolling.dart';

void main() {
	testWidgets('scrolling comes to rest on whole pixels', (tester) async {
		tester.view.devicePixelRatio = 1;
		addTearDown(tester.view.reset);
		final controller = ScrollController();
		await tester.pumpWidget(MaterialApp(
			builder: (_, child) => WholePixelScrolling(child: child!),
			home: Scaffold(
				body: ListView(controller: controller, children: const [SizedBox(height: 2000.5)]),
			),
		));
		controller.jumpTo(10.4);
		await tester.pump();
		expect(controller.offset, 10);

		controller.animateTo(100.5, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
		await tester.pumpAndSettle();
		expect(controller.offset, 101);

		// Half a step of a mouse wheel
		controller.jumpTo(0);
		final mouse = TestPointer(1, PointerDeviceKind.mouse)..hover(tester.getCenter(find.byType(ListView)));
		await tester.sendEventToBinding(mouse.scroll(const Offset(0, 26.5)));
		await tester.pump();
		expect(controller.offset, 27);

		controller.jumpTo(controller.position.maxScrollExtent);
		await tester.pump();
		expect(controller.offset, controller.offset.roundToDouble());
		expect(controller.offset, lessThanOrEqualTo(controller.position.maxScrollExtent));
		await tester.pumpWidget(const SizedBox());
		controller.dispose();
	});
}
