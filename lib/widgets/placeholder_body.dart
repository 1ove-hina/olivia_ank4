import 'package:flutter/material.dart';
import 'package:olivia_ank4/app/theme.dart';

/// 通用占位页（P0 用，后续页面接入后移除）
class PlaceholderBody extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const PlaceholderBody({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: AppColors.textSecondary),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(fontSize: 20, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}
