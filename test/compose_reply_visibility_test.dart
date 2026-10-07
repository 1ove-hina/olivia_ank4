import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olivia_ank4/domain/models.dart';
import 'package:olivia_ank4/features/compose/compose_page.dart';

/// 写信页布局规则：**只有回信送达后才显示「林离的回信」区**；
/// 没有回信（全新写信、或已寄出但尚未送达）时，只显示「来信草稿」并独占整宽。
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Letter letterWith({required bool replied}) {
    final t = DateTime(2026, 9, 17, 10, 0);
    return Letter(
      id: 'letter-1',
      title: '你好呀',
      personaId: 'linli',
      messages: [
        Message(role: 'user', content: '你好呀，今天过得怎么样？', createdAt: t),
        if (replied)
          Message(
              role: 'assistant',
              content: '亲爱的：\n\n见字如面。今天很好，想你。',
              createdAt: t.add(const Duration(minutes: 30))),
      ],
      createdAt: t,
      updatedAt: t,
    );
  }

  group('ComposePage 回信区显示时机', () {
    testWidgets('全新写信：只显示来信草稿，不出现林离的回信区', (tester) async {
      await tester.pumpWidget(wrap(ComposePage(onClose: () {})));
      await tester.pumpAndSettle();

      expect(find.text('来信草稿'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      // 关键：回信区（含其占位文案）完全不存在
      expect(find.text('林离的回信'), findsNothing);
      expect(find.textContaining('林离的回信将显示在这里'), findsNothing);
    });

    testWidgets('已寄出但回信尚未送达：仍然只显示草稿区', (tester) async {
      await tester
          .pumpWidget(wrap(ComposePage(letter: letterWith(replied: false), onClose: () {})));
      await tester.pumpAndSettle();

      expect(find.text('来信草稿'), findsOneWidget);
      expect(find.text('林离的回信'), findsNothing);
    });

    testWidgets('回信已送达：草稿区与回信区并排出现，回信正文可见', (tester) async {
      await tester
          .pumpWidget(wrap(ComposePage(letter: letterWith(replied: true), onClose: () {})));
      await tester.pumpAndSettle();

      expect(find.text('来信草稿'), findsOneWidget);
      expect(find.text('林离的回信'), findsOneWidget);
      expect(find.textContaining('见字如面'), findsOneWidget);
    });
  });
}
