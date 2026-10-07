import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 单一调色板（暗 / 亮各一份）
class _Palette {
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color pillSelected;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final Color divider;
  final Color inputBg;
  const _Palette({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.pillSelected,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.divider,
    required this.inputBg,
  });
}

const _Palette _darkPalette = _Palette(
  background: Color(0xFF0E0E12), // 整体近黑背景
  surface: Color(0xFF1A1A20), // 卡片/面板
  surfaceVariant: Color(0xFF202028), // 次级面板
  pillSelected: Color(0xFFFFFFFF), // 选中胶囊：白底
  textPrimary: Color(0xFFE8E8EA),
  textSecondary: Color(0xFF8A8A92),
  accent: Color(0xFF8A8A92), // 强调色（可由「无极轮盘」自定义覆盖）
  divider: Color(0xFF2A2A32),
  inputBg: Color(0xFF16161C),
);

const _Palette _lightPalette = _Palette(
  background: Color(0xFFF7F8FA),
  surface: Color(0xFFFFFFFF),
  surfaceVariant: Color(0xFFEFF1F4),
  pillSelected: Color(0xFFFCEFD6), // 浅色下用淡金底承托金色文字
  textPrimary: Color(0xFF1F2329),
  textSecondary: Color(0xFF6B7280),
  accent: Color(0xFF6B7280),
  divider: Color(0xFFE6E8EB),
  inputBg: Color(0xFFF2F3F5),
);

/// Olivia-安可 4.0 主题色（Beta2 支持暗/亮/跟随系统）
/// 通过 [ThemeModeController] 切换当前调色板；所有 widget 直接引用
/// [AppColors.xxx] 即可自动换肤，无需逐个改造。
class AppColors {
  static _Palette get _active {
    final mode = themeModeController.mode;
    final isDark = mode == ThemeMode.dark ||
        (mode == ThemeMode.system &&
            SchedulerBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    return isDark ? _darkPalette : _lightPalette;
  }

  static Color get background => _active.background;
  static Color get surface => _active.surface;
  static Color get surfaceVariant => _active.surfaceVariant;
  static Color get pillSelected => _active.pillSelected;
  static Color get textPrimary => _active.textPrimary;
  static Color get textSecondary => _active.textSecondary;
  /// 强调色（主题色）：优先取用户在色环里自定义的颜色，未自定义时回退调色板默认值。
  static Color get accent => accentColorController.color ?? _active.accent;

  /// 主题色之上的前景色（按钮文字/图标）：按对比度自动取深色或白色。
  static Color get onAccent => onAccentColor(accent);

  static Color get divider => _active.divider;
  static Color get inputBg => _active.inputBg;

  // 信纸（浅色背景）上的文字颜色固定为深色，保证可读性，不随主题变化
  static const paperTextPrimary = Color(0xFF2A2A2C);
  static const paperTextSecondary = Color(0xFF6A6A6C);
}

/// 主题模式控制器（全局单例）：变更会通知 MaterialApp 重建整棵子树，
/// 从而让 [AppColors] 的静态 getter 取到新调色板。
class ThemeModeController extends ChangeNotifier {
  ThemeMode mode;
  ThemeModeController([this.mode = ThemeMode.dark]);

  void set(ThemeMode m) {
    if (mode == m) return;
    mode = m;
    notifyListeners();
  }
}

final themeModeController = ThemeModeController(ThemeMode.dark);

/// 主题色控制器（全局单例）：承载用户在色环里自定义的主题色。
/// `color == null` 表示未自定义，回退到调色板默认强调色。
/// 变更会通知 MaterialApp 重建整棵子树，从而让 [AppColors] 与
/// [AppTheme] 派生出的 `colorScheme` 同时立即生效。
class AccentColorController extends ChangeNotifier {
  Color? _color;
  Color? get color => _color;

  void set(Color? c) {
    if (_color == c) return;
    _color = c;
    notifyListeners();
  }
}

final accentColorController = AccentColorController();

/// 主题色之上的前景色：取黑 / 白中与该色对比度更高的一个。
///
/// 0.179 是黑白对比度相等的临界相对亮度（WCAG 公式），低于它用白字、高于它用黑字。
/// 这样用户把主题色选成深蓝、深紫时，按钮文字不会变成看不清的深色；
/// 且无论选什么颜色，前景/背景对比度都不低于 4.58（满足 WCAG AA 的 4.5）。
Color onAccentColor(Color accent) =>
    accent.computeLuminance() > 0.179 ? Colors.black : Colors.white;

/// Color -> '#RRGGBB'（主题色不透明，忽略 alpha）
String colorToHex(Color c) {
  final rgb = c.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// '#RRGGBB' / 'RRGGBB' / '#AARRGGBB' -> Color；解析失败返回 null。
Color? colorFromHex(String hex) {
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

/// 字符串 <-> ThemeMode
ThemeMode parseThemeMode(String s) {
  switch (s) {
    case 'light':
      return ThemeMode.light;
    case 'system':
      return ThemeMode.system;
    default:
      return ThemeMode.dark;
  }
}

String themeModeToString(ThemeMode m) {
  switch (m) {
    case ThemeMode.light:
      return 'light';
    case ThemeMode.system:
      return 'system';
    default:
      return 'dark';
  }
}

/// 应用主题（由「明暗调色板 + 用户自定义主题色」共同决定）。
///
/// 注意：`lightTheme` / `darkTheme` 是 **getter 而非静态常量**——
/// 它们每次都会读取 [accentColorController] 的当前值，把用户选的色环颜色
/// 写进 `colorScheme.primary` 等槽位。这样 Material 自带控件
/// （Slider / Switch / 进度条 / 按钮涟漪 / 分段控件 / 文本选区）都会跟着变色，
/// 而不只是 [AppColors.accent] 这条自定义链路。
class AppTheme {
  static ThemeData get darkTheme => _build(_darkPalette, Brightness.dark);

  static ThemeData get lightTheme => _build(_lightPalette, Brightness.light);

  static ThemeData _build(_Palette p, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final accent = accentColorController.color ?? p.accent;
    final onAccent = onAccentColor(accent);

    // 用 Material 的命名构造器保证各槽位都有合法默认值，再覆盖主题色相关槽位。
    // 不传已弃用的 background（一并走 surface），页面底色由
    // scaffoldBackgroundColor 指定、组件底色统一读 AppColors.*。
    final base = isDark
        ? ColorScheme.dark(surface: p.surface, onSurface: p.textPrimary)
        : ColorScheme.light(surface: p.surface, onSurface: p.textPrimary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: p.background,
      colorScheme: base.copyWith(
        primary: accent,
        onPrimary: onAccent,
        secondary: accent,
        onSecondary: onAccent,
        // M3 里选中态容器（SegmentedButton / Chip / FilterChip）默认取 secondaryContainer，
        // 这里用主题色的半透明版本，未单独指定样式的控件也能跟随主题色。
        secondaryContainer: accent.withValues(alpha: isDark ? 0.30 : 0.22),
        onSecondaryContainer: p.textPrimary,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha: 0.32),
        selectionHandleColor: accent,
      ),
      textTheme: TextTheme(
        bodyMedium: TextStyle(color: p.textPrimary, fontSize: 14),
        titleMedium:
            TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600),
        labelSmall: TextStyle(color: p.textSecondary, fontSize: 12),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.divider),
        ),
      ),
    );
  }
}
