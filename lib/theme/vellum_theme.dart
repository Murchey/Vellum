import 'package:flutter/cupertino.dart';

/// Quiet paper/ink palette for Vellum.
abstract final class VellumTheme {
  static String fontFamily = 'Georgia';
  static String contentFontFamily = 'Georgia';
  static const paper = Color(0xfff1ece1);
  static const card = Color(0xfffbf8f1);
  static const ink = Color(0xff1c1917);
  static const muted = Color(0xff78716c);
  static const accent = Color(0xffa33d2e);
  static const line = Color(0xffe2dbcd);
  static const darkPaper = Color(0xff111110);
  static const darkCard = Color(0xff1c1917);
  static const darkInk = Color(0xfff0ebe1);
  static const darkMuted = Color(0xffa8a29e);
  static const darkAccent = Color(0xffd97757);
  static const darkLine = Color(0xff3a3530);

  static const light = CupertinoThemeData(
    brightness: Brightness.light,
    primaryColor: accent,
    scaffoldBackgroundColor: paper,
    barBackgroundColor: paper,
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
  // Fanqie reader theme palette (colors.xml reader_*_theme_bg_light).
  // Night = Fanqie theme 5 (#262626 / ink #B7B7B7); Charcoal is a deeper
  // dark variant so readerInkFor can distinguish the two dark papers.
  static const readerNight = Color(0xff262626);
  static const readerNightInk = Color(0xffb7b7b7);
  static const readerMint = Color(0xffc9decb);
  static const readerSepia = Color(0xfff7e4cf);
  static const readerCharcoal = Color(0xff1a1a1a);
  static const readerCharcoalInk = Color(0xff8c8c8c);
  static const readerBlue = Color(0xffc2def0);
  static const readerWhite = Color(0xffd7d7db);

  static Color readerInkFor(Color background) {
    if (background == darkPaper) return CupertinoColors.white;
    if (background == readerNight) return readerNightInk;
    if (background == readerCharcoal) return readerCharcoalInk;
    return CupertinoColors.black;
  }

  static Color mutedOf(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark
      ? darkMuted
      : muted;
  static Color accentOf(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark
      ? darkAccent
      : accent;
  static Color lineOf(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark
      ? darkLine
      : line;
  static Color cardOf(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark
      ? darkCard
      : card;
  /// Reader chrome surface. Prefer the active reading paper so menu bars
  /// sit on the same colour as the page (Fanqie menu uses theme bg).
  /// Falls back to app card/darkPaper when no paper is supplied.
  static Color readerChromeOf(BuildContext context, {Color? paper}) {
    if (paper != null) return paper;
    return CupertinoTheme.of(context).brightness == Brightness.dark
        ? darkPaper
        : card;
  }

  /// Ink for chrome painted on [surface] — always contrast-safe on reader
  /// papers (night/charcoal/sepia/…), independent of app light/dark mode.
  static Color readerChromeInk(Color surface) => readerInkFor(surface);

  static Color softAccentOf(BuildContext context) => accentOf(
    context,
  ).withValues(alpha: .12);
}
