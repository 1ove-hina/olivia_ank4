import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:olivia_ank4/domain/models.dart';
import 'package:olivia_ank4/services/crypto_service.dart';
import 'package:olivia_ank4/services/letter_service.dart';
import 'package:path_provider/path_provider.dart';

/// 延迟收信：写信生成回信后，不立即展示，而是排入「待投递」队列，
/// 在 15–60 分钟（随机）后投递——把回信写入对应信件（assistant 消息）。
/// 队列以主密码 AES 加密落盘（pending_replies.json），因此「退出软件不会失效」：
/// 下次启动由 PendingReplyWatcher 立即补投关闭期间已到期的回信。
class PendingReply {
  final String id;
  final String letterId;
  final String draft; // 来信内容（备份）
  final String reply; // 林离回信内容（已生成，待投递）
  final int createdAt; // 毫秒
  final int dueAt; // 毫秒：应投递时间

  const PendingReply({
    required this.id,
    required this.letterId,
    required this.draft,
    required this.reply,
    required this.createdAt,
    required this.dueAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'letterId': letterId,
        'draft': draft,
        'reply': reply,
        'createdAt': createdAt,
        'dueAt': dueAt,
      };

  factory PendingReply.fromJson(Map<String, dynamic> j) => PendingReply(
        id: j['id'] as String,
        letterId: j['letterId'] as String,
        draft: j['draft'] as String? ?? '',
        reply: j['reply'] as String? ?? '',
        createdAt: j['createdAt'] as int? ?? 0,
        dueAt: j['dueAt'] as int? ?? 0,
      );

  DateTime get dueTime => DateTime.fromMillisecondsSinceEpoch(dueAt);
}

class PendingReplyService {
  static const String _fileName = 'pending_replies.json';
  static const _idChars = 'abcdefghijklmnopqrstuvwxyz0123456789';

  static Future<String> _path() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/$_fileName';
  }

  /// 读取全部待投递项；未解锁或文件缺失返回空
  static Future<List<PendingReply>> loadAll() async {
    final f = File(await _path());
    if (!f.existsSync()) return [];
    final pass = CryptoService.sessionPassphrase;
    if (pass == null) return [];
    final content = await f.readAsString();
    final decrypted = CryptoService.decryptString(content, pass);
    if (decrypted == null) return [];
    try {
      final list = jsonDecode(decrypted) as List<dynamic>;
      return list
          .map((e) => PendingReply.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _persistAll(List<PendingReply> all) async {
    final pass = CryptoService.sessionPassphrase;
    if (pass == null) return; // 锁定：保持原加密文件不动
    final json = jsonEncode(all.map((p) => p.toJson()).toList());
    final enc = CryptoService.encryptString(json, pass);
    final f = File(await _path());
    await f.writeAsString(enc);
  }

  /// 登记一条待投递回信，返回其实例
  static Future<PendingReply> schedule({
    required String letterId,
    required String draft,
    required String reply,
    required DateTime dueAt,
  }) async {
    final all = await loadAll();
    final p = PendingReply(
      id: List.generate(
          12, (_) => _idChars[Random.secure().nextInt(_idChars.length)]).join(),
      letterId: letterId,
      draft: draft,
      reply: reply,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      dueAt: dueAt.millisecondsSinceEpoch,
    );
    all.add(p);
    await _persistAll(all);
    return p;
  }

  static Future<void> remove(String id) async {
    final all = await loadAll();
    all.removeWhere((p) => p.id == id);
    await _persistAll(all);
  }

  /// 取已到期（dueAt <= now）的待投递项
  static Future<List<PendingReply>> dueOnes(DateTime now) async {
    final all = await loadAll();
    final t = now.millisecondsSinceEpoch;
    return all.where((p) => p.dueAt <= t).toList();
  }

  /// 取某封信当前的待投递项（若存在）
  static Future<PendingReply?> forLetter(String letterId) async {
    final all = await loadAll();
    try {
      return all.firstWhere((p) => p.letterId == letterId);
    } catch (_) {
      return null;
    }
  }

  /// 投递：把回信写入对应信件（追加 assistant 消息），并移除待投递项
  static Future<void> deliver(PendingReply p) async {
    final pass = CryptoService.sessionPassphrase;
    if (pass == null) return;
    final letter = await LetterService.get(p.letterId);
    if (letter != null) {
      final already =
          letter.messages.any((m) => m.role == 'assistant' && m.content == p.reply);
      if (!already) {
        final now = DateTime.now();
        final msgs = List<Message>.from(letter.messages)
          ..add(Message(role: 'assistant', content: p.reply, createdAt: now));
        final updated = Letter(
          id: letter.id,
          title: letter.title,
          personaId: letter.personaId,
          messages: msgs,
          createdAt: letter.createdAt,
          updatedAt: now,
        );
        await LetterService.save(updated);
      }
    }
    await remove(p.id);
  }
}

/// 延迟收信监视器（单例）：在 AppShell 解锁后启动。
/// - 每 30s 周期检查；同时按「最近的未来 dueAt」精确排程一次性定时器，缩短等待误差。
/// - 启动即立即检查一次，覆盖软件关闭期间已到期的回信（退出不失效）。
/// - 投递成功会通知监听者（写信页据此把回信显示出来）。
class PendingReplyWatcher {
  static final PendingReplyWatcher instance = PendingReplyWatcher._();
  PendingReplyWatcher._();

  final List<void Function(PendingReply)> _listeners = [];
  Timer? _periodic;
  Timer? _next;
  bool _checking = false;

  void addListener(void Function(PendingReply) cb) => _listeners.add(cb);
  void removeListener(void Function(PendingReply) cb) => _listeners.remove(cb);

  void start() {
    _periodic?.cancel();
    _periodic =
        Timer.periodic(const Duration(seconds: 30), (_) => _check());
    _check(); // 立即补投关闭期间到期的
  }

  Future<void> _check() async {
    if (_checking) return; // 防止周期检查与精确定时器在 await 处重入导致重复投递
    _checking = true;
    try {
      final pass = CryptoService.sessionPassphrase;
    if (pass == null) return;
    final all = await PendingReplyService.loadAll();
    final now = DateTime.now();
    final t = now.millisecondsSinceEpoch;

    // 投递所有已到期项
    final due = all.where((p) => p.dueAt <= t).toList();
    for (final p in due) {
      await PendingReplyService.deliver(p);
      for (final cb in List.from(_listeners)) {
        cb(p);
      }
    }

    // 为最近的未来 dueAt 排程精确一次性定时器
    _next?.cancel();
    _next = null;
    final future = all.where((p) => p.dueAt > t).toList();
    if (future.isNotEmpty) {
      future.sort((a, b) => a.dueAt.compareTo(b.dueAt));
      final wait = future.first.dueTime.difference(now);
      _next = Timer(wait > Duration.zero ? wait : const Duration(seconds: 5),
          () => _check());
    }
    } finally {
      _checking = false;
    }
  }
}
