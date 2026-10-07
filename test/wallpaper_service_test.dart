import 'package:flutter_test/flutter_test.dart';
import 'package:olivia_ank4/services/wallpaper_service.dart';

void main() {
  group('WallpaperService.timeKeyFor', () {
    test('06:00–13:59 返回 1200（白天）', () {
      expect(WallpaperService.timeKeyFor(DateTime(2026, 9, 14, 6, 0)), '1200');
      expect(WallpaperService.timeKeyFor(DateTime(2026, 9, 14, 13, 59)), '1200');
    });

    test('14:00–17:59 返回 1730（午后）', () {
      expect(WallpaperService.timeKeyFor(DateTime(2026, 9, 14, 14, 0)), '1730');
      expect(WallpaperService.timeKeyFor(DateTime(2026, 9, 14, 17, 59)), '1730');
    });

    test('18:00–05:59 返回 2000（夜间）', () {
      expect(WallpaperService.timeKeyFor(DateTime(2026, 9, 14, 18, 0)), '2000');
      expect(WallpaperService.timeKeyFor(DateTime(2026, 9, 14, 23, 59)), '2000');
      expect(WallpaperService.timeKeyFor(DateTime(2026, 9, 14, 0, 0)), '2000');
      expect(WallpaperService.timeKeyFor(DateTime(2026, 9, 14, 5, 59)), '2000');
    });
  });

  group('WallpaperService.slotLabelFor', () {
    test('白天返回中文说明与素材号 1200', () {
      expect(
        WallpaperService.slotLabelFor(DateTime(2026, 9, 14, 10, 0)),
        '白天 06:00–14:00（素材 1200）',
      );
    });

    test('午后返回中文说明与素材号 1730', () {
      expect(
        WallpaperService.slotLabelFor(DateTime(2026, 9, 14, 15, 30)),
        '午后 14:00–18:00（素材 1730）',
      );
    });

    test('夜间不再返回占位符 "当前时段"', () {
      final label = WallpaperService.slotLabelFor(DateTime(2026, 9, 14, 20, 42));
      expect(label, isNot('当前时段'));
      expect(label, '夜间 18:00–次日 06:00（素材 2000）');
    });
  });
}
