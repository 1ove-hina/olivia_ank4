import 'dart:convert';
import 'dart:io';
import 'package:olivia_ank4/domain/user_profile.dart';
import 'package:path_provider/path_provider.dart';

/// 用户资料服务（P1）
///
/// 明文 JSON 存储：昵称与注册时间不属于敏感信息，
/// 无需主密码加密；未初始化时自动创建默认资料。
class UserProfileService {
  static const String _fileName = 'user_profile.json';

  static Future<String> _path() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/$_fileName';
  }

  static Future<UserProfile> load() async {
    final f = File(await _path());
    if (!f.existsSync()) return defaultProfile();
    try {
      final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return UserProfile.fromJson(json);
    } catch (_) {
      return defaultProfile();
    }
  }

  static Future<void> save(UserProfile p) async {
    final f = File(await _path());
    await f.writeAsString(jsonEncode(p.toJson()));
  }

  static UserProfile defaultProfile() => UserProfile(joinedAt: DateTime.now());
}
