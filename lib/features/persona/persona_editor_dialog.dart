import 'package:flutter/material.dart';
import 'package:olivia_ank4/app/theme.dart';
import 'package:olivia_ank4/domain/models.dart';
import 'package:olivia_ank4/domain/persona_config.dart';
import 'package:olivia_ank4/domain/persona_state.dart';
import 'package:olivia_ank4/services/persona_service.dart';

/// 人设编辑器（P2）：在「内置林离」与「自定义提示词」之间切换，并可编辑系统提示词。
/// 保存时写入 persona.json（明文，非敏感），并刷新全局 [activePersona]。
class PersonaEditorDialog extends StatefulWidget {
  const PersonaEditorDialog({super.key});

  @override
  State<PersonaEditorDialog> createState() => _PersonaEditorDialogState();
}

class _PersonaEditorDialogState extends State<PersonaEditorDialog> {
  Persona? _builtin;
  bool _custom = false;
  final _prompt = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final builtin = await PersonaService.loadDefault();
    final cfg = await PersonaService.loadConfig();
    _builtin = builtin;
    _custom = cfg.customPrompt != null;
    _prompt.text = cfg.customPrompt ?? builtin.systemPrompt;
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final config = PersonaConfig(
      selectedPersonaId: _custom ? 'custom' : 'linli',
      customPrompt: _custom ? _prompt.text.trim() : null,
    );
    await PersonaService.saveConfig(config);

    final b = _builtin!;
    final persona = Persona(
      id: config.selectedPersonaId,
      name: b.name,
      source: _custom ? PersonaSource.custom : PersonaSource.builtin,
      systemPrompt: config.customPrompt ?? b.systemPrompt,
      personality: b.personality,
      speechStyle: b.speechStyle,
      forbidden: b.forbidden,
      preferences: b.preferences,
      createdAt: b.createdAt,
    );
    activePersona.set(config, persona);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return AlertDialog(
        backgroundColor: AppColors.surface,
        content: SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final name = _builtin!.name;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('人设设置 · $name',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
      content: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('内置人设')),
                ButtonSegment(value: true, label: Text('自定义提示词')),
              ],
              selected: {_custom},
              onSelectionChanged: (s) => setState(() => _custom = s.first),
              style: ButtonStyle(
                foregroundColor:
                    WidgetStateProperty.all(AppColors.textPrimary),
              ),
            ),
            const SizedBox(height: 14),
            if (!_custom)
              Text(
                '当前使用内置「林离」人设，系统提示词由 bundled 人设文件生成，不可编辑。'
                '切换到「自定义提示词」可自由改写。',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 12),
              )
            else
              SizedBox(
                height: 360,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.inputBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    controller: _prompt,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: '在此编辑系统提示词…',
                      hintStyle:
                          TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 13, height: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('取消',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.onAccent,
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
