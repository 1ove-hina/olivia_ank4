import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:crypto/crypto.dart' show sha256;

/// 主密码加密服务（P1，替代设备绑定的 flutter_secure_storage）
/// - 密钥由 主密码 + 随机 salt 经 SHA-256 派生（AES-256-CBC）
/// - 密文可移植：在其它设备用同一主密码即可解密（非设备绑定）
/// - 主密码仅在会话内缓存（CryptoService.sessionPassphrase），不落盘
class CryptoService {
  static String? _sessionPassphrase;
  static String? get sessionPassphrase => _sessionPassphrase;
  static void setSessionPassphrase(String p) => _sessionPassphrase = p;

  static final Random _random = Random.secure();

  static enc.Key _deriveKey(String passphrase, List<int> salt) {
    final bytes = sha256.convert(utf8.encode(passphrase) + salt).bytes;
    return enc.Key(Uint8List.fromList(bytes));
  }

  /// 加密 JSON 可序列化对象，返回 base64 密文 blob（含 salt/iv，均为非机密元数据）
  static String encryptJson(Map<String, dynamic> payload, String passphrase) {
    final salt = List<int>.generate(16, (_) => _random.nextInt(256));
    final iv = List<int>.generate(16, (_) => _random.nextInt(256));
    final key = _deriveKey(passphrase, salt);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final plain = utf8.encode(jsonEncode(payload));
    final encrypted = encrypter.encryptBytes(plain, iv: enc.IV(Uint8List.fromList(iv)));
    final blob = {
      'v': 1,
      'salt': base64Encode(salt),
      'iv': base64Encode(iv),
      'data': encrypted.base64,
    };
    return base64Encode(utf8.encode(jsonEncode(blob)));
  }

  /// 解密；主密码错误或数据损坏返回 null
  static Map<String, dynamic>? decryptJson(String blob, String passphrase) {
    try {
      final decoded =
          jsonDecode(utf8.decode(base64Decode(blob))) as Map<String, dynamic>;
      final salt = base64Decode(decoded['salt'] as String);
      final iv = base64Decode(decoded['iv'] as String);
      final key = _deriveKey(passphrase, salt);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final decrypted = encrypter.decrypt64(
        decoded['data'] as String,
        iv: enc.IV(Uint8List.fromList(iv)),
      );
      return jsonDecode(decrypted) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 加密任意字符串（如 JSON 文本），返回 base64 密文 blob（含 salt/iv 元数据）
  /// 用于信件库 / 记忆库的整库 AES 落地（P6）
  static String encryptString(String plain, String passphrase) {
    final salt = List<int>.generate(16, (_) => _random.nextInt(256));
    final iv = List<int>.generate(16, (_) => _random.nextInt(256));
    final key = _deriveKey(passphrase, salt);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted =
        encrypter.encrypt(plain, iv: enc.IV(Uint8List.fromList(iv)));
    final blob = {
      'v': 1,
      'salt': base64Encode(salt),
      'iv': base64Encode(iv),
      'data': encrypted.base64,
    };
    return base64Encode(utf8.encode(jsonEncode(blob)));
  }

  /// 解密字符串；主密码错误或数据损坏返回 null
  static String? decryptString(String blob, String passphrase) {
    try {
      final decoded =
          jsonDecode(utf8.decode(base64Decode(blob))) as Map<String, dynamic>;
      final salt = base64Decode(decoded['salt'] as String);
      final iv = base64Decode(decoded['iv'] as String);
      final key = _deriveKey(passphrase, salt);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final decrypted = encrypter.decrypt64(
        decoded['data'] as String,
        iv: enc.IV(Uint8List.fromList(iv)),
      );
      return decrypted;
    } catch (_) {
      return null;
    }
  }
}
