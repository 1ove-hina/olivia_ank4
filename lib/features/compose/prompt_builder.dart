import 'package:olivia_ank4/domain/models.dart';

/// 写信页的 prompt 拼装逻辑（纯函数，便于单测）。
/// 从 compose_page 抽取，消除大文件内的方法膨胀。

/// 把时间格式化为 HH:mm
String formatHM(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// 根据 base + 检索到的记忆块拼出增强版 system prompt
String buildAugmentedPrompt(String base, List<MemoryChunk> mem) {
  if (mem.isEmpty) return base;
  final sb = StringBuffer(base);
  sb.writeln('\n\n---');
  sb.writeln('【记忆检索】以下是从过往通信中提取、与本次来信可能相关的片段，'
      '仅供你把握语气与上下文参考。请自然融入林离的口吻，不要生硬复述，'
      '也不要向对方暴露你在使用外部记忆系统：');
  for (var i = 0; i < mem.length; i++) {
    sb.writeln('${i + 1}. ${mem[i].text}');
  }
  return sb.toString();
}

/// 把最近几封往来信件全文拼进 system prompt 作为背景参考（无 Embedding 时的回退方案）。
/// [letters] 已按更新时间倒序，取最近的若干封；排除当前正在编辑的信件以避免自引用。
String appendLettersToPrompt(String base, List<Letter> letters) {
  if (letters.isEmpty) return base;
  final sb = StringBuffer(base);
  sb.writeln('\n\n---');
  sb.writeln('【往来信件参考】以下是此前写给林离的几封信及林离的回信，'
      '供你把握双方关系、语气与未竟之事的上下文。请自然延续林离的口吻，'
      '不要生硬复述，也不要向对方暴露你在使用外部信件参考：');
  for (var i = 0; i < letters.length; i++) {
    final l = letters[i];
    final userMsg = l.messages
            .where((m) => m.role == 'user')
            .firstOrNull
            ?.content ??
        '';
    final aiMsg = l.messages
            .where((m) => m.role == 'assistant')
            .firstOrNull
            ?.content ??
        '';
    sb.writeln('\n信件${i + 1}（${l.title}）：');
    if (userMsg.isNotEmpty) sb.writeln('来信：$userMsg');
    if (aiMsg.isNotEmpty) sb.writeln('林离回信：$aiMsg');
  }
  return sb.toString();
}
