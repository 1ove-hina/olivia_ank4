import 'package:flutter_test/flutter_test.dart';
import 'package:olivia_ank4/services/birthday_service.dart';

void main() {
  group('BirthdayService.isBirthday', () {
    test('生日为 null 时不是生日', () {
      expect(BirthdayService.isBirthday(null, DateTime(2026, 9, 14)), isFalse);
    });

    test('月日相同即为生日（年份无关）', () {
      final birthday = DateTime(2000, 9, 14);
      expect(BirthdayService.isBirthday(birthday, DateTime(2026, 9, 14)), isTrue);
    });

    test('月日不同不是生日', () {
      final birthday = DateTime(2000, 9, 14);
      expect(BirthdayService.isBirthday(birthday, DateTime(2026, 9, 15)), isFalse);
      expect(BirthdayService.isBirthday(birthday, DateTime(2026, 10, 14)), isFalse);
    });
  });

  group('BirthdayService.alreadyGreeted', () {
    test('同年已送过', () {
      expect(BirthdayService.alreadyGreeted(2026, 2026), isTrue);
    });

    test('不同年份未送过', () {
      expect(BirthdayService.alreadyGreeted(2025, 2026), isFalse);
      expect(BirthdayService.alreadyGreeted(null, 2026), isFalse);
    });
  });
}
