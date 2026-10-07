import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:olivia_ank4/domain/models.dart';
import 'package:olivia_ank4/domain/settings.dart';
import 'package:olivia_ank4/services/crypto_service.dart';
import 'package:olivia_ank4/services/embedding_service.dart';
import 'package:path_provider/path_provider.dart';

/// 本地记忆向量库（P4 检索，P6 主密码加密）
///
/// 存储形态：应用支持目录下的 `memory.json`，以主密码 AES-256-CBC 加密落地
/// （与 settings.enc / letters.json 共用同一把主密码）。
/// - 未解锁时 loadAll 返回空、_persist 不写，避免清空加密数据。
/// - 兼容 P4 遗留明文文件：解锁后首次读取识别明文并迁移。
class MemoryService {
  static const String _fileName = 'memory.json';
  static const _idChars = 'abcdefghijklmnopqrstuvwxyz0123456789';

  static Future<String> _path() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/$_fileName';
  }

  /// 读取全部记忆块。
  /// 未解锁返回空；解密失败尝试按旧明文解析（迁移）；均失败返回空。
  static Future<List<MemoryChunk>> loadAll() async {
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
      try {
        list = jsonDecode(content) as List<dynamic>;
      } catch (_) {
        return []; // 密码错误或文件损坏
      }
    }
    return list.map((e) => _fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 密文落地：未解锁不写，避免清空加密数据
  static Future<void> _persist(List<MemoryChunk> all) async {
    final pass = CryptoService.sessionPassphrase;
    if (pass == null) return; // 锁定：保持原加密文件不动
    final json = jsonEncode(all.map(_toJson).toList());
    final enc = CryptoService.encryptString(json, pass);
    final f = File(await _path());
    await f.writeAsString(enc);
  }

  /// 切块并 Embedding 后追加进本地库；返回新增块数
  static Future<int> addTexts({
    required List<String> texts,
    required AppSettings settings,
    String? letterId,
    http.Client? client,
  }) async {
    final cleaned = texts.where((t) => t.trim().isNotEmpty).toList();
    if (cleaned.isEmpty) return 0;
    final chunks = chunkText(cleaned.join('\n\n'));
    if (chunks.isEmpty) return 0;

    final vectors = await EmbeddingService.embedBatch(
      settings: settings,
      texts: chunks,
      client: client,
    );

    final existing = await loadAll();
    final now = DateTime.now();
    for (var i = 0; i < chunks.length; i++) {
      existing.add(MemoryChunk(
        id: _uid(),
        letterId: letterId ?? 'compose',
        text: chunks[i],
        vector: vectors[i],
        createdAt: now,
      ));
    }
    await _persist(existing);
    return chunks.length;
  }

  /// 用查询向量检索 top-k 相似记忆块（余弦相似度）
  static Future<List<MemoryChunk>> retrieve(
    List<double> query, {
    int topK = 4,
  }) async {
    if (query.isEmpty) return [];
    final all = await loadAll();
    final scored = <MapEntry<MemoryChunk, double>>[];
    for (final c in all) {
      if (c.vector == null || c.vector!.isEmpty) continue;
      final sim = _cosine(query, c.vector!);
      scored.add(MapEntry(c, sim));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(topK).map((e) => e.key).toList();
  }

  /// 清空记忆库
  static Future<void> clear() async {
    final f = File(await _path());
    if (f.existsSync()) await f.delete();
  }

  // ---- 文本切块 ----
  /// 按段落切分，短段合并、超长段自动截断（默认单块上限 600 字，适合 embedding 上下文）
  static List<String> chunkText(String text, {int maxLen = 600}) {
    final paras = text.split(RegExp(r'\n{1,}'));
    final out = <String>[];
    var buf = '';
    for (final raw in paras) {
      final p = raw.trim();
      if (p.isEmpty) continue;
      if (buf.isNotEmpty && buf.length + p.length + 1 > maxLen) {
        out.add(buf);
        buf = '';
      }
      buf = buf.isEmpty ? p : '$buf\n$p';
      while (buf.length > maxLen) {
        out.add(buf.substring(0, maxLen));
        buf = buf.substring(maxLen);
      }
    }
    if (buf.isNotEmpty) out.add(buf);
    return out;
  }

  // ---- 余弦相似度 ----
  static double _cosine(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0.0;
    double dot = 0, na = 0, nb = 0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0.0;
    return dot / (sqrt(na) * sqrt(nb));
  }

  static String _uid() {
    final r = Random.secure();
    return List.generate(12, (_) => _idChars[r.nextInt(_idChars.length)]).join();
  }

  static Map<String, dynamic> _toJson(MemoryChunk c) => {
        'id': c.id,
        'letterId': c.letterId,
        'text': c.text,
        'vector': c.vector,
        'createdAt': c.createdAt.toIso8601String(),
      };

  static MemoryChunk _fromJson(Map<String, dynamic> j) => MemoryChunk(
        id: j['id'] as String,
        letterId: j['letterId'] as String? ?? 'unknown',
        text: j['text'] as String,
        vector: (j['vector'] as List?)?.map((e) => (e as num).toDouble()).toList(),
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}
