import 'package:flutter/material.dart';
import 'package:olivia_ank4/app/theme.dart';
import 'package:olivia_ank4/services/crypto_service.dart';
import 'package:olivia_ank4/services/settings_service.dart';

/// 主密码解锁弹窗（P3）：写信页等场合需要读取加密的 API 配置时使用。
/// 返回解锁成功的主密码字符串，取消或失败返回 null。
Future<String?> showMasterPassDialog(BuildContext context) async {
  final ctrl = TextEditingController();
  final error = ValueNotifier<String?>(null);

  final result = await showDialog<String?>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('解锁主密码',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('输入主密码以读取 API 配置。',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              onSubmitted: (_) => _submit(ctx, ctrl.text, error),
              decoration: InputDecoration(
                hintText: '主密码',
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
            ValueListenableBuilder<String?>(
              valueListenable: error,
              builder: (_, e, __) => e == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(e,
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 12)),
                    ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text('取消',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.black87,
            ),
            onPressed: () => _submit(ctx, ctrl.text, error),
            child: const Text('解锁'),
          ),
        ],
      ),
    ),
  );

  ctrl.dispose();
  return result;
}

/// 便捷封装：已解锁（会话内有主密码）则直接返回 true，否则弹窗要求解锁。
/// 用于写信 / 信箱 / 记忆等需要读取或写入加密数据的场合（P6）。
Future<bool> ensureUnlocked(BuildContext context) async {
  if (CryptoService.sessionPassphrase != null) return true;
  final pass = await showMasterPassDialog(context);
  return pass != null && pass.isNotEmpty;
}

Future<void> _submit(
    BuildContext ctx, String pass, ValueNotifier<String?> error) async {
  if (pass.isEmpty) {
    error.value = '请输入主密码';
    return;
  }
  final s = await SettingsService.load(pass);
  if (s == null) {
    error.value = '主密码错误';
    return;
  }
  CryptoService.setSessionPassphrase(pass);
  if (ctx.mounted) Navigator.of(ctx).pop(pass);
}
