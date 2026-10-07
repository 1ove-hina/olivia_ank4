/// 性别（仅用于林离称呼 / 生日信语气等体验向用途，非敏感；默认保密）
enum UserGender {
  unknown,
  male,
  female,
}

extension UserGenderX on UserGender {
  String get label {
    switch (this) {
      case UserGender.male:
        return '男';
      case UserGender.female:
        return '女';
      case UserGender.unknown:
        return '保密';
    }
  }
}

/// 用户资料（P1）：非敏感信息，明文 JSON 持久化
///
/// 仅保存用户在应用内的显示名称与注册时间；
/// 敏感设置（API Key / Base URL / 主密码）仍走 SettingsService / CredentialStore。
class UserProfile {
  final String nickname;
  final DateTime joinedAt;
  final DateTime? birthday; // 出生日期（月/日用于生日判定，年份可选）
  final int? lastBirthdayGreetYear; // 林离已送生日信的年份，避免重复
  final UserGender gender; // 性别（体验向，默认保密）

  const UserProfile({
    this.nickname = '寄信人',
    required this.joinedAt,
    this.birthday,
    this.lastBirthdayGreetYear,
    this.gender = UserGender.unknown,
  });

  UserProfile copyWith({
    String? nickname,
    DateTime? joinedAt,
    DateTime? birthday,
    bool clearBirthday = false,
    int? lastBirthdayGreetYear,
    UserGender? gender,
  }) =>
      UserProfile(
        nickname: nickname ?? this.nickname,
        joinedAt: joinedAt ?? this.joinedAt,
        birthday: clearBirthday ? null : (birthday ?? this.birthday),
        lastBirthdayGreetYear:
            lastBirthdayGreetYear ?? this.lastBirthdayGreetYear,
        gender: gender ?? this.gender,
      );

  Map<String, dynamic> toJson() => {
        'nickname': nickname,
        'joinedAt': joinedAt.toIso8601String(),
        if (birthday != null) 'birthday': birthday!.toIso8601String(),
        if (lastBirthdayGreetYear != null)
          'lastBirthdayGreetYear': lastBirthdayGreetYear,
        'gender': gender.index,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        nickname: json['nickname'] as String? ?? '寄信人',
        joinedAt: DateTime.tryParse(json['joinedAt'] as String? ?? '') ??
            DateTime.now(),
        birthday: json['birthday'] == null
            ? null
            : DateTime.tryParse(json['birthday'] as String),
        lastBirthdayGreetYear: json['lastBirthdayGreetYear'] as int?,
        gender: _genderFromJson(json['gender']),
      );
}

UserGender _genderFromJson(dynamic v) {
  if (v is int && v >= 0 && v < UserGender.values.length) {
    return UserGender.values[v];
  }
  return UserGender.unknown;
}
