import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 本机凭据存储：用操作系统级安全存储「记住」主密码。
///
/// 目的：主密码只在**初始化软件时输入一次**，之后每次启动自动解锁、不再弹密码框。
/// 本机数据（settings.enc / letters.json / memory.json）仍由主密码 AES 加密，
/// 密文依旧**可移植**——换设备用同一主密码即可解密（与设备绑定无关）。
/// 这里只是把「记得密码」这件事交给操作系统保管：
/// - Windows：DPAPI（CryptProtectData），绑定当前 Windows 用户账户，
///   数据存于 HKCU 注册表，文件里不会出现明文密码，其他账户无法解密。
///
/// 因此仍需输入主密码的场合只剩：
/// 1. 首次初始化；
/// 2. 「转移数据」（导出/导入备份，见设置页 BackupService）；
/// 3. 本机凭据缺失/失效时（例如换设备、手动清除）补输一次，成功后会自动记回。
class CredentialStore {
  static const String _keyPassphrase = 'olivia_ank4_master_passphrase';
  static const FlutterSecureStorage _store = FlutterSecureStorage();

  /// 记住主密码（初始化、解锁成功、导入备份后调用）
  static Future<void> save(String passphrase) =>
      _store.write(key: _keyPassphrase, value: passphrase);

  /// 读取本机记住的主密码；未记住或已清除返回 null
  static Future<String?> read() => _store.read(key: _keyPassphrase);

  /// 清除（例如用户希望下次启动重新要求输入密码）
  static Future<void> clear() => _store.delete(key: _keyPassphrase);
}
