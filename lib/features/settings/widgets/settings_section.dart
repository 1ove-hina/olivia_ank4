import 'package:flutter/material.dart';
import 'package:olivia_ank4/app/theme.dart';

/// 设置页统一分区卡片：标题 + 副标题 + 自定义内容。
///
/// 替代 settings_page 中 8 个 section 各自重复的
/// `Container(padding:16, BoxDecoration(surfaceVariant, radius 12, divider))` 外壳，
/// 让各 section 只关注自身内容。
class SettingsSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  /// 标题行右侧组件（如开关）。非空时标题行变为 Row（文本 + trailing）。
  final Widget? trailing;

  const SettingsSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final Widget headerText = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(subtitle,
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 11)),
      ],
    );

    final header = trailing == null
        ? headerText
        : Row(
            children: [
              Expanded(child: headerText),
              trailing!,
            ],
          );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}
