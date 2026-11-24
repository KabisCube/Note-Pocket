// Colors and Material theme for the app.
// The active palette can be switched at runtime (Settings > theme). The color names below read from
// it, so anything that draws with them picks up the new colors when the app rebuilds.

import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'terminal_page_transition.dart';

class Palette {
	const Palette({
		required this.name,
		required this.brightness,
		required this.background,
		required this.text,
		required this.dimText,
		required this.titleColors,
	});

	final String name;
	final Brightness brightness;
	final Color background;
	final Color text;
	final Color dimText;
	// Note title colors, keyed by the names in titleColorNames
	final Map<String, Color> titleColors;
}

const darkPalette = Palette(
	name: 'dark',
	brightness: Brightness.dark,
	background: Color(0xFF3C3C3C),
	text: Color(0xFFDCDCDC),
	dimText: Color(0xFF8C8C8C),
	titleColors: {
		'green': Color(0xFFA6E08C),
		'yellow': Color(0xFFE8D36A),
		'orange': Color(0xFFF0A35E),
		'red': Color(0xFFF07878),
		'pink': Color(0xFFF0A0C8),
		'purple': Color(0xFFC3A0F0),
		'blue': Color(0xFF82B4F0),
		'cyan': Color(0xFF78DCDC),
	},
);

const lightPalette = Palette(
	name: 'light',
	brightness: Brightness.light,
	background: Color(0xFFE1E1E1),
	text: Color(0xFF1E1E1E),
	dimText: Color(0xFF6E6E6E),
	titleColors: {
		'green': Color(0xFF3E8E2C),
		'yellow': Color(0xFF8F7300),
		'orange': Color(0xFFB35A00),
		'red': Color(0xFFBF2E2E),
		'pink': Color(0xFFB03A7A),
		'purple': Color(0xFF7448B8),
		'blue': Color(0xFF2B60B5),
		'cyan': Color(0xFF0F8585),
	},
);

const highContrastPalette = Palette(
	name: 'high contrast',
	brightness: Brightness.dark,
	background: Color(0xFF000000),
	text: Color(0xFFFFFFFF),
	dimText: Color(0xFFA8A8A8),
	titleColors: {
		'green': Color(0xFFB8FF9A),
		'yellow': Color(0xFFFFE566),
		'orange': Color(0xFFFFAD5C),
		'red': Color(0xFFFF7A7A),
		'pink': Color(0xFFFFA8D6),
		'purple': Color(0xFFD2ADFF),
		'blue': Color(0xFF8CC2FF),
		'cyan': Color(0xFF7FF5F5),
	},
);

const palettes = [darkPalette, lightPalette, highContrastPalette];

// "system" follows the OS's light or dark mode, and is used until a theme is picked in settings
const systemThemeName = 'system';
final themeNames = [systemThemeName, for (final palette in palettes) palette.name];
String chosenThemeName = systemThemeName;
Palette currentPalette = darkPalette;
// The accent color is one of the note color names, green unless picked otherwise in settings
const defaultAccentColorName = 'green';
String accentColorName = defaultAccentColorName;

Palette paletteNamed(String? name) {
	return palettes.firstWhere((palette) => palette.name == name, orElse: () => darkPalette);
}

void applyThemeName(String? themeName) {
	chosenThemeName = themeName ?? systemThemeName;
	if (chosenThemeName != systemThemeName) {
		currentPalette = paletteNamed(chosenThemeName);
		return;
	}
	final systemBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
	currentPalette = systemBrightness == Brightness.dark ? darkPalette : lightPalette;
}

// Colors
Color get terminalBackground => currentPalette.background;
Color get terminalText => currentPalette.text;
Color get terminalDimText => currentPalette.dimText;
Color get terminalAccent => titleColorFor(accentColorName);
Map<String, Color> get titleColors => currentPalette.titleColors;

// Buttons under the mouse, pressed or with the keyboard focus are shown the terminal way: text and
// background swap colors. The space beside the label stays clear, so the highlight doesn't touch a border.
ButtonStyle invertedButtonStyle(Color color) {
	bool isHighlighted(Set<WidgetState> states) {
		if (states.contains(WidgetState.disabled)) return false;
		return states.any({WidgetState.focused, WidgetState.hovered, WidgetState.pressed}.contains);
	}
	return ButtonStyle(
		foregroundColor: WidgetStateProperty.resolveWith((states) => isHighlighted(states) ? terminalBackground : color),
		backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
		overlayColor: const WidgetStatePropertyAll(Colors.transparent),
		padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: compactButtonPadding.vertical / 2)),
		animationDuration: Duration.zero,
		backgroundBuilder: (_, states, child) => Padding(
			padding: EdgeInsets.symmetric(horizontal: compactButtonPadding.horizontal / 2),
			child: ColoredBox(color: isHighlighted(states) ? color : Colors.transparent, child: child),
		),
	);
}

Color titleColorFor(String? name) => titleColors[name] ?? terminalText;

// Borders and tags of colored notes use a dimmed color, like the gray of uncolored notes
const dullAmount = 0.45;

Color dulled(Color color) => Color.lerp(color, terminalBackground, dullAmount)!;

// A faint background that marks the row under the mouse
const rowHighlightAmount = 0.1;

Color get rowHighlightColor => Color.lerp(terminalBackground, terminalText, rowHighlightAmount)!;

// Font
const terminalFont = 'Consolas';
const terminalFontFallback = ['DejaVu Sans Mono', 'Ubuntu Mono', 'monospace'];

// Phones have no Tab or Ctrl keys, so they get line buttons at the bottom of notes, and menu rows big enough to tap
final isPhone = Platform.isAndroid || Platform.isIOS;

// Layout
const screenPadding = 8.0;
const compactButtonPadding = EdgeInsets.symmetric(horizontal: 4, vertical: 2);
// Every dropdown uses the same row height and padding
const boldTextStyle = TextStyle(fontWeight: FontWeight.bold);
const italicTextStyle = TextStyle(fontStyle: FontStyle.italic);
final menuItemHeight = isPhone ? 35.0 : 26.0;
const menuItemPadding = EdgeInsets.symmetric(horizontal: 10);
RoundedRectangleBorder get squareShape => RoundedRectangleBorder(side: BorderSide(color: terminalDimText));

ThemeData buildTerminalTheme() {
	final isDark = currentPalette.brightness == Brightness.dark;
	final textTheme = (isDark ? ThemeData.dark() : ThemeData.light()).textTheme.apply(
		fontFamily: terminalFont,
		fontFamilyFallback: terminalFontFallback,
		bodyColor: terminalText,
		displayColor: terminalText,
	);
	final colorScheme = isDark
		? ColorScheme.dark(surface: terminalBackground, onSurface: terminalText, primary: terminalAccent)
		: ColorScheme.light(surface: terminalBackground, onSurface: terminalText, primary: terminalAccent);

	return ThemeData(
		brightness: currentPalette.brightness,
		fontFamily: terminalFont,
		fontFamilyFallback: terminalFontFallback,
		textTheme: textTheme,
		scaffoldBackgroundColor: terminalBackground,
		pageTransitionsTheme: instantPageTransitions,
		splashFactory: NoSplash.splashFactory,
		highlightColor: Colors.transparent,
		hoverColor: Colors.transparent,
		focusColor: Colors.transparent,
		colorScheme: colorScheme,
		dialogTheme: DialogThemeData(backgroundColor: terminalBackground, shape: squareShape),
		popupMenuTheme: PopupMenuThemeData(color: terminalBackground, shape: squareShape, elevation: 0),
		textButtonTheme: TextButtonThemeData(
			style: invertedButtonStyle(terminalAccent).merge(
				TextButton.styleFrom(
					shape: const RoundedRectangleBorder(),
					minimumSize: Size.zero,
					tapTargetSize: MaterialTapTargetSize.shrinkWrap,
					splashFactory: NoSplash.splashFactory,
				),
			),
		),
		textSelectionTheme: TextSelectionThemeData(
			cursorColor: terminalAccent,
			// Opaque, since selected text is drawn in the background color (see inverted_selection.dart)
			selectionColor: terminalText,
			selectionHandleColor: terminalAccent,
		),
	);
}
