import 'package:flutter/material.dart';
import 'package:olivia_ank4/app/theme.dart';
import 'package:olivia_ank4/domain/models.dart';
import 'package:olivia_ank4/services/letter_service.dart';

/// 信件详情 / 阅读页（P5）：以对话气泡展示来信与林离回信，支持「继续编辑」与「删除」
class LetterViewPage extends StatelessWidget {
  final Letter letter;
  final VoidCallback onEdit;
  final VoidCallback onBack;

  const LetterViewPage({
    super.key,
    required this.letter,
    required this.onEdit,
    required this.onBack,
  });

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('删除这封信？', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('删除后无法恢复。',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await LetterService.delete(letter.id);
      onBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * 14),
          child: child,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: Icon(Icons.arrow_back, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(letter.title,
                    style: TextStyle(
                        fontSize: 20, color: AppColors.textPrimary)),
              ),
              Text(_fmt(letter.updatedAt),
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('继续编辑'),
                style: TextButton.styleFrom(foregroundColor: AppColors.accent),
              ),
              TextButton.icon(
                onPressed: () => _delete(context),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('删除'),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: letter.messages.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final m = letter.messages[i];
                final isUser = m.role == 'user';
                return Align(
                  alignment:
                      isUser ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.7),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider),
                      image: DecorationImage(
                        image: AssetImage(isUser
                            ? 'assets/backgrounds/user_bg.webp'
                            : 'assets/backgrounds/linli_bg.webp'),
                        fit: BoxFit.cover,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isUser ? '来信' : '林离',
                            style: TextStyle(
                                color: AppColors.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        SelectableText(m.content,
                            style: TextStyle(
                                color: AppColors.paperTextPrimary, height: 1.6)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
