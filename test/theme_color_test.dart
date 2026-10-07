import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olivia_ank4/app/theme.dart';
import 'package:olivia_ank4/domain/settings.dart';

void main() {
  group('colorToHex / colorFromHex', () {
    test('Color -> #RRGGBB（大写，忽略 alpha）', () {
      expect(colorToHex(const Color(0xFFE8B14C)), '#E8B14C');
      expect(colorToHex(const Color(0xFF0A0B0C)), '#0A0B0C');
      expect(colorToHex(const Color(0x80E8B14C)), '#E8B14C');
    });

    test('hex -> Color 往返一致', () {
      const c = Color(0xFF3C9AE8);
      final parsed = colorFromHex(colorToHex(c));
      expect(parsed, isNotNull);
      expect(parsed!.toARGB32(), c.toARGB32());
    });

    test('支持带/不带 # 前缀与 6/8 位', () {
      expect(colorFromHex('#FF0000')!.toARGB32(), 0xFFFF0000);
      expect(colorFromHex('00FF00')!.toARGB32(), 0xFF00FF00);
      expect(colorFromHex('#8000FFFF')!.toARGB32(), 0x8000FFFF);
    });

    test('非法输入返回 null', () {
      expect(colorFromHex(''), isNull);
      expect(colorFromHex('#12'), isNull);
      expect(colorFromHex('zzzzzz'), isNull);
    });
  });

  group('AccentColorController', () {
    test('set 生效并通知监听者；相同值不重复通知；可恢复默认(null)', () {
      final c = AccentColorController();
      var notified = 0;
      c.addListener(() => notified++);

      expect(c.color, isNull);
      c.set(const Color(0xFFE8B14C));
      expect(c.color, const Color(0xFFE8B14C));
      expect(notified, 1);

      c.set(const Color(0xFFE8B14C)); // 同值
      expect(notified, 1);

      c.set(null); // 恢复默认主题色
      expect(c.color, isNull);
      expect(notified, 2);
    });
  });

  group('AppSettings.accentColor', () {
    test('默认空串（表示使用默认主题色）', () {
      expect(const AppSettings().accentColor, '');
    });

    test('toJson / fromJson 往返一致', () {
      const s = AppSettings(accentColor: '#E8B14C');
      final restored = AppSettings.fromJson(s.toJson());
      expect(restored.accentColor, '#E8B14C');
    });

    test('旧数据缺 accentColor 字段时回退空串（向后兼容）', () {
      final restored = AppSettings.fromJson({'themeMode': 'dark'});
      expect(restored.accentColor, '');
    });

    test('copyWith 可修改 accentColor', () {
      const s = AppSettings();
      expect(s.copyWith(accentColor: '#112233').accentColor, '#112233');
    });
  });

  group('onAccentColor（主题色之上的前景色）', () {
    test('亮色主题色用黑字', () {
      expect(onAccentColor(const Color(0xFFE8B14C)), Colors.black); // 金
      expect(onAccentColor(const Color(0xFFFFFFFF)), Colors.black);
      expect(onAccentColor(const Color(0xFFFFF176)), Colors.black);
    });

    test('深色主题色用白字', () {
      expect(onAccentColor(const Color(0xFF1F2A44)), Colors.white); // 深蓝
      expect(onAccentColor(const Color(0xFF000000)), Colors.white);
      expect(onAccentColor(const Color(0xFF4A148C)), Colors.white);
    });

    test('始终取对比度更高的一侧，且不低于 WCAG AA（4.5）', () {
      const samples = [
        Color(0xFFE8B14C), Color(0xFF3C9AE8), Color(0xFF1F2A44),
        Color(0xFF000000), Color(0xFFFFFFFF), Color(0xFFE53935),
        Color(0xFF26A69A), Color(0xFF8A8A92), Color(0xFFB388FF),
        Color(0xFF00C853), Color(0xFF9E9E9E), Color(0xFF424242),
      ];
      for (final c in samples) {
        final pick = onAccentColor(c);
        final other = pick == Colors.black ? Colors.white : Colors.black;
        expect(_contrast(c, pick) >= _contrast(c, other), isTrue,
            reason: '应取对比度更高的一侧：$c');
        expect(_contrast(c, pick) >= 4.5, isTrue, reason: '对比度不足：$c');
      }
    });
  });

  group('AppTheme 由主题色构建（Material 控件跟随）', () {
    tearDown(() => accentColorController.set(null));

    test('未自定义时回退调色板默认强调色，明暗各不同', () {
      accentColorController.set(null);
      expect(AppTheme.darkTheme.colorScheme.primary, const Color(0xFF8A8A92));
      expect(AppTheme.lightTheme.colorScheme.primary, const Color(0xFF6B7280));
    });

    test('自定义主题色写入 colorScheme.primary / onPrimary（明暗两套都跟随）', () {
      const bright = Color(0xFF3C9AE8); // 亮蓝 -> 黑字
      accentColorController.set(bright);
      for (final t in [AppTheme.darkTheme, AppTheme.lightTheme]) {
        expect(t.colorScheme.primary, bright);
        expect(t.colorScheme.secondary, bright);
        expect(t.colorScheme.onPrimary, onAccentColor(bright));
        expect(t.colorScheme.onPrimary, Colors.black);
      }

      const deep = Color(0xFF1F2A44); // 深蓝 -> 白字
      accentColorController.set(deep);
      for (final t in [AppTheme.darkTheme, AppTheme.lightTheme]) {
        expect(t.colorScheme.primary, deep);
        expect(t.colorScheme.onPrimary, Colors.white);
      }
    });

    test('文本选区 / 光标颜色也跟随主题色', () {
      const accent = Color(0xFFE8B14C);
      accentColorController.set(accent);
      final ts = AppTheme.darkTheme.textSelectionTheme;
      expect(ts.cursorColor, accent);
      expect(ts.selectionHandleColor, accent);
      expect(ts.selectionColor, isNotNull);
    });

    test('主题色变更后再次读取即为新值（getter 而非缓存的静态常量）', () {
      accentColorController.set(const Color(0xFF112233));
      expect(AppTheme.darkTheme.colorScheme.primary, const Color(0xFF112233));
      accentColorController.set(const Color(0xFF445566));
      expect(AppTheme.darkTheme.colorScheme.primary, const Color(0xFF445566));
    });

    test('构建主题不会污染全局主题色状态', () {
      const accent = Color(0xFF112233);
      accentColorController.set(accent);
      expect(AppTheme.darkTheme.colorScheme.primary, accent);
      expect(AppTheme.lightTheme.colorScheme.primary, accent);
      expect(accentColorController.color, accent); // 构建主题无副作用
    });
  });
}

/// WCAG 相对亮度对比度
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
