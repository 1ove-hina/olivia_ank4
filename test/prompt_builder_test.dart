import 'package:flutter_test/flutter_test.dart';
import 'package:olivia_ank4/domain/models.dart';
import 'package:olivia_ank4/features/compose/prompt_builder.dart';

void main() {
  group('formatHM', () {
    test('补零到 HH:mm', () {
      expect(formatHM(DateTime(2024, 1, 1, 9, 5)), '09:05');
      expect(formatHM(DateTime(2024, 1, 1, 23, 59)), '23:59');
    });
  });

  group('buildAugmentedPrompt', () {
    const base = '你是林离';
    test('无记忆时原样返回', () {
      expect(buildAugmentedPrompt(base, []), base);
    });
    test('有记忆时拼接【记忆检索】块', () {
      final out = buildAugmentedPrompt(base, [
        MemoryChunk(
          id: 'm1',
          letterId: 'L1',
          text: '我们去过海边',
          createdAt: DateTime.now(),
        )
      ]);
      expect(out, contains('【记忆检索】'));
      expect(out, contains('1. 我们去过海边'));
    });
  });

  group('appendLettersToPrompt', () {
    final letter = Letter(
      id: 'L1',
      title: '问候',
      personaId: 'linli',
      messages: [
        Message(role: 'user', content: '你好', createdAt: DateTime.now()),
        Message(role: 'assistant', content: '你好呀', createdAt: DateTime.now()),
      ],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    test('无信件时原样返回', () {
      expect(appendLettersToPrompt('base', []), 'base');
    });
    test('拼接【往来信件参考】并提取双方内容', () {
      final out = appendLettersToPrompt('base', [letter]);
      expect(out, contains('【往来信件参考】'));
      expect(out, contains('来信：你好'));
      expect(out, contains('林离回信：你好呀'));
    });
  });
}
