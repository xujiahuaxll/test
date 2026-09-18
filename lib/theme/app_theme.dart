import 'package:flutter/material.dart';

/// 全局配色。整体走「户外 / 地图」的清爽绿，辅以暖橙做强调色。
class AppColors {
  static const Color primary = Color(0xFF1F7A63);
  static const Color primaryDark = Color(0xFF14594A);
  static const Color primarySoft = Color(0xFFE3F1EC);
  static const Color accent = Color(0xFFF2994A);

  static const Color background = Color(0xFFF4F7F6);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF0F4F2);

  static const Color textPrimary = Color(0xFF16211E);
  static const Color textSecondary = Color(0xFF6B7C77);
  static const Color textTertiary = Color(0xFF9AA8A3);
  static const Color divider = Color(0xFFE6ECEA);
  static const Color danger = Color(0xFFE05B5B);

  /// 标签配色（名称 -> 颜色），列表与详情共用，保证同一标签颜色一致。
  static const Map<String, Color> tagColors = <String, Color>{
    '美食': Color(0xFFE2703A),
    '风景': Color(0xFF2F9E7E),
    '咖啡': Color(0xFF8D6E63),
    '打卡': Color(0xFF7E57C2),
    '露营': Color(0xFF3B8ED0),
    '拍照': Color(0xFFD8567A),
    '工作': Color(0xFF546E7A),
    '待办': Color(0xFFC9A227),
  };

  static Color tagColor(String tag) => tagColors[tag] ?? primary;
}

/// 通用圆角 / 间距常量，避免各页面写死数字。
class AppRadius {
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 22;
  static const double pill = 999;
}

class AppTheme {
  static ThemeData light() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'PingFang SC',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          height: 1.2,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: AppColors.textPrimary,
          height: 1.5,
        ),
        bodySmall: TextStyle(
          fontSize: 12.5,
          color: AppColors.textSecondary,
          height: 1.45,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.background,
        hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
  }
}

/// 卡片统一阴影
const List<BoxShadow> kCardShadow = <BoxShadow>[
  BoxShadow(
    color: Color(0x0F1B3A33),
    blurRadius: 18,
    offset: Offset(0, 6),
  ),
];
