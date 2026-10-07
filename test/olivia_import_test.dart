import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olivia_ank4/services/olivia_import_service.dart';

void main() {
  test('parseDir 从模拟缓存解析出信件', () async {
    final dir = await Directory.systemTemp.createTemp('olivia_cache_');
    try {
      final cache = Directory('${dir.path}/Cache')..createSync();
      final raw = 'garbage {"code":0,"message":"ok","data":{'
          '"letterId":"a2_abc","content":"用户来信",'
          '"sent":{"content":"用户来信","timestamp":1700000000000},'
          '"received":{"content":"林离回信","timestamp":1700000001000}}} more';
      File('${cache.path}/data_1').writeAsStringSync(raw);

      final letters = await OliviaImportService.parseDir(dir.path);
      expect(letters.length, 1);
      final ol = letters.first;
      expect(ol.id, 'a2_abc');
      expect(ol.userContent, '用户来信');
      expect(ol.aiContent, '林离回信');
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('parseDir 目录不存在返回空', () async {
    final letters =
        await OliviaImportService.parseDir('C:/no/such/dir/olivia_cache');
    expect(letters, isEmpty);
  });

  test('discoverOliviaDir 安全不抛（缺失环境变量时返回 null）', () {
    // 仅验证函数契约：要么返回路径字符串，要么返回 null，绝不抛异常。
    final result = OliviaImportService.discoverOliviaDir();
    expect(result, isA<String?>());
  });
}
