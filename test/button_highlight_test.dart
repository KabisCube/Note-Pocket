import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_pocket/ui/ascii_widgets.dart';
import 'package:note_pocket/ui/terminal_theme.dart';

void main() {
	testWidgets('buttons and menu buttons are inverted under the mouse, but not when they do nothing', (tester) async {
		await tester.pumpWidget(MaterialApp(
			theme: buildTerminalTheme(),
			home: Scaffold(
				body: Column(children: [
					TextButton(onPressed: () {}, child: const Text('button')),
					const TextButton(onPressed: null, child: Text('disabled')),
					invertedLabelText('label', terminalAccent),
				]),
			),
		));
		final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
		await mouse.addPointer(location: const Offset(500, 500));
		Color? colorOf(String label) {
			final text = tester.renderObject<RenderBox>(find.text(label));
			return (text as dynamic).text.style.color as Color?;
		}

		for (final (label, isInverted) in [('button', true), ('label', true), ('disabled', false)]) {
			expect(colorOf(label), terminalAccent);
			await mouse.moveTo(tester.getCenter(find.text(label)));
			await tester.pumpAndSettle();
			expect(colorOf(label), isInverted ? terminalBackground : terminalAccent);
			await mouse.moveTo(const Offset(500, 500));
			await tester.pumpAndSettle();
		}
		expect(colorOf('button'), terminalAccent);
		await mouse.removePointer();
	});

	testWidgets('a wide row gets a faint background under the mouse, also while one of its buttons is inverted', (tester) async {
		await tester.pumpWidget(MaterialApp(
			theme: buildTerminalTheme(),
			home: Scaffold(
				body: Column(children: [
					HoverRow(children: [
						const Expanded(child: Text('name')),
						TextButton(onPressed: () {}, child: const Text('button')),
					]),
				]),
			),
		));
		final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
		await mouse.addPointer(location: const Offset(500, 500));
		final background = find.descendant(of: find.byType(HoverRow), matching: find.byType(ColoredBox)).first;
		Color colorAfterMoving() => tester.widget<ColoredBox>(background).color;

		final rowCenter = tester.getCenter(find.byType(HoverRow));
		for (final position in [rowCenter, tester.getCenter(find.text('name')), tester.getCenter(find.text('button'))]) {
			await mouse.moveTo(position);
			await tester.pumpAndSettle();
			expect(colorAfterMoving(), rowHighlightColor);
		}
		expect((tester.renderObject(find.text('button')) as dynamic).text.style.color, terminalBackground);
		await mouse.moveTo(const Offset(500, 500));
		await tester.pumpAndSettle();
		expect(colorAfterMoving(), Colors.transparent);
		await mouse.removePointer();
	});
}
