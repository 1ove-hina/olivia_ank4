import 'package:olivia_ank4/services/letter_service.dart';

/// 写信统计（P2 体验功能）
///
/// 统计采用「读取时聚合」而非「落盘累加」：直接从已加密的 letters.json
/// 经 LetterService.loadAll() 计算，天然包含导入的信件，且无需引入第二个
/// 加密存储文件，避免与信件库不同步。未解锁（无会话主密码）时 loadAll 返回空，
/// 统计即全 0，表现正确。
class LetterStats {
  final int letters; // 信件总数
  final int messages; // 消息总数（user + assistant）
  final int chars; // 全部消息内容字数
  final DateTime? firstDate; // 最早写信时间
  final DateTime? lastDate; // 最近写信时间
  final Map<String, int> byMonth; // 'yyyy-MM' -> 当月信件数

  const LetterStats({
    this.letters = 0,
    this.messages = 0,
    this.chars = 0,
    this.firstDate,
    this.lastDate,
    this.byMonth = const {},
  });
}

class StatsService {
  /// 聚合全部信件的统计快照。
  static Future<LetterStats> compute() async {
    final all = await LetterService.loadAll();
    int messages = 0;
    int chars = 0;
    DateTime? first;
    DateTime? last;
    final byMonth = <String, int>{};

    for (final l in all) {
      for (final m in l.messages) {
        messages++;
        chars += m.content.length;
      }
      if (first == null || l.createdAt.isBefore(first)) first = l.createdAt;
      if (last == null || l.createdAt.isAfter(last)) last = l.createdAt;
      final key =
          '${l.createdAt.year}-${l.createdAt.month.toString().padLeft(2, '0')}';
      byMonth[key] = (byMonth[key] ?? 0) + 1;
    }

    return LetterStats(
      letters: all.length,
      messages: messages,
      chars: chars,
      firstDate: first,
      lastDate: last,
      byMonth: byMonth,
    );
  }

  /// 最近 [n] 个月（含当月）的 'yyyy-MM' 键，用于月度柱状图横轴。
  static List<String> recentMonths(int n) {
    final now = DateTime.now();
    final out = <String>[];
    for (int i = n - 1; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      out.add('${d.year}-${d.month.toString().padLeft(2, '0')}');
    }
    return out;
  }
}
