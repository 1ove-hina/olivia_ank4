import 'package:flutter_test/flutter_test.dart';
import 'package:olivia_ank4/domain/user_profile.dart';

void main() {
  group('UserProfile', () {
    test('默认昵称为「寄信人」', () {
      final p = UserProfile(joinedAt: DateTime(2026, 9, 14));
      expect(p.nickname, '寄信人');
    });

    test('toJson / fromJson 往返一致', () {
      final original = UserProfile(
        nickname: 'LinLiFan',
        joinedAt: DateTime(2026, 9, 14, 20, 42),
      );
      final json = original.toJson();
      final restored = UserProfile.fromJson(json);

      expect(restored.nickname, original.nickname);
      expect(restored.joinedAt, original.joinedAt);
    });

    test('fromJson 缺 nickname 时使用默认值', () {
      final restored = UserProfile.fromJson({
        'joinedAt': '2026-09-14T20:42:00.000',
      });
      expect(restored.nickname, '寄信人');
    });

    test('copyWith 仅修改指定字段', () {
      final p = UserProfile(
        nickname: 'Old',
        joinedAt: DateTime(2026, 1, 1),
      );
      final updated = p.copyWith(nickname: 'New');
      expect(updated.nickname, 'New');
      expect(updated.joinedAt, p.joinedAt);
    });

    group('生日字段', () {
      test('birthday / lastBirthdayGreetYear 可序列化往返', () {
        final p = UserProfile(
          nickname: 'LinLiFan',
          joinedAt: DateTime(2026, 9, 14),
          birthday: DateTime(2000, 5, 20),
          lastBirthdayGreetYear: 2026,
        );
        final restored = UserProfile.fromJson(p.toJson());
        expect(restored.birthday, DateTime(2000, 5, 20));
        expect(restored.lastBirthdayGreetYear, 2026);
      });

      test('缺生日字段时 birthday 为 null', () {
        final p = UserProfile.fromJson({'joinedAt': '2026-09-14T00:00:00.000'});
        expect(p.birthday, isNull);
        expect(p.lastBirthdayGreetYear, isNull);
      });

      test('copyWith 可设置与清除生日', () {
        final p = UserProfile(joinedAt: DateTime(2026, 9, 14));
        final set = p.copyWith(birthday: DateTime(1999, 3, 3));
        expect(set.birthday, DateTime(1999, 3, 3));
        final cleared = set.copyWith(clearBirthday: true);
        expect(cleared.birthday, isNull);
      });
    });

    group('性别字段', () {
      test('默认性别为 unknown（保密）', () {
        final p = UserProfile(joinedAt: DateTime(2026, 9, 14));
        expect(p.gender, UserGender.unknown);
        expect(p.gender.label, '保密');
      });

      test('gender 序列化往返一致', () {
        for (final g in UserGender.values) {
          final p = UserProfile(joinedAt: DateTime(2026, 9, 14), gender: g);
          final restored = UserProfile.fromJson(p.toJson());
          expect(restored.gender, g);
        }
      });

      test('fromJson 缺 gender 时回退 unknown', () {
        final p = UserProfile.fromJson({'joinedAt': '2026-09-14T00:00:00.000'});
        expect(p.gender, UserGender.unknown);
      });

      test('fromJson 收到非法 gender 索引时回退 unknown', () {
        final p = UserProfile.fromJson({
          'joinedAt': '2026-09-14T00:00:00.000',
          'gender': 99,
        });
        expect(p.gender, UserGender.unknown);
      });

      test('copyWith 可修改性别', () {
        final p = UserProfile(joinedAt: DateTime(2026, 9, 14));
        final updated = p.copyWith(gender: UserGender.female);
        expect(updated.gender, UserGender.female);
        expect(updated.gender.label, '女');
      });
    });
  });
}
