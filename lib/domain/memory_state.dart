import 'package:flutter/foundation.dart';

/// 本地记忆库的内存态（P4 轻量状态中心，与 activePersona 同模式）
///
/// 写信页新增/检索记忆后刷新 [_count]，底部面板据此显示「记忆：N 条」。
class MemoryState extends ChangeNotifier {
  int _count = 0;
  bool _ready = false;

  int get count => _count;
  bool get ready => _ready;

  void setCount(int c) {
    _count = c;
    _ready = true;
    notifyListeners();
  }
}

/// 全局单例，应用启动及每次记忆变更后更新
final memoryState = MemoryState();
