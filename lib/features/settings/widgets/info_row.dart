import 'package:flutter/material.dart';
import 'package:olivia_ank4/app/theme.dart';

/// 设置页键值行（标签 + 右侧胶囊值）。
/// 从 settings_page._infoRow 抽取，消除重复。
Widget infoRow(String label, String value) {
  return Row(
    children: [
      Text(label,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      const Spacer(),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.pillSelected,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(value,
            style: TextStyle(
                color: AppColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ),
    ],
  );
}
