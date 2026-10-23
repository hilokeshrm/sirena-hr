import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sirena palette: primary red, black, white and one grey.
/// Veg / non-veg marks keep their standard colours.
class C {
  static const red = Color(0xFFA32330);
  static const ink = Color(0xFF2A2A2A);
  static const grey = Color(0xFFEDEDED);
  static const white = Colors.white;
  static const veg = Color(0xFF1A8F3C);
  static const nonVeg = Color(0xFF8B4513);
}

TextStyle display(double size, {Color color = C.ink}) =>
    GoogleFonts.bricolageGrotesque(fontSize: size, fontWeight: FontWeight.w800, color: color, height: 1.1);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: C.red,
      primary: C.red,
      onPrimary: Colors.white,
      secondary: C.ink,
      onSecondary: Colors.white,
      surface: Colors.white,
      onSurface: C.ink,
    ),
    scaffoldBackgroundColor: Colors.white,
  );
  final text = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(bodyColor: C.ink, displayColor: C.ink);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: C.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: display(22),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.red,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 50),
        shape: shape,
        textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.ink,
        minimumSize: const Size(64, 50),
        shape: shape,
        side: const BorderSide(color: C.grey, width: 1.5),
        textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: C.red, textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: C.grey,
      elevation: 0,
      labelTextStyle: WidgetStatePropertyAll(GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700)),
    ),
    dividerTheme: const DividerThemeData(color: C.grey, thickness: 1, space: 1),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.white,
      selectedColor: C.ink,
      side: const BorderSide(color: C.grey),
      labelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: C.ink),
      secondaryLabelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: Colors.white),
      shape: const StadiumBorder(),
    ),
  );
}

/// Shared input look: grey fill, no border until focused.
InputDecoration inputDeco(String label, {String? hint, Widget? suffix}) => InputDecoration(
      labelText: label,
      hintText: hint,
      suffixIcon: suffix,
      filled: true,
      fillColor: C.grey,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.ink, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
