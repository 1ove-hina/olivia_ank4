import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:olivia_ank4/domain/models.dart';
import 'package:olivia_ank4/services/crypto_service.dart';
import 'package:path_provider/path_provider.dart';

/// 信箱本地存储服务（P5 持久化，P6 主密码加密）
///
/// 存储形态：应用支持目录下的 `letters.json`，以主密码 AES-256-CBC 加密落地
/// （与 settings.enc 共用同一把主密码，由 CryptoService.sessionPassphrase 提供）。
/// - 未解锁（会话内无主密码）时 loadAll 返回空、_persist 不写，避免清空加密数据。
/// - 兼容 P5 遗留明文文件：解锁后首次读取会自动识别明文并迁移，下次写入即转密文。
class LetterService {
  static const String _fileName = 'letters.json';
  static const _idChars = 'abcdefghijklmnopqrstuvwxyz0123456789';

  static Future<String> _path() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/$_fileName';
  }

  /// 生成信件 id（同样用于 ComposePage 复用同一封信）
  static String newId() {
    final r = Random.secure();
    return List.generate(12, (_) => _idChars[r.nextInt(_idChars.length)]).join();
  }

  /// 读取全部信件，按更新时间倒序（最新在前）。
  /// 未解锁返回空；解密失败尝试按旧明文解析（迁移）；均失败返回空。
  static Future<List<Letter>> loadAll() async {
    final f = File(await _path());
    if (!f.existsSync()) return [];
    final pass = CryptoService.sessionPassphrase;
    if (pass == null) return []; // 锁定：无密码无法解密
    final content = await f.readAsString();
    List<dynamic> list;
    final decrypted = CryptoService.decryptString(content, pass);
    if (decrypted != null) {
      try {
        list = jsonDecode(decrypted) as List<dynamic>;
      } catch (_) {
        return []; // 密文损坏
      }
    } else {
      // 兼容 P5 明文遗留：直接按明文解析
      try {
        list = jsonDecode(content) as List<dynamic>;
      } catch (_) {
        return []; // 密码错误或文件损坏
      }
    }
    final letters =
        list.map((e) => Letter.fromJson(e as Map<String, dynamic>)).toList();
    letters.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return letters;
  }

  static Future<Letter?> get(String id) async {
    final all = await loadAll();
    try {
      return all.firstWhere((l) => l.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 新增或更新（按 id 匹配覆盖）
  static Future<void> save(Letter letter) async {
    final all = await loadAll();
    final idx = all.indexWhere((l) => l.id == letter.id);
    if (idx >= 0) {
      all[idx] = letter;
    } else {
      all.add(letter);
    }
    await _persist(all);
  }

  static Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((l) => l.id == id);
    await _persist(all);
  }

  static Future<void> clear() async {
    final f = File(await _path());
    if (f.existsSync()) await f.delete();
  }

  /// 密文落地：未解锁不写，避免清空加密数据
  static Future<void> _persist(List<Letter> all) async {
    final pass = CryptoService.sessionPassphrase;
    if (pass == null) return; // 锁定：保持原加密文件不动
    final json = jsonEncode(all.map((l) => l.toJson()).toList());
    final enc = CryptoService.encryptString(json, pass);
    final f = File(await _path());
    await f.writeAsString(enc);
  }
}
