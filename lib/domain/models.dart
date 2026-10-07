/// 领域模型（P0 占位骨架，P2/P4/P6 将填充完整行为与持久化）

/// 人设：内置「林离」或用户自定义
class Persona {
  final String id;
  final String name;
  final PersonaSource source;
  final String systemPrompt; // 由人设文件生成
  final String? personality; // 性格规则
  final String? speechStyle; // 语言风格
  final String? forbidden; // 禁忌边界
  final String? preferences; // 偏好
  final DateTime createdAt;

  const Persona({
    required this.id,
    required this.name,
    required this.source,
    required this.systemPrompt,
    this.personality,
    this.speechStyle,
    this.forbidden,
    this.preferences,
    required this.createdAt,
  });
}

enum PersonaSource { builtin, custom }

/// 一封信（含多轮消息）
class Letter {
  final String id;
  final String title;
  final String personaId;
  final List<Message> messages;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Letter({
    required this.id,
    required this.title,
    required this.personaId,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'personaId': personaId,
        'messages': messages.map((m) => m.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Letter.fromJson(Map<String, dynamic> j) => Letter(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        personaId: j['personaId'] as String? ?? 'linli',
        messages: (j['messages'] as List? ?? [])
            .map((e) => Message.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
      );
}

class Message {
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime createdAt;

  const Message({
    required this.role,
    required this.content,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        role: j['role'] as String? ?? 'user',
        content: j['content'] as String? ?? '',
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

/// 记忆片段：信件切块后的可检索单元（P4 注入向量）
class MemoryChunk {
  final String id;
  final String letterId;
  final String text;
  final List<double>? vector; // 云端 embedding，本地存储
  final DateTime createdAt;

  const MemoryChunk({
    required this.id,
    required this.letterId,
    required this.text,
    this.vector,
    required this.createdAt,
  });
}
