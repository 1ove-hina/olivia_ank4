import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:olivia_ank4/domain/models.dart';
import 'package:olivia_ank4/domain/persona_config.dart';
import 'package:path_provider/path_provider.dart';

/// 人设服务（P2）
/// - loadDefault：从 bundled 资源 assets/personas/林离.md 读取并生成 Persona
/// - loadConfig/saveConfig：人设选择 + 自定义提示词（明文 JSON，非敏感，免主密码可用）
class PersonaService {
  static const String _assetPath = 'assets/personas/林离.md';
  static const String _fileName = 'persona.json';

  static Future<String> _path() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/$_fileName';
  }

  /// 读取内置「林离」人设，生成可用 systemPrompt
  static Future<Persona> loadDefault() async {
    final md = await rootBundle.loadString(_assetPath);
    return _fromMarkdown(md);
  }

  static Persona _fromMarkdown(String md) {
    const name = '林离';
    final prompt = _buildSystemPrompt(name, md);
    return Persona(
      id: 'linli',
      name: name,
      source: PersonaSource.builtin,
      systemPrompt: prompt,
      createdAt: DateTime(2026, 8, 29),
    );
  }

  /// 内置人设文件（assets/personas/林离.md）本身即完整、自洽的 system prompt，
  /// 直接作为 system 角色内容使用，不再额外包裹壳，避免重复/矛盾指令。
  static String _buildSystemPrompt(String name, String md) {
    return md;
  }

  static Future<PersonaConfig> loadConfig() async {
    final f = File(await _path());
    if (!f.existsSync()) return const PersonaConfig();
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return PersonaConfig.fromJson(j);
    } catch (_) {
      return const PersonaConfig();
    }
  }

  static Future<void> saveConfig(PersonaConfig c) async {
    final f = File(await _path());
    await f.writeAsString(jsonEncode(c.toJson()));
  }
}
