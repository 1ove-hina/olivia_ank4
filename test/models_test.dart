import 'package:flutter_test/flutter_test.dart';
import 'package:olivia_ank4/domain/models.dart';
import 'package:olivia_ank4/services/olivia_import_service.dart';
import 'package:olivia_ank4/services/pending_reply_service.dart';

void main() {
  group('Message', () {
    test('fromJson/toJson roundtrip', () {
      final m = Message(
        role: 'assistant',
        content: 'hi',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      final m2 = Message.fromJson(m.toJson());
      expect(m2.role, 'assistant');
      expect(m2.content, 'hi');
      expect(m2.createdAt.millisecondsSinceEpoch, 1000);
    });
  });

  group('Letter', () {
    test('fromJson/toJson roundtrip', () {
      final letter = Letter(
        id: 'L1',
        title: 't',
        personaId: 'linli',
        messages: [
          Message(role: 'user', content: 'u', createdAt: DateTime.now())
        ],
        createdAt: DateTime.fromMillisecondsSinceEpoch(1),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
      );
      final l2 = Letter.fromJson(letter.toJson());
      expect(l2.id, 'L1');
      expect(l2.messages.length, 1);
    });
  });

  group('PendingReply', () {
    final p = PendingReply(
      id: 'abc',
      letterId: 'L1',
      draft: 'd',
      reply: 'r',
      createdAt: 100,
      dueAt: 200,
    );
    test('fromJson/toJson roundtrip', () {
      final p2 = PendingReply.fromJson(p.toJson());
      expect(p2.id, 'abc');
      expect(p2.dueAt, 200);
      expect(p2.dueTime.millisecondsSinceEpoch, 200);
    });
  });

  group('OliviaLetter', () {
    test('title 取首行非空并截断到 40 字 + …', () {
      final longFirstLine =
          '这是一封非常长的来信标题用来测试截断逻辑是否生效一共需要超过四十个中文字符才能看到省略号的效果';
      final ol = OliviaLetter(
        id: 'a2_x',
        // 前两行是空行，验证「取首行非空」会跳过；超长内容放在首行触发截断
        userContent: '\n\n$longFirstLine\n短的第二行',
        aiContent: '回信',
        createdMs: 1000,
        updatedMs: 2000,
      );
      final t = ol.title;
      expect(t.startsWith('这是一封'), isTrue);
      expect(t.endsWith('…'), isTrue);
      expect(t.length, 41); // 40 + '…'
    });

    test('toLetter 生成 user + assistant 消息', () {
      final ol = OliviaLetter(
        id: 'a2_x',
        userContent: 'hi',
        aiContent: 'hello',
        createdMs: 1000,
        updatedMs: 2000,
      );
      final letter = ol.toLetter();
      expect(letter.personaId, 'linli');
      expect(letter.messages.length, 2);
      expect(letter.messages.first.role, 'user');
      expect(letter.messages.last.role, 'assistant');
    });
  });
}
