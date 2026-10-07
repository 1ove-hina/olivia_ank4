import 'package:flutter/material.dart';
import 'package:olivia_ank4/app/theme.dart';
import 'package:olivia_ank4/services/stats_service.dart';

/// 写信回顾页（P2 体验功能）
/// 从加密信箱聚合写信统计：总信件 / 总字数 / 消息数 / 首末写信日期，
/// 以及近 6 个月写信量的柱状图。纯本地聚合，无外部依赖、无图表库。
class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  Future<LetterStats>? _future;

  @override
  void initState() {
    super.initState();
    _future = StatsService.compute();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LetterStats>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final s = snap.data ?? const LetterStats();
        return _body(s);
      },
    );
  }

  /// 日期格式化：无日期时显示占位符
  String _fmt(DateTime? d) => d == null
      ? '—'
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _body(LetterStats s) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('写信回顾',
              style: TextStyle(
                  fontSize: 22,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('记录你与林离往来的点滴',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 22),
          Row(
            children: [
              _statCard('总信件', '${s.letters}', Icons.mail_outline),
              const SizedBox(width: 14),
              _statCard('总字数', _pretty(s.chars), Icons.edit_note_outlined),
              const SizedBox(width: 14),
              _statCard('消息数', '${s.messages}', Icons.chat_bubble_outline),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _statCard('首次写信', _fmt(s.firstDate), Icons.flag_outlined),
              const SizedBox(width: 14),
              _statCard('最近写信', _fmt(s.lastDate), Icons.schedule_outlined),
            ],
          ),
          const SizedBox(height: 26),
          _monthChart(s),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: AppColors.accent),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 10),
            Text(value,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _monthChart(LetterStats s) {
    final months = StatsService.recentMonths(6);
    final counts =
        months.map((m) => s.byMonth[m] ?? 0).toList();
    final maxC = counts.fold(0, (a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('近 6 个月写信',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(months.length, (i) {
              final c = counts[i];
              final h = maxC == 0 ? 6.0 : 12.0 + (c / maxC) * 92.0;
              final label = months[i].substring(5); // 'MM'
              return Expanded(
                child: Column(
                  children: [
                    Container(
                      height: h,
                      width: 24,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('$c',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(label,
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 11)),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  String _pretty(int n) {
    if (n < 1000) return '$n';
    if (n < 10000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '${(n / 10000).toStringAsFixed(1)}w';
  }
}
