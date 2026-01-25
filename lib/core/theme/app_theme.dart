import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // WeVote Inspired Color Palette (Premium Indigo-Blue)
  static const Color primaryIndigo = Color(0xFF4F46E5); // WeVote Main Indigo
  static const Color secondaryIndigo = Color(0xFF818CF8); 
  static const Color surfaceIndigo = Color(0xFFF5F3FF); // Light Indigo Surface
  
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  // Design Tokens
  static const Color background = Color(0xFFF9FAFB);
  static const Color surface = Colors.white;
  static const Color textMain = Color(0xFF1F2937); // Darker Gray 800
  static const Color textSub = Color(0xFF6B7280); // Gray 500
  static const Color textLight = Color(0xFF9CA3AF); // Gray 400
  static const Color divider = Color(0xFFF3F4F6); // Gray 100
  
  // Status Colors
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryIndigo,
        primary: primaryIndigo,
        secondary: secondaryIndigo,
        surface: surface,
        background: background,
        error: error,
      ),
      textTheme: GoogleFonts.notoSansKrTextTheme().copyWith(
        displayLarge: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold, color: textMain, letterSpacing: -1.0),
        titleLarge: GoogleFonts.notoSansKr(fontSize: 22, fontWeight: FontWeight.w800, color: textMain, letterSpacing: -0.5),
        bodyLarge: GoogleFonts.notoSansKr(fontSize: 16, color: textMain, height: 1.6),
        bodyMedium: GoogleFonts.notoSansKr(fontSize: 14, color: textSub, height: 1.5),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: textMain,
          fontSize: 22,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.8,
        ),
        iconTheme: IconThemeData(color: textMain, size: 24),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Colors.transparent),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryIndigo,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: divider, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: divider, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: primaryIndigo, width: 2),
        ),
        hintStyle: TextStyle(color: textLight, fontSize: 14),
      ),
    );
  }
}
