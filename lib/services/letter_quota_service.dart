import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 写信配额（Beta3）：每个自然日最多寄出 [dailyLimit] 封信。
///
/// 明文 JSON 存于 `letter_quota.json`，内容只是「每封信的寄出时间戳」列表；
/// 「今日已寄」＝ 与当前时间同年月日的时间戳个数，因此**跨天自动归零**，
/// 不需要额外的日期字段或零点重置定时器。
///
/// 所有磁盘操作都静默降级（读失败视为无记录、写失败忽略）：这是本地单机
/// 应用的自律性限制，不承担风控职责，绝不能因为配额文件损坏而阻断写信。
class LetterQuotaService {
  /// 每日可寄出的信件上限（改这里即可调整限制）
  static const int dailyLimit = 3;

  static const String _fileName = 'letter_quota.json';

  /// 落盘时保留最近多少天的记录（仅用于避免文件无限增长，不影响配额判定）
  static const int _keepDays = 7;

  // ---------------------------------------------------------------- 纯函数

  /// 与 [now] 处于同一自然日（本地时区）的寄出时间
  static List<DateTime> sentOn(Iterable<DateTime> all, DateTime now) => all
      .where((t) => t.year == now.year && t.month == now.month && t.day == now.day)
      .toList();

  /// 今日已寄出的封数
  static int usedToday(Iterable<DateTime> all, DateTime now) =>
      sentOn(all, now).length;

  /// 今日还可寄出的封数（不低于 0）
  static int remaining(Iterable<DateTime> all, DateTime now) {
    final used = usedToday(all, now);
    return used >= dailyLimit ? 0 : dailyLimit - used;
  }

  /// 今日是否还能寄信
  static bool canSend(Iterable<DateTime> all, DateTime now) =>
      remaining(all, now) > 0;

  // ---------------------------------------------------------------- 持久化

  static Future<String> _path() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/$_fileName';
  }

  /// 读取全部寄出记录（按时间正序）；文件缺失或损坏时返回空列表
  static Future<List<DateTime>> loadAll() async {
    try {
      final f = File(await _path());
      if (!f.existsSync()) return [];
      final raw = jsonDecode(await f.readAsString());
      if (raw is! List) return [];
      final all = raw
          .map((e) => DateTime.tryParse(e.toString()))
          .whereType<DateTime>()
          .toList()
        ..sort();
      return all;
    } catch (_) {
      return [];
    }
  }

  /// 今日已寄出的封数
  static Future<int> usedTodayFromDisk() async =>
      usedToday(await loadAll(), DateTime.now());

  /// 今日还可寄出的封数
  static Future<int> remainingToday() async =>
      remaining(await loadAll(), DateTime.now());

  /// 记录一次寄信（在信件真正送出后调用）
  static Future<void> recordSend([DateTime? at]) async {
    try {
      final now = at ?? DateTime.now();
      final kept = (await loadAll())
          .where((t) => now.difference(t).inDays < _keepDays)
          .toList()
        ..add(now);
      final f = File(await _path());
      await f.writeAsString(
        jsonEncode(kept.map((t) => t.toIso8601String()).toList()),
      );
    } catch (_) {
      // 忽略：写失败不阻断写信
    }
  }

  /// 清空全部记录（调试用；不做上限解除，仅重置计数）
  static Future<void> reset() async {
    try {
      final f = File(await _path());
      if (f.existsSync()) await f.delete();
    } catch (_) {
      // 忽略
    }
  }
}
