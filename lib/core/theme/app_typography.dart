import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

TextStyle _display(double size, FontWeight w, Color c) => GoogleFonts.spaceGrotesk(
      fontSize: size,
      fontWeight: w,
      color: c,
      height: 1.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

TextStyle moneyStyle(Color color, {double size = 15}) => GoogleFonts.spaceGrotesk(
      fontSize: size,
      fontWeight: FontWeight.w600,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

TextTheme buildTextTheme(Color primary) {
  final body = GoogleFonts.onestTextTheme();
  return body.copyWith(
    displayLarge: _display(44, FontWeight.w500, primary),
    headlineSmall: _display(22, FontWeight.w600, primary),
    titleLarge: _display(20, FontWeight.w600, primary),
    bodyLarge: GoogleFonts.onest(fontSize: 15, color: primary, height: 1.5),
    bodyMedium: GoogleFonts.onest(fontSize: 14, color: primary, height: 1.5),
    labelLarge: GoogleFonts.onest(fontSize: 13, fontWeight: FontWeight.w500, color: primary),
    labelSmall: GoogleFonts.onest(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.1, color: primary),
  );
}
