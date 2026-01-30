import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class AppTheme {
  // Grace Note 핵심 컬러 (shadcn/ui 컨셉 지원)
  static const Color primaryViolet = Color(0xFF8B5CF6);
  static const Color accentViolet = Color(0xFFF3F0FF);
  static const Color background = Color(0xFFFFFFFF);
  static const Color secondaryBackground = Color(0xFFF8FAFC);
  static const Color border = Color(0xFFF1F5F9); // v0 very light border
  static const Color borderMedium = Color(0xFFE2E8F0); // For cards
  
  static const Color textMain = Color(0xFF1A1A1A);
  static const Color textSub = Color(0xFF64748B);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  
  static const Color divider = border;
  static const Color textLight = textSub;
  static const Color primaryIndigo = primaryViolet;

  // [NEW] shadcn_ui 전역 테마 설정
  static ShadThemeData get graceNoteTheme {
    return ShadThemeData(
      brightness: Brightness.light,
      colorScheme: ShadColorScheme(
        background: background,
        foreground: textMain,
        card: background,
        cardForeground: textMain,
        popover: background,
        popoverForeground: textMain,
        primary: primaryViolet,
        primaryForeground: Colors.white,
        secondary: secondaryBackground,
        secondaryForeground: textMain,
        muted: const Color(0xFFF1F5F9),
        mutedForeground: textSub,
        accent: accentViolet,
        accentForeground: primaryViolet,
        destructive: error,
        destructiveForeground: Colors.white,
        border: border,
        input: border,
        ring: primaryViolet,
        selection: primaryViolet.withOpacity(.3),
      ),
      // 폰트 설정: Pretendard 적용 (실패 대비)
      textTheme: ShadTextTheme(
        family: 'Pretendard',
      ),
      // 모든 컴포넌트 곡률 12px 통일
      radius: BorderRadius.circular(12),
    );
  }

  // 기존 Material ThemeData (호환성을 위해 유지하되 스타일 업데이트)
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      primaryColor: primaryViolet,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryViolet,
        primary: primaryViolet,
        surface: background,
        onSurface: textMain,
        error: error,
      ),
      // Material 텍스트 테마 초정밀 교정 (Pretendard 로컬 폰트 강제)
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontWeight: FontWeight.bold, color: textMain, letterSpacing: -0.5, fontFamily: 'Pretendard'),
        titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textMain, letterSpacing: -0.5, fontFamily: 'Pretendard'),
        bodyLarge: TextStyle(fontSize: 14, color: textMain, height: 1.5, letterSpacing: -0.5, fontFamily: 'Pretendard'), // 이름 등
        bodyMedium: TextStyle(fontSize: 13, color: textSub, height: 1.4, letterSpacing: -0.5, fontFamily: 'Pretendard'), // 보조텍스트
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        toolbarHeight: 52,
        titleTextStyle: TextStyle(
          color: textMain,
          fontSize: 16, // v0 정밀 축소
          fontWeight: FontWeight.w700, // Bold(700)
          fontFamily: 'Pretendard',
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: textMain, size: 22),
      ),
      cardTheme: CardThemeData(
        color: background,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: borderMedium, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryViolet,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2, fontFamily: 'Pretendard'),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: secondaryBackground,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryViolet, width: 2),
        ),
        hintStyle: const TextStyle(color: textSub, fontSize: 14, fontFamily: 'Pretendard'),
      ),
    );
  }
}
