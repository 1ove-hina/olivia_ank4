import 'package:flutter/material.dart';
import 'package:olivia_ank4/app/theme.dart';
import 'package:olivia_ank4/domain/settings.dart';
import 'package:olivia_ank4/services/credential_store.dart';
import 'package:olivia_ank4/services/crypto_service.dart';
import 'package:olivia_ank4/services/settings_service.dart';

/// 首次运行初始化屏：设定主密码（必填，用于加密全部本地数据），
/// 并可一并填入 API 配置（也可稍后在设置中补）。完成后解锁整个会话。
/// 这是**唯一一次**要求设定主密码的场合：设定后会记入本机凭据，
/// 之后每次启动自动解锁，无需再输入。
class SetupScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SetupScreen({super.key, required this.onDone});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  final _baseUrl = TextEditingController();
  final _apiKey = TextEditingController();
  final _chatModel = TextEditingController();
  final _embeddingModel = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _chatModel.dispose();
    _embeddingModel.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final p = _pass.text;
    if (p.isEmpty) {
      setState(() => _error = '请设置主密码');
      return;
    }
    if (p != _confirm.text) {
      setState(() => _error = '两次输入的密码不一致');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final settings = AppSettings(
      baseUrl: _baseUrl.text.trim(),
      apiKey: _apiKey.text.trim(),
      chatModel: _chatModel.text.trim(),
      embeddingModel: _embeddingModel.text.trim(),
    );
    await SettingsService.save(settings, p);
    // 记入本机凭据（Windows DPAPI）：之后启动自动解锁，无需再次输入密码
    await CredentialStore.save(p);
    CryptoService.setSessionPassphrase(p);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          width: 420,
          constraints: const BoxConstraints(maxHeight: 640),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome_outlined,
                    size: 32, color: AppColors.accent),
                const SizedBox(height: 10),
                Text('初始化 Olivia-安可',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('设置主密码以加密本地数据。该密码仅此设置一次，'
                    '之后启动自动解锁、无需再输入；仅在「转移数据」时需要。'
                    '请务必牢记（换设备需同一主密码解密）。',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 18),
                _field('主密码', _pass, obscure: true),
                const SizedBox(height: 12),
                _field('确认主密码', _confirm, obscure: true),
                const SizedBox(height: 18),
                Divider(color: AppColors.divider),
                const SizedBox(height: 6),
                Text('API 配置（可稍后在设置中填写）',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 12),
                _field('API Base URL', _baseUrl,
                    hint: 'https://api.deepseek.com/v1'),
                const SizedBox(height: 12),
                _field('API Key', _apiKey, hint: 'sk-...', obscure: true),
                const SizedBox(height: 12),
                _field('Chat Model', _chatModel, hint: 'deepseek-chat'),
                const SizedBox(height: 12),
                _field('Embedding Model', _embeddingModel,
                    hint: 'deepseek-embedding'),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 12)),
                ],
                const SizedBox(height: 18),
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
                        : const Text('设置并进入'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
      {String hint = '', bool obscure = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                TextStyle(color: AppColors.textSecondary),
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
}
