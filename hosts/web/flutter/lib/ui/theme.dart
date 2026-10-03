import 'package:flutter/cupertino.dart';
import 'package:pull_down_button/pull_down_button.dart';

// Bound volumes (docs/reports/Visual direction.md): binder's board for the
// desk and chrome, leaf for sheets and menus, blue-black ink for text, and a
// red ribbon that marks the current selection and nothing else. WCAG 2.2
// contrast of each text color on background / surface2 / surface3:
//   label           11.4 / 13.6 / 15.0
//   secondaryLabel   4.9 /  5.8 /  6.4
//   accentText       5.4 /  6.5 /  7.1
//   destructive      5.4 /  6.5 /  7.1
// surface2 on label (filled buttons) is 13.6; white on accent is 7.4.
// tertiaryLabel marks disabled controls only, which WCAG 1.4.3 exempts.
const background = Color(0xFFDADDD5);
const surface1 = Color(0xFFDADDD5);
const surface2 = Color(0xFFEEF0EA);
const surface3 = Color(0xFFFBFAF6);
const separator = Color(0x291C2430);
const label = Color(0xFF1C2430);
const secondaryLabel = Color(0xFF555D67);
const tertiaryLabel = Color(0xFF7D858E);
const accent = Color(0xFF9E2A2B);
const accentText = Color(0xFF9E2A2B);
const onAccent = Color(0xFFFFFFFF);
const destructive = Color(0xFF9E2A2B);
// Warning icons: 5.2 or more on every surface.
const warning = Color(0xFF7A4E00);
const selectedFill = Color(0x1F9E2A2B);
const coverInk = Color(0xFF1C2430);
// The default page fill: ink samples sit on it so they read as on the page.
const paper = Color(0xFFFBFAF6);
const paperEdge = Color(0xFFC9CDC3);
// Buckram for notebook covers, with the title on a paper spine label.
const coverColors = {
  '#24324A': 'Navy',
  '#5B2328': 'Oxblood',
  '#2F4A3A': 'Forest',
  '#A87B2C': 'Ochre',
};

// Text field placeholders: secondaryLabel is 4.9 or more on every surface.
const placeholderText = TextStyle(
  fontWeight: FontWeight.w400,
  color: secondaryLabel,
);

// Text fields: paper-toned surface3 with a hairline edge.
const fieldDecoration = BoxDecoration(
  color: surface3,
  border: Border.fromBorderSide(BorderSide(color: separator)),
  borderRadius: BorderRadius.all(Radius.circular(8)),
);
// The thumb of a segmented control: paper on the board-toned track.
const segmentThumb = Color(0xFFFBFAF6);
const segmentTrack = Color(0xFFDADDD5);
// Segment labels at the callout size; the control sets 13 pt and the weight.
const segmentLabel = TextStyle(fontSize: 16);

// Elevation: one shadow per level.
const floatingShadow = [
  BoxShadow(color: Color(0x2E1C2430), blurRadius: 18, offset: Offset(0, 6)),
];
// Under modal routes: ink at a light wash.
const scrim = Color(0x521C2430);
const modalShadow = [
  BoxShadow(color: Color(0x421C2430), blurRadius: 40, offset: Offset(0, 14)),
];

// Type roles: Alegreya Sans, a humanist sans of calligraphic origin, in
// weights 400 and 800 on a 4:3 scale (14 / 18 / 24 / 32), with 16 for
// secondary lines. letterSpacing is 0: Cupertino's defaults carry SF Pro's
// negative tracking.
const _ui = TextStyle(
  inherit: false,
  fontFamily: 'Alegreya Sans',
  letterSpacing: 0,
  color: label,
  textBaseline: TextBaseline.alphabetic,
);
final footnote = _ui.copyWith(fontSize: 14, height: 18 / 14);
final callout = _ui.copyWith(fontSize: 16, height: 21 / 16);
final subhead = callout.copyWith(fontWeight: FontWeight.w800);
final body = _ui.copyWith(fontSize: 18, height: 24 / 18);
final headline = body.copyWith(fontWeight: FontWeight.w800);
final title = _ui.copyWith(
  fontSize: 24,
  height: 30 / 24,
  fontWeight: FontWeight.w800,
);
final largeTitle = _ui.copyWith(
  fontSize: 32,
  height: 38 / 32,
  fontWeight: FontWeight.w800,
);
// Alegreya, the serif partner, for the titles on spine labels and the
// library heading. The bundled face is variable, so the weight is an axis.
const _volume = TextStyle(
  inherit: false,
  fontFamily: 'Alegreya',
  letterSpacing: 0,
  color: label,
  textBaseline: TextBaseline.alphabetic,
);
final spineTitle = _volume.copyWith(
  fontSize: 15,
  height: 19 / 15,
  fontVariations: const [FontVariation('wght', 700)],
);
final volumeTitle = _volume.copyWith(
  fontSize: 32,
  height: 38 / 32,
  fontVariations: const [FontVariation('wght', 800)],
);

final cupertinoTheme = CupertinoThemeData(
  brightness: Brightness.light,
  primaryColor: label,
  primaryContrastingColor: surface2,
  scaffoldBackgroundColor: background,
  barBackgroundColor: surface1,
  textTheme: CupertinoTextThemeData(
    primaryColor: label,
    textStyle: body,
    actionTextStyle: body,
    actionSmallTextStyle: callout,
    tabLabelTextStyle: _ui.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
    navTitleTextStyle: headline,
    navLargeTitleTextStyle: largeTitle,
    navActionTextStyle: body,
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
  // Items within a group have no rules; GroupRule separates the groups.
  dividerTheme: const PullDownMenuDividerTheme(
    dividerColor: Color(0x00000000),
    largeDividerColor: separator,
  ),
  titleTheme: PullDownMenuTitleTheme(
    style: footnote.copyWith(color: secondaryLabel),
  ),
);

// A hairline rule between menu groups, in place of the package's 8 px band
// (PullDownMenuDivider.large, pull_down_button items/divider.dart).
class GroupRule extends StatelessWidget implements PullDownMenuEntry {
  const GroupRule({super.key});

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    color: separator,
  );
}

String hex(int rgb) => '#${rgb.toRadixString(16).padLeft(6, '0')}';
