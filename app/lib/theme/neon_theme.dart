import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The "Arcade Cabinet" / "Comic Pop" outline ink — always this fixed
/// wine-black, in either theme. The whole effect is a dark line-art ring
/// around a shape, the way a real cabinet button's edge (or a comic panel's
/// outline) reads regardless of the color behind it. Using the theme's `ink`
/// token (which flips to near-white in dark mode) would wash the ring out.
/// This is what keeps the *shape* language playful — thick outline plus the
/// hard offset shadow in [NeonShadow] — independent of the palette.
const Color kCabinetInk = Color(0xFF1E1012);

/// Palm Wine — deep maroon brand on a wine-black ground, with gold as the
/// carrying secondary. Chosen over four other colorways (see the "PlayHuud
/// Colorways" board) because nothing else in social or gaming owns maroon.
///
/// Two rules this palette exists to enforce:
///
/// 1. **No purple, ever.** Not in the neutrals, not in an accent. The
///    violet/indigo greys every other dark app defaults to are exactly what
///    this replaced; the neutrals here are wine-tinted, and the game boards
///    they frame have always been wood and amber
///    (`draughts_theme.dart`, `goosi_theme.dart`).
/// 2. **The palette changed, the shape language did not.** Buttons, badges
///    and the nav pill keep the playful sticker treatment — thick
///    [kCabinetInk] outline, hard offset shadow, stadium corners. Maroon is
///    the paint, not a reason to go flat and corporate.
///
/// Roles: [brand] is the primary (every main call to action), [gold] carries
/// secondary structure and labels, [jade] is the "go" / success signal, and
/// [danger] stays a distinctly hotter orange-red so an error never reads as
/// just more brand.
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
    required this.gold,
    required this.brand,
    required this.jade,
    required this.danger,
    required this.onAccent,
  });

  final Color bg, panel, plate, line, ink, mid, mute;
  final Color gold, brand, jade, danger, onAccent;

  /// Wine-black ground — near-black carrying a red bias, so maroon sits on
  /// it as depth rather than as a stain, and gold reads as lit metal.
  static const dark = NeonColors(
    bg: Color(0xFF16100F),
    panel: Color(0xFF241517),
    plate: Color(0xFF1D1213),
    line: Color(0xFF3A2429),
    ink: Color(0xFFF6EAE3),
    mid: Color(0xFFD6BFB6),
    mute: Color(0xFF9C8078),
    gold: Color(0xFFD9A441),
    brand: Color(0xFFC02B52),
    jade: Color(0xFF7FCFA0),
    danger: Color(0xFFFF6B4A),
    onAccent: Color(0xFF1B0E10),
  );

  /// Blush paper — the daylight counterpart. Accents darken (a #C02B52 that
  /// carries on wine-black is too light to put cream text on at 4.5:1 over
  /// white), so each one has a deeper daylight twin rather than the same hex
  /// reused across both themes.
  static const light = NeonColors(
    bg: Color(0xFFFBF4F0),
    panel: Color(0xFFFFFFFF),
    plate: Color(0xFFFFF9F6),
    line: Color(0xFFEEDFD9),
    ink: Color(0xFF2A1418),
    mid: Color(0xFF5C4048),
    mute: Color(0xFF93756F),
    gold: Color(0xFF9A6B14),
    brand: Color(0xFF8E1F3D),
    jade: Color(0xFF2E8F63),
    danger: Color(0xFFCF4426),
    onAccent: Color(0xFFFFFFFF),
  );

  /// Optional Nebula palette: midnight blue, violet surfaces, rose actions,
  /// and warm peach highlights inspired by sci-fi game interfaces.
  static const nebulaDark = NeonColors(
    bg: Color(0xFF090B1B),
    panel: Color(0xFF1B1740),
    plate: Color(0xFF11132F),
    line: Color(0xFF514679),
    ink: Color(0xFFFFF2F1),
    mid: Color(0xFFE0CADA),
    mute: Color(0xFFAA9EBF),
    gold: Color(0xFFFFC98F),
    brand: Color(0xFFC33671),
    jade: Color(0xFF83E4D8),
    danger: Color(0xFFFF735E),
    onAccent: Color(0xFF1A1026),
  );

  static const nebulaLight = NeonColors(
    bg: Color(0xFFFFF2EC),
    panel: Color(0xFFFFFFFF),
    plate: Color(0xFFF7EAF6),
    line: Color(0xFFD9C7DF),
    ink: Color(0xFF251535),
    mid: Color(0xFF614E69),
    mute: Color(0xFF806F88),
    gold: Color(0xFF83521B),
    brand: Color(0xFFAA245A),
    jade: Color(0xFF167C72),
    danger: Color(0xFFC43832),
    onAccent: Color(0xFFFFFFFF),
  );

  /// Supercar: racing blue panels, cyan instruments, and red warning lights.
  /// Inspired by the futuristic dashboard in the Supercar Battle concept.
  static const supercarDark = NeonColors(
    bg: Color(0xFF040411),
    panel: Color(0xFF10183A),
    plate: Color(0xFF0B1130),
    line: Color(0xFF344581),
    ink: Color(0xFFF4F7FF),
    mid: Color(0xFFCBD6F3),
    mute: Color(0xFFAAB8DF),
    gold: Color(0xFF27D5F2),
    brand: Color(0xFF2847AD),
    jade: Color(0xFF4CE3BD),
    danger: Color(0xFFF04B55),
    onAccent: Color(0xFF061328),
  );

  static const supercarLight = NeonColors(
    bg: Color(0xFFF0F5FF),
    panel: Color(0xFFFFFFFF),
    plate: Color(0xFFE6EEFF),
    line: Color(0xFFC3D1EB),
    ink: Color(0xFF0B1735),
    mid: Color(0xFF405475),
    mute: Color(0xFF5E7294),
    gold: Color(0xFF086B8D),
    brand: Color(0xFF243E9A),
    jade: Color(0xFF087D69),
    danger: Color(0xFFBF2739),
    onAccent: Color(0xFFFFFFFF),
  );

  @override
  NeonColors copyWith({
    Color? bg,
    Color? panel,
    Color? plate,
    Color? line,
    Color? ink,
    Color? mid,
    Color? mute,
    Color? gold,
    Color? brand,
    Color? jade,
    Color? danger,
    Color? onAccent,
  }) {
    return NeonColors(
      bg: bg ?? this.bg,
      panel: panel ?? this.panel,
      plate: plate ?? this.plate,
      line: line ?? this.line,
      ink: ink ?? this.ink,
      mid: mid ?? this.mid,
      mute: mute ?? this.mute,
      gold: gold ?? this.gold,
      brand: brand ?? this.brand,
      jade: jade ?? this.jade,
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
      gold: Color.lerp(gold, other.gold, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      jade: Color.lerp(jade, other.jade, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
    );
  }
}

extension NeonContext on BuildContext {
  NeonColors get neon => Theme.of(this).extension<NeonColors>()!;
  NeonDesign get neonDesign => Theme.of(this).extension<NeonDesign>()!;
}

enum NeonDesignKind { cabinet, nebula, supercar }

@immutable
class NeonDesign extends ThemeExtension<NeonDesign> {
  const NeonDesign(this.kind);

  final NeonDesignKind kind;

  @override
  NeonDesign copyWith({NeonDesignKind? kind}) => NeonDesign(kind ?? this.kind);

  @override
  NeonDesign lerp(ThemeExtension<NeonDesign>? other, double t) =>
      t < 0.5 || other is! NeonDesign ? this : other;
}

/// Shared corner radii — chunkier and rounder than a "sleek" app, short of
/// pill-everything cartoonishness. Buttons and chips go all the way to a
/// stadium shape; cards use an uneven "blob" corner set instead of a plain
/// rectangle, so nothing on screen reads as a stiff, straight-edged box.
class NeonRadius {
  static const card = 22.0;
  static const control = 16.0;
  static const chip = 14.0;
  static const pill = 999.0;

  /// A friendly, asymmetric card shape — bigger round on two opposite
  /// corners, tighter on the other two. Mirrored for alternating cards so a
  /// list of them doesn't all lean the same way.
  static BorderRadius blob({bool mirror = false}) => mirror
      ? const BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(28),
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(14),
        )
      : const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(14),
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(28),
        );
}

class NeonTheme {
  static ThemeData _base(NeonColors n, Brightness brightness,
      {NeonDesignKind design = NeonDesignKind.cabinet}) {
    final futuristic = design != NeonDesignKind.cabinet;
    // Baloo 2 — rounded, chunky, playful without tipping into a kids'-app
    // look; paired with Archivo's clean, upright body so long text stays
    // easy to read rather than "fuzzy" all the way down.
    final display = futuristic ? GoogleFonts.archivo() : GoogleFonts.baloo2();
    final body = GoogleFonts.archivo();
    final scheme = ColorScheme.fromSeed(
      seedColor: n.gold,
      brightness: brightness,
    ).copyWith(
      surface: n.bg,
      primary: n.gold,
      onPrimary: n.onAccent,
      secondary: n.brand,
      error: n.danger,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: futuristic ? Colors.transparent : n.bg,
      extensions: [n, NeonDesign(design)],
      appBarTheme: futuristic
          ? AppBarTheme(
              backgroundColor: Colors.transparent,
              foregroundColor: n.ink,
              surfaceTintColor: Colors.transparent,
              titleTextStyle: display.copyWith(
                  color: n.ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8),
            )
          : null,
      // Every pushed screen fades and drifts up instead of sliding in from
      // the edge. The platform slide is what made navigation feel rigid and
      // "app-like"; a fade-through reads lighter and keeps attention in the
      // middle of the screen rather than throwing it sideways.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.iOS: _FadeThroughTransitions(),
        TargetPlatform.android: _FadeThroughTransitions(),
        TargetPlatform.macOS: _FadeThroughTransitions(),
      }),
      // Sheets float over a softly dimmed, blurred page rather than a hard
      // black scrim (see `showNeonSheet`).
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalBarrierColor: kScrim,
      ),
      // Dialogs sit on the same frosted surface as the cards rather than a
      // solid slab.
      dialogTheme: DialogThemeData(
        backgroundColor: n.panel.withValues(alpha: 0.88),
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: GoogleFonts.archivoTextTheme(
        brightness == Brightness.dark
            ? ThemeData.dark().textTheme
            : ThemeData.light().textTheme,
      ).apply(bodyColor: n.ink, displayColor: n.ink).copyWith(
            displayLarge: display.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: futuristic ? 0.8 : 0.2,
              color: n.ink,
              height: 1.0,
            ),
            headlineSmall:
                display.copyWith(fontWeight: FontWeight.w800, color: n.ink),
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
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: n.plate,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: body.copyWith(color: n.mute),
        labelStyle: body.copyWith(color: n.mute),
        prefixIconColor: n.mute,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
              design == NeonDesignKind.supercar ? 8 : NeonRadius.control),
          borderSide: BorderSide(
              color: futuristic ? n.line : kCabinetInk,
              width: futuristic ? 1.2 : 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
              design == NeonDesignKind.supercar ? 8 : NeonRadius.control),
          borderSide: BorderSide(
              color: futuristic ? n.line : kCabinetInk,
              width: futuristic ? 1.2 : 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
              design == NeonDesignKind.supercar ? 8 : NeonRadius.control),
          borderSide: BorderSide(color: n.gold, width: 2.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
              design == NeonDesignKind.supercar ? 8 : NeonRadius.control),
          borderSide: BorderSide(color: n.danger, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
              design == NeonDesignKind.supercar ? 8 : NeonRadius.control),
          borderSide: BorderSide(color: n.danger, width: 2.5),
        ),
      ),
    );
  }

  // Keep the ThemeData identity stable across unrelated AppState updates.
  // Replacing it while a route is being built can restart MaterialApp's
  // implicit theme animation and make translucent surfaces flash.
  static final ThemeData dark = _base(NeonColors.dark, Brightness.dark);
  static final ThemeData light = _base(NeonColors.light, Brightness.light);
  static final ThemeData nebulaDark = _base(
      NeonColors.nebulaDark, Brightness.dark,
      design: NeonDesignKind.nebula);
  static final ThemeData nebulaLight = _base(
      NeonColors.nebulaLight, Brightness.light,
      design: NeonDesignKind.nebula);
  static final ThemeData supercarDark = _base(
      NeonColors.supercarDark, Brightness.dark,
      design: NeonDesignKind.supercar);
  static final ThemeData supercarLight = _base(
      NeonColors.supercarLight, Brightness.light,
      design: NeonDesignKind.supercar);

  static LinearGradient backdrop(NeonDesignKind design, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomRight,
      colors: design == NeonDesignKind.supercar
          ? (dark
              ? const [Color(0xFF040411), Color(0xFF111B49), Color(0xFF071D37)]
              : const [Color(0xFFF6FAFF), Color(0xFFE7EEFF), Color(0xFFD9F2FA)])
          : (dark
              ? const [Color(0xFF080C1E), Color(0xFF201342), Color(0xFF3B174A)]
              : const [
                  Color(0xFFFFF5EE),
                  Color(0xFFFCE5E5),
                  Color(0xFFEBDCF5)
                ]),
    );
  }
}

/// The dim behind any modal surface. Deliberately light (and warm, so it
/// tints toward the wine ground rather than muddying it) — the page behind
/// should stay legible, which is what makes an overlay feel like a layer
/// floating above the app instead of a door slamming over it.
const Color kScrim = Color(0x59120C0D);

/// How long a surface takes to arrive. Long enough to read as a movement
/// rather than a cut — short enough that it never delays you.
class NeonMotion {
  /// Page pushes and pops.
  static const page = Duration(milliseconds: 460);

  /// Sheets, banners, overlays.
  static const overlay = Duration(milliseconds: 380);

  /// The standard easing for arriving content: decelerates into place.
  static const enter = Curves.easeOutCubic;

  /// Leaving is quicker than arriving — nobody wants to wait on a dismissal.
  static const exit = Curves.easeInCubic;
}

/// Fade + a small upward drift, with the outgoing page fading and easing
/// back slightly — a "fade through" rather than a platform slide.
class _FadeThroughTransitions extends PageTransitionsBuilder {
  const _FadeThroughTransitions();

  @override
  Duration get transitionDuration => NeonMotion.page;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final design = context.neonDesign.kind;
    if (design != NeonDesignKind.cabinet) {
      // These screens have translucent Scaffolds. Fading two routed screens
      // through each other exposes the old content while the new one renders.
      // Give every route the same fully opaque backdrop and switch it in one
      // frame; the gradient itself remains fixed across navigation.
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: NeonTheme.backdrop(design, Theme.of(context).brightness),
        ),
        child: child,
      );
    }
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;

    final incoming = CurvedAnimation(
      parent: animation,
      curve: NeonMotion.enter,
      reverseCurve: NeonMotion.exit,
    );
    // The page being covered doesn't slide away — it dissolves and settles
    // back a touch, so the new screen reads as arriving *on top*.
    final outgoing =
        CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOut);

    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0).animate(outgoing),
      child: ScaleTransition(
        scale: Tween<double>(begin: 1, end: 0.97).animate(outgoing),
        child: FadeTransition(
          opacity: incoming,
          child: SlideTransition(
            position:
                Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero)
                    .animate(incoming),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.98, end: 1).animate(incoming),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
