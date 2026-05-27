import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Primary Colors
  static const Color royalBlue = Color(0xFF1A4D8F);
  static const Color deepNavy = Color(0xFF0F2E57);

  // Secondary Colors
  static const Color gold = Color(0xFFF1C40F);
  static const Color cleanWhite = Color(0xFFFFFFFF);
  static const Color lightGray = Color(0xFFF4F4F4);

  // Text Colors
  static const Color darkText = Color(0xFF1C1C1C);
  static const Color mutedText = Color(0xFF6D6D6D);

  // Border Colors
  static const Color borderGray = Color(0xFFE0E0E0);

  // Shadow
  static const Color shadowColor = Color(0x1A000000); // rgba black 0.1
  static List<BoxShadow> get elevatedShadow => [
        BoxShadow(
          color: Colors.black.withOpacity(0.1),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ];

  // Get the app theme
  static ThemeData get lightTheme {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.light(
        primary: royalBlue,
        secondary: gold,
        surface: cleanWhite,
        background: lightGray,
        onPrimary: cleanWhite,
        onSecondary: deepNavy,
        onSurface: darkText,
        onBackground: darkText,
      ),
      scaffoldBackgroundColor: lightGray,
      visualDensity: VisualDensity.standard,
      splashFactory: InkRipple.splashFactory,

      // AppBar Theme
      appBarTheme: AppBarTheme(
        backgroundColor: royalBlue,
        foregroundColor: cleanWhite,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: cleanWhite,
        ),
      ),

      // Card Theme
      cardTheme: CardThemeData(
        color: cleanWhite,
        elevation: 2,
        shadowColor: shadowColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      // Button Themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: royalBlue,
          foregroundColor: cleanWhite,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: royalBlue,
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: gold,
          side: const BorderSide(color: gold, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Input Decoration Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cleanWhite,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: borderGray, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: borderGray, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: royalBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.red, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
        labelStyle: TextStyle(
          color: mutedText,
          fontSize: 14,
        ),
        hintStyle: TextStyle(
          color: mutedText,
          fontSize: 14,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),

      // Text Themes
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: darkText,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: darkText,
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: darkText,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: darkText,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: darkText,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: darkText,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: darkText,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: darkText,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.normal,
          color: mutedText,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: darkText,
        ),
      ),

      // Bottom Navigation Bar Theme
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: deepNavy,
        selectedItemColor: gold,
        unselectedItemColor: Colors.white70,
        selectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.normal,
        ),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      // Floating Action Button Theme
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: royalBlue,
        foregroundColor: cleanWhite,
        elevation: 4,
      ),

      // Icon Theme
      iconTheme: const IconThemeData(
        color: royalBlue,
        size: 24,
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.standard,
        ),
      ),

      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),

      // Divider Theme
      dividerTheme: const DividerThemeData(
        color: borderGray,
        thickness: 1,
        space: 1,
      ),

      // Chip Theme
      chipTheme: ChipThemeData(
        backgroundColor: lightGray,
        selectedColor: gold.withOpacity(0.2),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );

    // Noto Sans covers most scripts (court orders, names, etc.) without bundling
    // missing system emoji fonts that trigger console warnings on web.
    return theme.copyWith(
      textTheme: GoogleFonts.notoSansTextTheme(theme.textTheme),
      primaryTextTheme: GoogleFonts.notoSansTextTheme(theme.primaryTextTheme),
      appBarTheme: theme.appBarTheme.copyWith(
        titleTextStyle: GoogleFonts.notoSans(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: cleanWhite,
        ),
      ),
    );
  }

  // Helper methods for common styles
  static TextStyle get heading1 => TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: darkText,
      );

  static TextStyle get bodyMedium => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: darkText,
      );

  static Color get lightBackground => lightGray;

  static TextStyle get cardTitleStyle => TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: royalBlue,
      );

  static TextStyle get cardDetailStyle => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: mutedText,
      );

  static BoxDecoration get cardDecoration => BoxDecoration(
        color: cleanWhite,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      );

  static BoxDecoration get primaryButtonDecoration => BoxDecoration(
        color: royalBlue,
        borderRadius: BorderRadius.circular(12),
      );

  static BoxDecoration get secondaryButtonDecoration => BoxDecoration(
        border: Border.all(color: gold, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      );

  // Additional static getters for compatibility
  static const Color error = Colors.red;
  static const Color textPrimary = darkText;
  static const Color textSecondary = mutedText;
  static const Color navy = deepNavy;
  static const Color success = Colors.green;
  static const Color white = cleanWhite;
  static const Color warning = Colors.orange;

  static TextStyle get heading2 => TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: darkText,
      );

  static TextStyle get heading3 => TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: darkText,
      );

  static TextStyle get heading4 => TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: darkText,
      );

  static TextStyle get bodySmall => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: mutedText,
      );

  static TextStyle get caption => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: mutedText,
      );

  static TextStyle get bodyLarge => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: darkText,
      );

  static TextStyle get buttonText => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: cleanWhite,
      );

  /// Inline text links (Register, View profile) — compact tap area by design.
  static ButtonStyle get compactTextButtonStyle => TextButton.styleFrom(
        foregroundColor: royalBlue,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      );
}

