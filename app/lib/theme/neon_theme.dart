import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Neon Night-Market — the chosen visual direction (see design/set-the-night.html).
/// After-dark by nature, but with a full light mode. Accents are a triad: cyan carries,
/// magenta means danger/traitor, acid is the "go" / positive signal.
@immutable
class NeonColors extends ThemeExtension<NeonColors> {
  const NeonColors({
    required this.bg,
    required this.panel,
    required this.plate,
    required this.line,
    required this.ink,
    required this.mid,
    required this.mute,
    required this.cyan,
    required this.magenta,
    required this.acid,
    required this.danger,
    required this.onAccent,
  });

  final Color bg, panel, plate, line, ink, mid, mute;
  final Color cyan, magenta, acid, danger, onAccent;

  static const dark = NeonColors(
    bg: Color(0xFF131120),
    panel: Color(0xFF241F38),
    plate: Color(0xFF1E1A31),
    line: Color(0xFF332C50),
    ink: Color(0xFFF3F0FB),
    mid: Color(0xFFC7BFE3),
    mute: Color(0xFF8F86B6),
    cyan: Color(0xFF3DF6F0),
    magenta: Color(0xFFFF47A8),
    acid: Color(0xFFD3FF5A),
    danger: Color(0xFFFF445F),
    onAccent: Color(0xFF08201D),
  );

  static const light = NeonColors(
    bg: Color(0xFFEFEAF8),
    panel: Color(0xFFFFFFFF),
    plate: Color(0xFFFAF7FF),
    line: Color(0xFFE7E0F4),
    ink: Color(0xFF1B1530),
    mid: Color(0xFF4B4368),
    mute: Color(0xFF8B83A6),
    cyan: Color(0xFF0A9D95),
    magenta: Color(0xFFD21A7A),
    acid: Color(0xFF6D8A00),
    danger: Color(0xFFE01E49),
    onAccent: Color(0xFFFFFFFF),
  );

  @override
  NeonColors copyWith({
    Color? bg, Color? panel, Color? plate, Color? line, Color? ink, Color? mid, Color? mute,
    Color? cyan, Color? magenta, Color? acid, Color? danger, Color? onAccent,
  }) {
    return NeonColors(
      bg: bg ?? this.bg,
      panel: panel ?? this.panel,
      plate: plate ?? this.plate,
      line: line ?? this.line,
      ink: ink ?? this.ink,
      mid: mid ?? this.mid,
      mute: mute ?? this.mute,
      cyan: cyan ?? this.cyan,
      magenta: magenta ?? this.magenta,
      acid: acid ?? this.acid,
      danger: danger ?? this.danger,
      onAccent: onAccent ?? this.onAccent,
    );
  }

  @override
  NeonColors lerp(ThemeExtension<NeonColors>? other, double t) {
    if (other is! NeonColors) return this;
    return NeonColors(
      bg: Color.lerp(bg, other.bg, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      plate: Color.lerp(plate, other.plate, t)!,
      line: Color.lerp(line, other.line, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      mid: Color.lerp(mid, other.mid, t)!,
      mute: Color.lerp(mute, other.mute, t)!,
      cyan: Color.lerp(cyan, other.cyan, t)!,
      magenta: Color.lerp(magenta, other.magenta, t)!,
      acid: Color.lerp(acid, other.acid, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
    );
  }
}

extension NeonContext on BuildContext {
  NeonColors get neon => Theme.of(this).extension<NeonColors>()!;
}

class NeonTheme {
  static ThemeData _base(NeonColors n, Brightness brightness) {
    final display = GoogleFonts.unbounded(); // headline face
    final body = GoogleFonts.archivo();
    final scheme = ColorScheme.fromSeed(
      seedColor: n.cyan,
      brightness: brightness,
    ).copyWith(
      surface: n.bg,
      primary: n.cyan,
      onPrimary: n.onAccent,
      secondary: n.magenta,
      error: n.danger,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: n.bg,
      extensions: [n],
      textTheme: GoogleFonts.archivoTextTheme(
        brightness == Brightness.dark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
      ).apply(bodyColor: n.ink, displayColor: n.ink).copyWith(
            displayLarge: display.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              color: n.ink,
              height: 0.98,
            ),
            headlineSmall: display.copyWith(fontWeight: FontWeight.w900, color: n.ink),
            labelLarge: body.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: n.ink,
            ),
          ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: n.panel,
        contentTextStyle: body.copyWith(color: n.ink),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ThemeData get dark => _base(NeonColors.dark, Brightness.dark);
  static ThemeData get light => _base(NeonColors.light, Brightness.light);
}
