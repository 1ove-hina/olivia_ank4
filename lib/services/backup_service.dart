import 'dart:convert';
import 'dart:io';
import 'package:olivia_ank4/services/crypto_service.dart';
import 'package:path_provider/path_provider.dart';

/// 数据转移（备份/恢复）服务：把本地加密数据打包为单个文件，便于跨设备迁移。
/// 这是除「启动解锁」外唯一需要再次输入主密码的场合（见设置页调用）。
class BackupService {
  static const List<String> _files = [
    'settings.enc',
    'letters.json',
    'memory.json',
    'pending_replies.json', // 延迟收信队列：一并转移，避免导入后待投递回信丢失
  ];

  static Future<String> _supportDir() async {
    final d = await getApplicationSupportDirectory();
    return d.path;
  }

  static Future<String> _documentsDir() async {
    final d = await getApplicationDocumentsDirectory();
    return d.path;
  }

  /// 导出：把三个（可能存在的）加密文件打包为单个 .ank4backup。
  /// 文件内容本身仍由主密码加密，转移后需用同一主密码解密。
  /// 返回生成的备份文件路径（位于「文档」目录）。
  static Future<String> exportBackup(String pass) async {
    final support = await _supportDir();
    final files = <String, String>{};
    for (final n in _files) {
      final f = File('$support/$n');
      if (f.existsSync()) {
        files[n] = base64Encode(await f.readAsBytes());
      }
    }
    final payload = jsonEncode({'version': 1, 'files': files});
    final outDir = await _documentsDir();
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final outPath = '$outDir/olivia-ank4-backup-$ts.ank4backup';
    await File(outPath).writeAsString(payload);
    return outPath;
  }

  /// 导入：从 .ank4backup 还原加密文件，并以该主密码解锁当前会话。
  /// 调用方需先验证主密码正确（见设置页 showMasterPassDialog）。
  static Future<void> importBackup(String pass, String filePath) async {
    final content = await File(filePath).readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;
    final files = (data['files'] as Map<String, dynamic>? ?? {});
    final support = await _supportDir();
    files.forEach((name, b64) {
      final bytes = base64Decode(b64 as String);
      File('$support/$name').writeAsBytesSync(bytes);
    });
    CryptoService.setSessionPassphrase(pass);
  }
}
