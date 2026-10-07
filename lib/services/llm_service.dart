import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:olivia_ank4/domain/settings.dart';

/// LLM 调用服务（P3）：OpenAI 兼容的 chat/completions
///
/// - 由 [AppSettings] 提供 baseUrl / apiKey / chatModel
/// - systemPrompt 取生效人设（林离或自定义），userLetter 为来信正文
/// - 返回模型文本回复；失败抛 [Exception]（含 HTTP 状态/错误信息）
class LLMService {
  /// 发起一次非流式对话补全
  static Future<String> chat({
    required AppSettings settings,
    required String systemPrompt,
    required String userLetter,
    http.Client? client,
  }) async {
    final base = settings.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final url = Uri.parse('$base/chat/completions');
    final c = client ?? http.Client();
    try {
      final resp = await c
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${settings.apiKey.trim()}',
            },
            body: jsonEncode({
              'model': settings.chatModel.trim().isEmpty
                  ? 'deepseek-chat'
                  : settings.chatModel.trim(),
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': userLetter},
              ],
              'temperature': 0.9,
              'stream': false,
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        throw Exception('响应中无 choices：${resp.body}');
      }
      final message = choices[0]['message'] as Map<String, dynamic>;
      final content = message['content'];
      if (content is! String) {
        throw Exception('回复内容格式异常：${resp.body}');
      }
      return content.trim();
    } finally {
      if (client == null) c.close();
    }
  }
}
