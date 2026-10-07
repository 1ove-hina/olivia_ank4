import 'dart:io';
import 'package:olivia_ank4/domain/settings.dart';
import 'package:olivia_ank4/services/crypto_service.dart';
import 'package:path_provider/path_provider.dart';

/// 设置持久化服务（P1，主密码加密、可移植、非设备绑定）
/// 密文存于应用支持目录 settings.enc；主密码不落盘，仅在会话内缓存。
class SettingsService {
  static const String _fileName = 'settings.enc';

  static Future<String> _path() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/$_fileName';
  }

  static Future<bool> exists() async {
    final f = File(await _path());
    return f.existsSync();
  }

  /// 读取并解密；返回 null 表示主密码错误或数据损坏。
  static Future<AppSettings?> load(String passphrase) async {
    final f = File(await _path());
    if (!f.existsSync()) return const AppSettings();
    final blob = await f.readAsString();
    final payload = CryptoService.decryptJson(blob, passphrase);
    if (payload == null) return null;
    final settings = payload['settings'];
    if (settings is Map<String, dynamic>) {
      return AppSettings.fromJson(settings);
    }
    return const AppSettings();
  }

  /// 加密并写入（含 _verify 校验字段，解密失败即密码错误）。
  static Future<void> save(AppSettings s, String passphrase) async {
    final payload = {
      'settings': s.toJson(),
      '_verify': 'OK',
    };
    final blob = CryptoService.encryptJson(payload, passphrase);
    final f = File(await _path());
    await f.writeAsString(blob);
  }
}
