import 'package:flutter/material.dart';
import 'package:olivia_ank4/app/theme.dart';

/// 设置页统一输入框：标签 + 文本框。
/// 从 settings_page._field 抽取，消除重复。
Widget settingsField(
  String label,
  TextEditingController c, {
  String hint = '',
  bool obscure = false,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      const SizedBox(height: 6),
      TextField(
        controller: c,
        obscureText: obscure,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AppColors.textSecondary),
          filled: true,
          fillColor: AppColors.inputBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.divider),
          ),
        ),
        style: TextStyle(color: AppColors.textPrimary),
      ),
    ],
  );
}
