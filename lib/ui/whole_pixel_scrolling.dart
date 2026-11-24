// Makes scrolling come to rest on whole screen pixels. Half a step of a fine mouse wheel, or a touchpad, can stop
// between two pixels, and then thin horizontal lines are smeared over both.

import 'dart:async';

import 'package:material_ui/material_ui.dart';

class WholePixelScrolling extends StatelessWidget {
	const WholePixelScrolling({super.key, required this.child});

	final Widget child;

	bool _handleScrollEnd(ScrollEndNotification notification) {
		final context = notification.context;
		final position = context == null ? null : Scrollable.maybeOf(context)?.position;
		if (position == null || position.axis != Axis.vertical) return false;
		final pixelRatio = notification.metrics.devicePixelRatio;
		// The scroll that just ended has to finish first
		scheduleMicrotask(() => _settle(position, pixelRatio));
		return false;
	}

	void _settle(ScrollPosition position, double pixelRatio) {
		if (!position.context.storageContext.mounted || position.isScrollingNotifier.value || position.outOfRange) return;
		var pixels = (position.pixels * pixelRatio).roundToDouble() / pixelRatio;
		if (pixels > position.maxScrollExtent) pixels = (position.pixels * pixelRatio).floorToDouble() / pixelRatio;
		if (pixels != position.pixels) position.jumpTo(pixels);
	}

	@override
	Widget build(BuildContext context) {
		return NotificationListener<ScrollEndNotification>(onNotification: _handleScrollEnd, child: child);
	}
}
