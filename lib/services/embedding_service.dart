import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:olivia_ank4/domain/settings.dart';

/// 云端 Embedding 服务（P4，OpenAI 兼容的 /embeddings）
///
/// 复用 [AppSettings] 的 baseUrl / apiKey / embeddingModel（与 chat 同一 Key）。
/// - [embed]：单条文本 → 向量
/// - [embedBatch]：多条文本一次性批量 → 向量列表（减少请求次数）
/// 失败抛 [Exception]（含 HTTP 状态/错误信息）。
class EmbeddingService {
  /// 单条文本转向量
  static Future<List<double>> embed({
    required AppSettings settings,
    required String text,
    http.Client? client,
  }) async {
    final list = await embedBatch(settings: settings, texts: [text], client: client);
    return list.first;
  }

  /// 批量文本转向量（OpenAI 格式：input 可为字符串数组）
  static Future<List<List<double>>> embedBatch({
    required AppSettings settings,
    required List<String> texts,
    http.Client? client,
  }) async {
    if (settings.apiKey.trim().isEmpty) {
      throw Exception('未配置 API Key，无法调用 Embedding');
    }
    final model = settings.embeddingModel.trim();
    if (model.isEmpty) {
      throw Exception('未配置 Embedding 模型，请在「设置」中填写 embeddingModel');
    }
    final base = settings.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final url = Uri.parse('$base/embeddings');
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
              'model': model,
              'input': texts,
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (resp.statusCode != 200) {
        throw Exception('Embedding HTTP ${resp.statusCode}: ${resp.body}');
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final dList = data['data'] as List<dynamic>?;
      if (dList == null || dList.isEmpty) {
        throw Exception('Embedding 响应中无 data：${resp.body}');
      }
      // 按 index 排序后取 embedding（兼容乱序返回）
      final byIndex = <int, List<double>>{};
      for (final item in dList) {
        final idx = (item['index'] as int?) ?? 0;
        final emb = item['embedding'];
        if (emb is! List) throw Exception('embedding 格式异常：${resp.body}');
        byIndex[idx] = emb.map((e) => (e as num).toDouble()).toList();
      }
      final result = <List<double>>[];
      for (var i = 0; i < texts.length; i++) {
        final v = byIndex[i];
        if (v == null) throw Exception('Embedding 缺失第 $i 条结果');
        result.add(v);
      }
      return result;
    } finally {
      if (client == null) c.close();
    }
  }
}
