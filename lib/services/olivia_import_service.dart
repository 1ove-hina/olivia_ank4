import 'dart:convert';
import 'dart:io';
import 'package:olivia_ank4/domain/models.dart';
import 'package:olivia_ank4/services/crypto_service.dart';
import 'package:olivia_ank4/services/letter_service.dart';

/// 从 Olivia 原版（米哈游桌面客户端）导入信件（P7）。
///
/// 数据来源：Olivia 的对话走服务端 API，其明文 JSON 响应被缓存在 Chromium
/// HTTP 磁盘缓存里（`%APPDATA%\miHoYo\Olivia-steam\cache\web\**\Cache\*`）。
/// 单封信响应形如：
///   {"code":0,"message":"ok","data":{
///      "letterId":"a2_xxx","createdAt":<秒>,"content":"<用户来信>",
///      "sent":{"subject":"","timestamp":<毫秒>,"content":"<用户来信>"},
///      "received":{"subject":"林离的回信","timestamp":<毫秒>,"content":"<林离回信>"},
///      "replyText":"<林离回信>","replyType":1,"letterStatus":4,...}}
/// 列表响应形如：{"code":0,"message":"ok","data":{"list":[<上述单封的精简版>],"total":N}}
///
/// 本服务直接扫描这些缓存文件、提取信件 JSON、按 letterId 去重，并并入 olivia_ank4
/// 的信箱（沿用当前会话的主密码加密）。不依赖任何第三方解析库。
class OliviaImportService {
  /// 自动探测 Olivia 安装目录（Windows：%APPDATA%\miHoYo\Olivia-steam）
  static String? discoverOliviaDir() {
    final appData = Platform.environment['APPDATA'] ??
        Platform.environment['LOCALAPPDATA'];
    if (appData == null || appData.isEmpty) return null;
    final dir = Directory('$appData${Platform.pathSeparator}miHoYo'
        '${Platform.pathSeparator}Olivia-steam');
    return dir.existsSync() ? dir.path : null;
  }

  /// 扫描 [root] 下所有 Olivia 缓存文件，解析并返回去重后的信件列表。
  static Future<List<OliviaLetter>> parseDir(String root) async {
    final dir = Directory(root);
    if (!dir.existsSync()) return [];
    final files = <File>[];
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final p = e.path.toLowerCase();
      if (!p.contains('cache')) continue; // 仅扫描缓存目录
      final name = e.uri.pathSegments.last;
      if (!RegExp(r'(^|[/\\])(data_\d+|f_[0-9a-f]+)$').hasMatch(name)) continue;
      final sz = await e.length();
      if (sz == 0 || sz > 30 * 1024 * 1024) continue; // 跳过空/超大文件
      files.add(e);
    }

    final byId = <String, OliviaLetter>{};
    for (final f in files) {
      try {
        final bytes = await f.readAsBytes();
        final text = utf8.decode(bytes, allowMalformed: true);
        _extractInto(text, byId);
      } catch (_) {
        // 单个缓存文件解析失败不影响整体
      }
    }
    return byId.values.toList();
  }

  /// 将解析到的信件合并进信箱（用当前会话主密码加密）。已存在的 letterId 跳过。
  static Future<OliviaImportResult> importLetters(List<OliviaLetter> letters) async {
    final pass = CryptoService.sessionPassphrase;
    if (pass == null || pass.isEmpty) {
      return OliviaImportResult(
        parsed: letters.length,
        imported: 0,
        skipped: 0,
        titles: const [],
        error: '尚未解锁，无法写入信箱',
      );
    }
    final existing = await LetterService.loadAll();
    final existingIds = <String>{for (final l in existing) l.id};

    var imported = 0;
    var skipped = 0;
    final titles = <String>[];
    for (final ol in letters) {
      if (existingIds.contains(ol.id)) {
        skipped++;
        continue;
      }
      await LetterService.save(ol.toLetter());
      imported++;
      titles.add(ol.title);
    }
    return OliviaImportResult(
      parsed: letters.length,
      imported: imported,
      skipped: skipped,
      titles: titles,
    );
  }

  // ---- 内部：从文本中暴力提取所有 {"code":...} 对象并识别信件 ----

  static void _extractInto(String text, Map<String, OliviaLetter> byId) {
    final re = RegExp(r'\{\s*"code"\s*:');
    for (final m in re.allMatches(text)) {
      final obj = _matchBraces(text, m.start);
      if (obj == null) continue;
      Map<String, dynamic>? dec;
      try {
        dec = jsonDecode(obj) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final data = dec['data'];
      if (data is! Map) continue;
      if (data['list'] is List) {
        for (final item in data['list'] as List) {
          if (item is Map) _addLetter(item, byId);
        }
      }
      if (data['letterId'] != null) _addLetter(data, byId);
    }
  }

  /// 从位置 [start]（必须是 '{'）开始做括号配对，返回完整 JSON 子串；失败返回 null。
  static String? _matchBraces(String text, int start) {
    if (start < 0 || start >= text.length || text[start] != '{') return null;
    var depth = 0;
    var inStr = false;
    var esc = false;
    var i = start;
    while (i < text.length) {
      final c = text[i];
      if (inStr) {
        if (esc) {
          esc = false;
        } else if (c == '\\') {
          esc = true;
        } else if (c == '"') {
          inStr = false;
        }
      } else {
        if (c == '"') {
          inStr = true;
        } else if (c == '{') {
          depth++;
        } else if (c == '}') {
          depth--;
          if (depth == 0) return text.substring(start, i + 1);
        }
      }
      i++;
    }
    return null;
  }

  static void _addLetter(Map m, Map<String, OliviaLetter> byId) {
    final id = m['letterId'];
    if (id is! String || id.isEmpty) return;

    final sent = m['sent'];
    final received = m['received'];
    final userContent = _str((sent is Map ? sent['content'] : null) ?? m['content']);
    final aiContent = _str((received is Map ? received['content'] : null) ?? m['replyText']);

    if (userContent.isEmpty && aiContent.isEmpty) return;

    final createdMs = _toMs(sent is Map ? sent['timestamp'] : null) ??
        _toMs(m['createdAt']) ??
        DateTime.now().millisecondsSinceEpoch;
    final updatedMs = _toMs(received is Map ? received['timestamp'] : null) ??
        _toMs(m['repliedAt']) ??
        createdMs;

    final letter = OliviaLetter(
      id: id,
      userContent: userContent,
      aiContent: aiContent,
      createdMs: createdMs,
      updatedMs: updatedMs,
    );

    final prev = byId[id];
    if (prev == null) {
      byId[id] = letter;
    } else {
      // 保留信息更完整的版本（双方都在 > 单方）
      final prevScore = (prev.userContent.isNotEmpty ? 1 : 0) +
          (prev.aiContent.isNotEmpty ? 1 : 0);
      final newScore =
          (letter.userContent.isNotEmpty ? 1 : 0) + (letter.aiContent.isNotEmpty ? 1 : 0);
      if (newScore > prevScore) byId[id] = letter;
    }
  }

  static String _str(dynamic v) =>
      v is String ? v.trim() : (v?.toString() ?? '');

  /// 时间戳归一化为毫秒：毫秒级（>1e12）或秒级（>1e9）都兼容。
  static int? _toMs(dynamic v) {
    if (v is int) {
      if (v > 1e12) return v;
      if (v > 1e9) return v * 1000;
      return null;
    }
    if (v is double) return _toMs(v.toInt());
    return null;
  }
}

/// 一封从 Olivia 原版解析出的信件（用户来信 + 林离回信）
class OliviaLetter {
  final String id;
  final String userContent; // 用户写给林离的来信
  final String aiContent; // 林离的回信
  final int createdMs;
  final int updatedMs;

  const OliviaLetter({
    required this.id,
    required this.userContent,
    required this.aiContent,
    required this.createdMs,
    required this.updatedMs,
  });

  String get title {
    final src = userContent.isNotEmpty ? userContent : aiContent;
    final first = src
        .split('\n')
        .where((s) => s.trim().isNotEmpty)
        .firstOrNull
        ?.trim();
    final base = first ?? '未命名信件';
    return base.length > 40 ? '${base.substring(0, 40)}…' : base;
  }

  Letter toLetter() {
    final msgs = <Message>[];
    final created = DateTime.fromMillisecondsSinceEpoch(createdMs, isUtc: false);
    final updated = DateTime.fromMillisecondsSinceEpoch(updatedMs, isUtc: false);
    if (userContent.isNotEmpty) {
      msgs.add(Message(role: 'user', content: userContent, createdAt: created));
    }
    if (aiContent.isNotEmpty) {
      msgs.add(Message(
          role: 'assistant', content: aiContent, createdAt: updated));
    }
    return Letter(
      id: id,
      title: title,
      personaId: 'linli', // Olivia 原版信件均为林离
      messages: msgs,
      createdAt: created,
      updatedAt: updated,
    );
  }
}

class OliviaImportResult {
  final int parsed;
  final int imported;
  final int skipped;
  final List<String> titles;
  final String? error;

  const OliviaImportResult({
    required this.parsed,
    required this.imported,
    required this.skipped,
    required this.titles,
    this.error,
  });

  bool get ok => error == null;
}
