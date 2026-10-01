import 'package:flutter/cupertino.dart';
import 'package:pull_down_button/pull_down_button.dart';

// One navy neutral ramp (docs/specs/tablet-ui.md, Visual style). WCAG 2.2
// contrast of each text color on background / surface1 / surface2 /
// surface3:
//   label           15.6 / 13.7 / 11.7 / 9.7
//   secondaryLabel   8.0 /  7.0 /  6.0 / 5.0
//   accentText       7.8 /  6.9 /  5.9 / 4.9
//   destructive      7.5 /  6.6 /  5.6 / 4.7
// White on accent is 4.6. tertiaryLabel (5.4 / 4.7 / 4.0 / 3.3) marks
// disabled controls only, which WCAG 1.4.3 exempts.
const background = Color(0xFF151B2B);
const surface1 = Color(0xFF1E2638);
const surface2 = Color(0xFF283247);
const surface3 = Color(0xFF333E56);
const separator = Color(0x1FFFFFFF);
const label = Color(0xFFF2F4F8);
const secondaryLabel = Color(0xFFA9B1C3);
const tertiaryLabel = Color(0xFF8790A6);
const accent = Color(0xFF2F6FEB);
const accentText = Color(0xFF8AAEFF);
const onAccent = Color(0xFFFFFFFF);
const destructive = Color(0xFFFF8A80);
// Warning icons: 6.8 or more on every surface.
const warning = Color(0xFFFFC46B);
const selectedFill = Color(0x662F6FEB);
const coverInk = Color(0xFF1C2230);
// The default page fill: ink samples sit on it so they read as on the page.
const paper = Color(0xFFFFFFFF);
const paperEdge = Color(0xFFD5D9E2);

// Elevation: one shadow per level.
const floatingShadow = [
  BoxShadow(color: Color(0x59000000), blurRadius: 16, offset: Offset(0, 4)),
];
const modalShadow = [
  BoxShadow(color: Color(0x80000000), blurRadius: 40, offset: Offset(0, 12)),
];

// Type roles on one scale. Inter carries its own tracking, so letterSpacing
// is 0 everywhere; Cupertino's defaults carry SF Pro's negative tracking.
const _ui = TextStyle(
  inherit: false,
  fontFamily: 'Inter',
  letterSpacing: 0,
  color: label,
  textBaseline: TextBaseline.alphabetic,
);
final footnote = _ui.copyWith(fontSize: 13, height: 18 / 13);
final callout = _ui.copyWith(fontSize: 15, height: 20 / 15);
final subhead = callout.copyWith(fontWeight: FontWeight.w600);
final body = _ui.copyWith(fontSize: 17, height: 22 / 17);
final headline = body.copyWith(fontWeight: FontWeight.w600);
final title = _ui.copyWith(
  fontSize: 20,
  height: 25 / 20,
  fontWeight: FontWeight.w600,
);
final largeTitle = _ui.copyWith(
  fontSize: 28,
  height: 34 / 28,
  fontWeight: FontWeight.w700,
);

final cupertinoTheme = CupertinoThemeData(
  brightness: Brightness.dark,
  primaryColor: accentText,
  primaryContrastingColor: onAccent,
  scaffoldBackgroundColor: background,
  barBackgroundColor: surface1,
  textTheme: CupertinoTextThemeData(
    primaryColor: accentText,
    textStyle: body,
    actionTextStyle: body.copyWith(color: accentText),
    actionSmallTextStyle: callout.copyWith(color: accentText),
    tabLabelTextStyle: _ui.copyWith(fontSize: 13, fontWeight: FontWeight.w500),
    navTitleTextStyle: headline,
    navLargeTitleTextStyle: largeTitle,
    navActionTextStyle: body.copyWith(color: accentText),
    pickerTextStyle: _ui.copyWith(fontSize: 21),
    dateTimePickerTextStyle: _ui.copyWith(fontSize: 21),
  ),
);

final pullDownTheme = PullDownButtonTheme(
  routeTheme: PullDownMenuRouteTheme(
    backgroundColor: surface2,
    borderRadius: const BorderRadius.all(Radius.circular(12)),
    shadow: floatingShadow.first,
  ),
  itemTheme: PullDownMenuItemTheme(
    destructiveColor: destructive,
    textStyle: body,
    subtitleStyle: callout.copyWith(color: secondaryLabel),
    iconActionTextStyle: footnote,
    onHoverBackgroundColor: surface3,
    onPressedBackgroundColor: surface3,
  ),
  dividerTheme: const PullDownMenuDividerTheme(
    dividerColor: separator,
    largeDividerColor: background,
  ),
  titleTheme: PullDownMenuTitleTheme(
    style: footnote.copyWith(color: secondaryLabel),
  ),
);

String hex(int rgb) => '#${rgb.toRadixString(16).padLeft(6, '0')}';
