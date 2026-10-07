import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olivia_ank4/features/user/user_page.dart';

void main() {
  group('UserPage', () {
    test('can be constructed', () {
      expect(const UserPage(), isA<Widget>());
    });
  });
}
