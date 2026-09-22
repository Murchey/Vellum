import 'package:flutter/cupertino.dart';

/// Quiet paper/ink palette for Vellum.
///
/// App shell stays warm paper; reader papers/brand follow Fanqie
/// `colors.xml` (`reader_*_theme_bg_light`, `skin_color_orange_brand_*`).
abstract final class VellumTheme {
  static String fontFamily = 'Georgia';
  static String contentFontFamily = 'Georgia';

  // Fanqie brand orange — reader chrome / current chapter / seek only.
  static const readerAccent = Color(0xfffa6725);
  static const readerAccentDark = Color(0xffffa177);

  // App shell accent (nav bars, library actions) — Vellum quiet wine.
  // Kept separate so Fanqie orange does not repaint the whole app nav.
  static const accent = Color(0xffa33d2e);
  static const darkAccent = Color(0xffd97757);

  // App shell (library / settings).
  static const paper = Color(0xfff7e4cf);
  static const card = Color(0xfffff8ef);
  static const ink = Color(0xff2a211b);
  static const muted = Color(0xff7a6558);
  static const line = Color(0xffe5cdb7);
  static const darkPaper = Color(0xff111110);
  static const darkCard = Color(0xff1c1917);
  static const darkInk = Color(0xfff0ebe1);
  static const darkMuted = Color(0xffa8a29e);
  static const darkLine = Color(0xff3a3530);

  // Fanqie reader themes.
  static const readerWhite = Color(0xffd7d7db);
  static const readerSepia = Color(0xfff7e4cf);
  static const readerMint = Color(0xffc9decb);
  static const readerBlue = Color(0xffc2def0);
  static const readerNight = Color(0xff262626);
  static const readerNightInk = Color(0xffb7b7b7);
  static const readerCharcoal = Color(0xff1a1a1a);
  static const readerCharcoalInk = Color(0xff8c8c8c);

  /// Fanqie body ink on light papers is pure black.
  static const readerBodyInk = Color(0xff000000);
  static const readerHairline = Color(0x14000000);

  static const light = CupertinoThemeData(
    brightness: Brightness.light,
    primaryColor: accent,
    scaffoldBackgroundColor: paper,
    barBackgroundColor: paper,
    applyThemeToAll: true,
    textTheme: CupertinoTextThemeData(
      textStyle: TextStyle(inherit: false, color: ink, fontFamily: 'Georgia'),
      navTitleTextStyle: TextStyle(
        inherit: false,
        color: ink,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        fontFamily: 'Georgia',
      ),
      navLargeTitleTextStyle: TextStyle(
        inherit: false,
        color: ink,
        fontSize: 34,
        fontWeight: FontWeight.w700,
        fontFamily: 'Georgia',
      ),
    ),
  );

  static const dark = CupertinoThemeData(
    brightness: Brightness.dark,
    primaryColor: darkAccent,
    scaffoldBackgroundColor: darkPaper,
    barBackgroundColor: darkPaper,
    applyThemeToAll: true,
    textTheme: CupertinoTextThemeData(
      textStyle: TextStyle(
        inherit: false,
        color: darkInk,
        fontFamily: 'Georgia',
      ),
      navTitleTextStyle: TextStyle(
        inherit: false,
        color: darkInk,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        fontFamily: 'Georgia',
      ),
      navLargeTitleTextStyle: TextStyle(
        inherit: false,
        color: darkInk,
        fontSize: 34,
        fontWeight: FontWeight.w700,
        fontFamily: 'Georgia',
      ),
    ),
  );

  static CupertinoThemeData forBrightness(
    Brightness brightness, {
    String fontFamily = 'Georgia',
  }) {
    final base = brightness == Brightness.dark ? dark : light;
    return base.copyWith(
      textTheme: CupertinoTextThemeData(
        textStyle: base.textTheme.textStyle.copyWith(fontFamily: fontFamily),
        navTitleTextStyle: base.textTheme.navTitleTextStyle.copyWith(
          fontFamily: fontFamily,
        ),
        navLargeTitleTextStyle: base.textTheme.navLargeTitleTextStyle.copyWith(
          fontFamily: fontFamily,
        ),
      ),
    );
  }

  static Color inkOf(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark ? darkInk : ink;

  /// Fanqie body ink on a reader paper (pure black on light, #B7B7B7 night).
  static Color readerInkFor(Color background) {
    if (background == darkPaper) return CupertinoColors.white;
    if (background == readerNight) return readerNightInk;
    if (background == readerCharcoal) return readerCharcoalInk;
    return readerBodyInk;
  }

  /// Secondary text on a reader paper (Fanqie `#66000000` body).
  static Color readerMutedInk(Color surface) {
    final ink = readerInkFor(surface);
    final night = surface == readerNight || surface == readerCharcoal;
    return ink.withValues(alpha: night ? .55 : .4);
  }

  /// App-shell surface (nav bar / scaffold) — always matches the page paper.
  static Color shellOf(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark
      ? darkPaper
      : paper;

  static Color mutedOf(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark
      ? darkMuted
      : muted;
  static Color accentOf(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark
      ? darkAccent
      : accent;

  /// Fanqie brand orange for reader UI (independent of app shell accent).
  static Color readerAccentOf(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark
      ? readerAccentDark
      : readerAccent;
  static Color lineOf(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark
      ? darkLine
      : line;
  static Color cardOf(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark
      ? darkCard
      : card;

  /// Reader chrome surface. Prefer the active reading paper (Fanqie menu
  /// sits on theme bg). Defaults to Fanqie white paper in light mode.
  static Color readerChromeOf(BuildContext context, {Color? paper}) {
    if (paper != null) return paper;
    return CupertinoTheme.of(context).brightness == Brightness.dark
        ? darkPaper
        : readerWhite;
  }

  static Color readerChromeInk(Color surface) => readerInkFor(surface);

  static Color softAccentOf(BuildContext context) =>
      accentOf(context).withValues(alpha: .12);
}
