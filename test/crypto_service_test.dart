import 'package:flutter_test/flutter_test.dart';
import 'package:olivia_ank4/services/crypto_service.dart';

void main() {
  group('CryptoService.encryptJson / decryptJson', () {
    const pass = 'correct horse battery staple';
    final payload = <String, dynamic>{
      'title': '林离的来信',
      'n': 42,
      'list': [1, 2, 3],
      'nested': {'a': 'b'},
    };

    test('roundtrip 还原原值', () {
      final blob = CryptoService.encryptJson(payload, pass);
      final out = CryptoService.decryptJson(blob, pass);
      expect(out, isNotNull);
      expect(out!['title'], '林离的来信');
      expect(out['n'], 42);
      expect(out['list'], [1, 2, 3]);
    });

    test('错误密码返回 null', () {
      final blob = CryptoService.encryptJson(payload, pass);
      expect(CryptoService.decryptJson(blob, 'wrong'), isNull);
    });

    test('密文被篡改返回 null', () {
      final blob = CryptoService.encryptJson(payload, pass);
      final codeUnits = blob.codeUnits.toList();
      codeUnits[codeUnits.length - 1] ^= 0x01; // 翻转末字节
      final tampered = String.fromCharCodes(codeUnits);
      expect(CryptoService.decryptJson(tampered, pass), isNull);
    });

    test('相同明文+密码每次密文不同（随机 salt/iv）', () {
      final a = CryptoService.encryptJson(payload, pass);
      final b = CryptoService.encryptJson(payload, pass);
      expect(a, isNot(b));
    });
  });

  group('CryptoService.encryptString / decryptString', () {
    const pass = 'p@ss';
    const plain = '用户来信内容 🌿';

    test('roundtrip', () {
      final blob = CryptoService.encryptString(plain, pass);
      expect(CryptoService.decryptString(blob, pass), plain);
    });

    test('错误密码返回 null', () {
      final blob = CryptoService.encryptString(plain, pass);
      expect(CryptoService.decryptString(blob, 'x'), isNull);
    });
  });
}
