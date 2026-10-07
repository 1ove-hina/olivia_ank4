import 'package:flutter/foundation.dart';
import 'package:olivia_ank4/domain/models.dart';
import 'package:olivia_ank4/domain/persona_config.dart';

/// 当前生效人设的内存态（P2 轻量状态中心，未引入 Riverpod）
///
/// 写信页头、设置页、底部面板都从这里读取当前人设；
/// 人设编辑器保存后调用 [set] 通知所有监听者刷新。
class ActivePersonaState extends ChangeNotifier {
  PersonaConfig _config = const PersonaConfig();
  Persona? _persona;

  PersonaConfig get config => _config;
  Persona? get persona => _persona;

  void set(PersonaConfig config, Persona persona) {
    _config = config;
    _persona = persona;
    notifyListeners();
  }
}

/// 全局单例，应用启动时由 [AppShell] 初始化
final activePersona = ActivePersonaState();
