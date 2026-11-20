import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_pocket/notes/notes_folder.dart';
import 'package:note_pocket/ui/font_size_control.dart';

const scrollUpOneNotch = Offset(0, -100);
const pinchStartGap = 100.0;
const pinchWideGap = 200.0;
const pinchCenter = Offset(200, 300);

Future<double> fontScaleIn(WidgetTester tester) async {
	return MediaQuery.textScalerOf(tester.element(find.text('sample'))).scale(1);
}

Future<AppSettings> pumpApp(WidgetTester tester, File settingsFile) async {
	final settings = AppSettings(settingsFile, {});
	await tester.pumpWidget(MaterialApp(
		builder: (context, child) => FontSizeControl(settings: settings, child: child!),
		home: const Scaffold(body: Center(child: Text('sample'))),
	));
	return settings;
}

void main() {
	testWidgets('ctrl + scroll changes the text size within limits', (tester) async {
		final settings = await pumpApp(tester, File('${Directory.systemTemp.path}/note_pocket_font_test.ini'));
		expect(await fontScaleIn(tester), 1);

		await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
		final mouse = TestPointer(1, PointerDeviceKind.mouse);
		await tester.sendEventToBinding(mouse.hover(tester.getCenter(find.text('sample'))));
		for (var notch = 0; notch < 10; notch++) {
			await tester.sendEventToBinding(mouse.scroll(scrollUpOneNotch));
		}
		await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
		await tester.pump();

		expect(await fontScaleIn(tester), (baseFontSize + largestFontSizeChange) / baseFontSize);
		expect(settings.fontSizeChange, largestFontSizeChange);
		await tester.pump(fontSizeLabelTime);
	});

	testWidgets('pinching two fingers apart makes the text bigger', (tester) async {
		await pumpApp(tester, File('${Directory.systemTemp.path}/note_pocket_pinch_test.ini'));
		final firstFinger = await tester.startGesture(pinchCenter - const Offset(pinchStartGap / 2, 0), pointer: 1);
		final secondFinger = await tester.startGesture(pinchCenter + const Offset(pinchStartGap / 2, 0), pointer: 2);
		await firstFinger.moveTo(pinchCenter - const Offset(pinchWideGap / 2, 0));
		await secondFinger.moveTo(pinchCenter + const Offset(pinchWideGap / 2, 0));
		await firstFinger.up();
		await secondFinger.up();
		await tester.pump();

		expect(await fontScaleIn(tester), greaterThan(1));
		await tester.pump(fontSizeLabelTime);
	});
}
