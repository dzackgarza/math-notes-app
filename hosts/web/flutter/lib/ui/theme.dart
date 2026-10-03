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
class AppPalette {
  const AppPalette({
    required this.background,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.separator,
    required this.label,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.accent,
    required this.onAccent,
    required this.warning,
    required this.selectedFill,
    required this.paperEdge,
    required this.segmentThumb,
    required this.segmentTrack,
    required this.shadow,
    required this.scrim,
  });
  final Color background, surface1, surface2, surface3, separator;
  final Color label, secondaryLabel, tertiaryLabel, accent, onAccent, warning;
  final Color selectedFill, paperEdge, segmentThumb, segmentTrack, shadow, scrim;
}

const _light = AppPalette(
  background: Color(0xFFDADDD5),
  surface1: Color(0xFFDADDD5),
  surface2: Color(0xFFEEF0EA),
  surface3: Color(0xFFFBFAF6),
  separator: Color(0x291C2430),
  label: Color(0xFF1C2430),
  secondaryLabel: Color(0xFF555D67),
  tertiaryLabel: Color(0xFF7D858E),
  accent: Color(0xFF9E2A2B),
  onAccent: Color(0xFFFFFFFF),
  warning: Color(0xFF7A4E00),
  selectedFill: Color(0x1F9E2A2B),
  paperEdge: Color(0xFFC9CDC3),
  segmentThumb: Color(0xFFFBFAF6),
  segmentTrack: Color(0xFFDADDD5),
  shadow: Color(0x2E1C2430),
  scrim: Color(0x521C2430),
);

const _dark = AppPalette(
  background: Color(0xFF26302C),
  surface1: Color(0xFF26302C),
  surface2: Color(0xFF323D38),
  surface3: Color(0xFF3D4842),
  separator: Color(0x55C0C8BD),
  label: Color(0xFFE9E6DA),
  secondaryLabel: Color(0xFFC0C8BD),
  tertiaryLabel: Color(0xFF8E9A90),
  accent: Color(0xFFF1A0A1),
  onAccent: Color(0xFF26302C),
  warning: Color(0xFFF1CB80),
  selectedFill: Color(0x4DF1A0A1),
  paperEdge: Color(0xFF90998D),
  segmentThumb: Color(0xFF3D4842),
  segmentTrack: Color(0xFF26302C),
  shadow: Color(0x99000000),
  scrim: Color(0x99000000),
);

AppPalette _colors = _light;
bool get darkAppearance => identical(_colors, _dark);
void setAppearance(bool dark) => _colors = dark ? _dark : _light;

Color get background => _colors.background;
Color get surface1 => _colors.surface1;
Color get surface2 => _colors.surface2;
Color get surface3 => _colors.surface3;
Color get separator => _colors.separator;
Color get label => _colors.label;
Color get secondaryLabel => _colors.secondaryLabel;
Color get tertiaryLabel => _colors.tertiaryLabel;
Color get accent => _colors.accent;
Color get accentText => _colors.accent;
Color get onAccent => _colors.onAccent;
Color get destructive => _colors.accent;
Color get warning => _colors.warning;
Color get selectedFill => _colors.selectedFill;
const coverInk = Color(0xFF1C2430);
// The default page fill: ink samples sit on it so they read as on the page.
const paper = Color(0xFFFBFAF6);
Color get paperEdge => _colors.paperEdge;
// Buckram for notebook covers, with the title on a paper spine label.
const coverColors = {
  '#24324A': 'Navy',
  '#5B2328': 'Oxblood',
  '#2F4A3A': 'Forest',
  '#A87B2C': 'Ochre',
};

// Text field placeholders: secondaryLabel is 4.9 or more on every surface.
TextStyle get placeholderText => TextStyle(
  fontWeight: FontWeight.w400,
  color: secondaryLabel,
);

// Text fields: paper-toned surface3 with a hairline edge.
BoxDecoration get fieldDecoration => BoxDecoration(
  color: surface3,
  border: Border.fromBorderSide(BorderSide(color: separator)),
  borderRadius: BorderRadius.all(Radius.circular(8)),
);
// The thumb of a segmented control: paper on the board-toned track.
Color get segmentThumb => _colors.segmentThumb;
Color get segmentTrack => _colors.segmentTrack;
// Segment labels at the callout size; the control sets 13 pt and the weight.
const segmentLabel = TextStyle(fontSize: 16);

// Elevation: one shadow per level.
List<BoxShadow> get floatingShadow => [
  BoxShadow(color: _colors.shadow, blurRadius: 18, offset: const Offset(0, 6)),
];
// Under modal routes: ink at a light wash.
Color get scrim => _colors.scrim;
List<BoxShadow> get modalShadow => [
  BoxShadow(color: _colors.shadow, blurRadius: 40, offset: const Offset(0, 14)),
];

// Type roles: Alegreya Sans, a humanist sans of calligraphic origin, in
// weights 400 and 800 on a 4:3 scale (14 / 18 / 24 / 32), with 16 for
// secondary lines. letterSpacing is 0: Cupertino's defaults carry SF Pro's
// negative tracking.
TextStyle get _ui => TextStyle(
  inherit: false,
  fontFamily: 'Alegreya Sans',
  letterSpacing: 0,
  color: label,
  textBaseline: TextBaseline.alphabetic,
);
TextStyle get footnote => _ui.copyWith(fontSize: 14, height: 18 / 14);
TextStyle get callout => _ui.copyWith(fontSize: 16, height: 21 / 16);
TextStyle get subhead => callout.copyWith(fontWeight: FontWeight.w800);
TextStyle get body => _ui.copyWith(fontSize: 18, height: 24 / 18);
TextStyle get headline => body.copyWith(fontWeight: FontWeight.w800);
TextStyle get title => _ui.copyWith(
  fontSize: 24,
  height: 30 / 24,
  fontWeight: FontWeight.w800,
);
TextStyle get largeTitle => _ui.copyWith(
  fontSize: 32,
  height: 38 / 32,
  fontWeight: FontWeight.w800,
);
// Alegreya, the serif partner, for the titles on spine labels and the
// library heading. The bundled face is variable, so the weight is an axis.
TextStyle get _volume => TextStyle(
  inherit: false,
  fontFamily: 'Alegreya',
  letterSpacing: 0,
  color: label,
  textBaseline: TextBaseline.alphabetic,
);
TextStyle get spineTitle => _volume.copyWith(
  fontSize: 15,
  height: 19 / 15,
  fontVariations: const [FontVariation('wght', 700)],
);
TextStyle get volumeTitle => _volume.copyWith(
  fontSize: 32,
  height: 38 / 32,
  fontVariations: const [FontVariation('wght', 800)],
);

CupertinoThemeData get cupertinoTheme => CupertinoThemeData(
  brightness: darkAppearance ? Brightness.dark : Brightness.light,
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

PullDownButtonTheme get pullDownTheme => PullDownButtonTheme(
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
  dividerTheme: PullDownMenuDividerTheme(
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
