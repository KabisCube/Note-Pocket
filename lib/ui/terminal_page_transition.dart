// Screen changes happen instantly, without Flutter's default zoom.
// A closing screen is hidden right away, so going back doesn't wait for the route animation.

import 'package:material_ui/material_ui.dart';

class InstantPageTransitionsBuilder extends PageTransitionsBuilder {
	const InstantPageTransitionsBuilder();

	@override
	Widget buildTransitions<T>(
		PageRoute<T> route,
		BuildContext context,
		Animation<double> animation,
		Animation<double> secondaryAnimation,
		Widget child,
	) {
		return AnimatedBuilder(
			animation: animation,
			child: child,
			builder: (context, child) => Opacity(
				opacity: animation.status == AnimationStatus.reverse ? 0 : 1,
				child: child,
			),
		);
	}
}

PageTransitionsTheme get instantPageTransitions {
	return PageTransitionsTheme(
		builders: {
			for (final platform in TargetPlatform.values) platform: const InstantPageTransitionsBuilder(),
		},
	);
}
