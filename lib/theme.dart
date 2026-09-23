import 'package:flutter/material.dart';

import 'domain/models.dart';

/// The prototype's colour tokens, available as `context.palette`.
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.paper,
    required this.card,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.rule,
    required this.tag,
    required this.tagEdge,
    required this.focus,
    required this.status,
    required this.statusBg,
  });

  final Color paper, card, ink, ink2, ink3, rule, tag, tagEdge, focus;
  final Map<WarrantyState, Color> status;
  final Map<WarrantyState, Color> statusBg;

  static const light = Palette(
    paper: Color(0xFFE9EDF2),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF18243F),
    ink2: Color(0xFF4E5B75),
    ink3: Color(0xFF8590A6),
    rule: Color(0xFFCDD4DF),
    tag: Color(0xFFF7F4EC),
    tagEdge: Color(0xFFD9D2BF),
    focus: Color(0xFF2F5BEA),
    status: {
      WarrantyState.verified: Color(0xFF1E8A4C),
      WarrantyState.documented: Color(0xFF2F5BEA),
      WarrantyState.estimated: Color(0xFFB7791F),
      WarrantyState.unknown: Color(0xFF8590A6),
      WarrantyState.expired: Color(0xFFC0392B),
    },
    statusBg: {
      WarrantyState.verified: Color(0xFFE3F3E9),
      WarrantyState.documented: Color(0xFFE6ECFD),
      WarrantyState.estimated: Color(0xFFFBF0DC),
      WarrantyState.unknown: Color(0xFFEDEFF3),
      WarrantyState.expired: Color(0xFFFAE5E2),
    },
  );

  static const dark = Palette(
    paper: Color(0xFF0F1522),
    card: Color(0xFF182033),
    ink: Color(0xFFE7ECF5),
    ink2: Color(0xFFA9B3C8),
    ink3: Color(0xFF6E7890),
    rule: Color(0xFF2A3550),
    tag: Color(0xFF222B3F),
    tagEdge: Color(0xFF39445E),
    focus: Color(0xFF7E9BFF),
    status: {
      WarrantyState.verified: Color(0xFF4CC57F),
      WarrantyState.documented: Color(0xFF7E9BFF),
      WarrantyState.estimated: Color(0xFFE0A94A),
      WarrantyState.unknown: Color(0xFF8B95AB),
      WarrantyState.expired: Color(0xFFEE6B5C),
    },
    statusBg: {
      WarrantyState.verified: Color(0xFF173524),
      WarrantyState.documented: Color(0xFF1C2A55),
      WarrantyState.estimated: Color(0xFF3A2C12),
      WarrantyState.unknown: Color(0xFF232B3D),
      WarrantyState.expired: Color(0xFF43201C),
    },
  );

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(Palette? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

extension PaletteX on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>()!;
}

const gutter = 18.0;

ThemeData buildTheme(Brightness b) {
  final p = b == Brightness.dark ? Palette.dark : Palette.light;
  final base = ThemeData(
    brightness: b,
    useMaterial3: true,
    fontFamily: 'Archivo',
    scaffoldBackgroundColor: p.paper,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.focus,
      brightness: b,
      primary: p.ink,
      onPrimary: p.paper,
      surface: p.paper,
      onSurface: p.ink,
    ),
    extensions: [p],
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: p.paper,
      foregroundColor: p.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'Archivo',
        fontWeight: FontWeight.w700,
        fontSize: 17,
        color: p.ink,
      ),
    ),
    textTheme: base.textTheme.apply(bodyColor: p.ink, displayColor: p.ink),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.card,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: TextStyle(color: p.ink3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: p.rule),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: p.rule),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: p.focus, width: 1.5),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink,
      contentTextStyle: TextStyle(
        fontFamily: 'Archivo',
        color: p.paper,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}
