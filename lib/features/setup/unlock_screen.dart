import 'package:flutter/material.dart';
import 'package:olivia_ank4/app/theme.dart';
import 'package:olivia_ank4/services/credential_store.dart';
import 'package:olivia_ank4/services/crypto_service.dart';
import 'package:olivia_ank4/services/settings_service.dart';

/// 兜底解锁屏：仅在**本机凭据缺失或失效**时出现（例如换设备、手动清除过凭据）。
/// 正常启动会自动解锁，不会走到这里；输入一次成功后会记回本机凭据，下次继续免密。
class UnlockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const UnlockScreen({super.key, required this.onUnlocked});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _pass = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final p = _pass.text;
    if (p.isEmpty) {
      setState(() => _error = '请输入主密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final s = await SettingsService.load(p);
    if (!mounted) return;
    if (s == null) {
      setState(() {
        _busy = false;
        _error = '主密码错误';
      });
      return;
    }
    CryptoService.setSessionPassphrase(p);
    // 记回本机凭据，之后启动免密（仅此一次需要输入）
    await CredentialStore.save(p);
    widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_open_outlined,
                  size: 36, color: AppColors.accent),
              const SizedBox(height: 12),
              Text('解锁 Olivia-安可',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('本机未记住主密码（换设备或手动清除过）。'
                  '输入一次后会自动记住，下次启动无需再输入。',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextField(
                controller: _pass,
                obscureText: true,
                autofocus: true,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: '主密码',
                  hintStyle:
                      TextStyle(color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.inputBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: AppColors.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: AppColors.divider),
                  ),
                ),
                style: TextStyle(color: AppColors.textPrimary),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onAccent,
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('解锁'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
