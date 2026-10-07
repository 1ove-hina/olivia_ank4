import 'package:flutter_test/flutter_test.dart';
import 'package:olivia_ank4/services/letter_quota_service.dart';

void main() {
  // 固定「现在」：2026-09-17 15:30，避免测试依赖真实时间
  final now = DateTime(2026, 9, 17, 15, 30);

  DateTime at(int y, int m, int d, [int h = 12]) => DateTime(y, m, d, h);

  group('LetterQuotaService 每日寄信上限', () {
    test('上限为 3 封', () {
      expect(LetterQuotaService.dailyLimit, 3);
    });

    test('无记录时可送 3 封', () {
      expect(LetterQuotaService.remaining([], now), 3);
      expect(LetterQuotaService.canSend([], now), isTrue);
      expect(LetterQuotaService.usedToday([], now), 0);
    });

    test('今日已送 1 / 2 封时剩余正确递减', () {
      expect(LetterQuotaService.remaining([at(2026, 9, 17, 9)], now), 2);
      expect(
        LetterQuotaService.remaining(
            [at(2026, 9, 17, 9), at(2026, 9, 17, 12)], now),
        1,
      );
    });

    test('今日送满 3 封后剩余为 0 且不可再送', () {
      final all = [
        at(2026, 9, 17, 8),
        at(2026, 9, 17, 12),
        at(2026, 9, 17, 20),
      ];
      expect(LetterQuotaService.remaining(all, now), 0);
      expect(LetterQuotaService.canSend(all, now), isFalse);
    });

    test('跨天自动重置：昨天 / 上月 / 去年的记录不计入今日', () {
      final all = [
        at(2025, 9, 17), // 去年
        at(2026, 8, 17), // 上月
        at(2026, 9, 16), // 昨天
        at(2026, 9, 17, 9), // 今天
      ];
      expect(LetterQuotaService.usedToday(all, now), 1);
      expect(LetterQuotaService.remaining(all, now), 2);
    });

    test('次日零点后前一天 3 封不再占用配额', () {
      final yesterday = [
        at(2026, 9, 16, 8),
        at(2026, 9, 16, 12),
        at(2026, 9, 16, 23),
      ];
      expect(LetterQuotaService.remaining(yesterday, now), 3);
      expect(
        LetterQuotaService.canSend(yesterday, DateTime(2026, 9, 17, 0, 1)),
        isTrue,
      );
      // 但在昨天当天看，是已经用满的
      expect(
        LetterQuotaService.canSend(yesterday, DateTime(2026, 9, 16, 23, 59)),
        isFalse,
      );
    });

    test('异常超额记录不会让剩余变成负数', () {
      final all = List.generate(6, (i) => at(2026, 9, 17, 1 + i));
      expect(LetterQuotaService.remaining(all, now), 0);
      expect(LetterQuotaService.canSend(all, now), isFalse);
    });

    test('同日判定不受具体时刻影响（00:00 与 23:59 属同一天）', () {
      final all = [
        DateTime(2026, 9, 17, 0, 0, 1),
        DateTime(2026, 9, 17, 23, 59, 59),
      ];
      expect(LetterQuotaService.sentOn(all, now).length, 2);
    });

    test('sentOn 只挑出同一自然日，且保持原顺序', () {
      final all = [
        at(2026, 9, 17, 8),
        at(2026, 9, 16, 20),
        at(2026, 9, 17, 19),
      ];
      final today = LetterQuotaService.sentOn(all, now);
      expect(today.length, 2);
      expect(today.first.hour, 8);
      expect(today.last.hour, 19);
    });
  });
}
