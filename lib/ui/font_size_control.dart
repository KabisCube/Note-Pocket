// Lets the text size be tuned a few points up or down: Ctrl + scroll wheel on desktop,
// pinching with two fingers on touch screens.
// The size is applied as a text scale for the whole app, so every text and measurement follows it.
// While Ctrl is held, scrolling is turned off, so the wheel only changes the size.
// Pinches are read from raw pointer events instead of a gesture detector, so they never
// compete with scrolling or dragging.

import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../notes/notes_folder.dart';
import 'terminal_theme.dart';

const baseFontSize = 14.0;
const smallestFontSizeChange = -2;
const largestFontSizeChange = 4;
const pinchRatioPerStep = 0.15;
const fontSizeLabelTime = Duration(milliseconds: 1200);
const fontSizeLabelPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);
const fontSizeLabelBottomOffset = 24.0;

class FontSizeControl extends StatefulWidget {
	const FontSizeControl({super.key, required this.settings, required this.child});

	final AppSettings settings;
	final Widget child;

	@override
	State<FontSizeControl> createState() => _FontSizeControlState();
}

class _FontSizeControlState extends State<FontSizeControl> {
	late int fontSizeChange = widget.settings.fontSizeChange.clamp(smallestFontSizeChange, largestFontSizeChange);
	bool isControlHeld = false;
	bool isShowingLabel = false;
	Timer? labelTimer;

	final pointerPositions = <int, Offset>{};
	double? pinchStartDistance;
	int pinchStartFontSizeChange = 0;

	@override
	void initState() {
		super.initState();
		HardwareKeyboard.instance.addHandler(_handleKey);
	}

	@override
	void dispose() {
		HardwareKeyboard.instance.removeHandler(_handleKey);
		labelTimer?.cancel();
		super.dispose();
	}

	bool _handleKey(KeyEvent event) {
		final isControlPressed = HardwareKeyboard.instance.isControlPressed;
		if (isControlPressed != isControlHeld) setState(() => isControlHeld = isControlPressed);
		return false;
	}

	void _setFontSizeChange(int change) {
		final clamped = change.clamp(smallestFontSizeChange, largestFontSizeChange);
		labelTimer?.cancel();
		labelTimer = Timer(fontSizeLabelTime, () {
			if (mounted) setState(() => isShowingLabel = false);
		});
		setState(() {
			isShowingLabel = true;
			fontSizeChange = clamped;
		});
		widget.settings.setFontSizeChange(clamped);
	}

	void _handlePointerSignal(PointerSignalEvent event) {
		if (event is! PointerScrollEvent || !HardwareKeyboard.instance.isControlPressed) return;
		final step = event.scrollDelta.dy < 0 ? 1 : -1;
		_setFontSizeChange(fontSizeChange + step);
	}

	void _handlePointerDown(PointerDownEvent event) {
		pointerPositions[event.pointer] = event.position;
		if (pointerPositions.length == 2) {
			pinchStartDistance = _pinchDistance();
			pinchStartFontSizeChange = fontSizeChange;
		}
	}

	void _handlePointerMove(PointerMoveEvent event) {
		if (!pointerPositions.containsKey(event.pointer)) return;
		pointerPositions[event.pointer] = event.position;
		final startDistance = pinchStartDistance;
		if (pointerPositions.length != 2 || startDistance == null || startDistance == 0) return;

		final ratio = _pinchDistance() / startDistance;
		final steps = (log(ratio) / log(1 + pinchRatioPerStep)).truncate();
		final change = pinchStartFontSizeChange + steps;
		if (change != fontSizeChange) _setFontSizeChange(change);
	}

	void _handlePointerEnd(PointerEvent event) {
		pointerPositions.remove(event.pointer);
		if (pointerPositions.length < 2) pinchStartDistance = null;
	}

	double _pinchDistance() {
		final positions = pointerPositions.values.toList();
		return (positions[0] - positions[1]).distance;
	}

	@override
	Widget build(BuildContext context) {
		final mediaQuery = MediaQuery.of(context);
		final fontScale = (baseFontSize + fontSizeChange) / baseFontSize;
		final scrollBehavior = ScrollConfiguration.of(context).copyWith(
			physics: isControlHeld ? const NeverScrollableScrollPhysics() : null,
		);

		return Listener(
			onPointerSignal: _handlePointerSignal,
			onPointerDown: _handlePointerDown,
			onPointerMove: _handlePointerMove,
			onPointerUp: _handlePointerEnd,
			onPointerCancel: _handlePointerEnd,
			child: MediaQuery(
				data: mediaQuery.copyWith(textScaler: TextScaler.linear(mediaQuery.textScaler.scale(1) * fontScale)),
				child: ScrollConfiguration(
					behavior: scrollBehavior,
					child: Stack(
						children: [
							widget.child,
							if (isShowingLabel)
								Positioned(
									left: 0,
									right: 0,
									bottom: fontSizeLabelBottomOffset,
									child: Center(child: _buildLabel()),
								),
						],
					),
				),
			),
		);
	}

	Widget _buildLabel() {
		final fontSize = (baseFontSize + fontSizeChange).round();
		return IgnorePointer(
			child: Container(
				padding: fontSizeLabelPadding,
				decoration: BoxDecoration(color: terminalBackground, border: Border.all(color: terminalAccent)),
				child: Text('[font $fontSize]', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: terminalAccent)),
			),
		);
	}
}
