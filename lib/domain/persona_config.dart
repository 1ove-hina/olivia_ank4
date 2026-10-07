/// 人设配置（P2）：当前选中的人设 + 可选的系统提示词覆盖
class PersonaConfig {
  final String selectedPersonaId;
  final String? customPrompt; // 为 null 时使用内置人设的默认 systemPrompt

  const PersonaConfig({
    this.selectedPersonaId = 'linli',
    this.customPrompt,
  });

  Map<String, dynamic> toJson() => {
        'selectedPersonaId': selectedPersonaId,
        'customPrompt': customPrompt,
      };

  factory PersonaConfig.fromJson(Map<String, dynamic> json) => PersonaConfig(
        selectedPersonaId: json['selectedPersonaId'] as String? ?? 'linli',
        customPrompt: json['customPrompt'] as String?,
      );

  static const PersonaConfig empty = PersonaConfig();
}
