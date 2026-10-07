import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// 系统栏（通知栏 / 托盘）最小化功能。
///
/// 行为（设置项「最小化到系统栏」控制，默认开启）：
/// - 最小化(_) 按钮：把窗口收进通知栏后台运行（windowManager.hide），
///   之后从托盘图标双击/单击「打开主界面」恢复；应用不退出，壁纸/音乐继续。
/// - 关闭(X) 按钮：仍直接退出（见 window_chrome），与托盘菜单「退出」一致。
///
/// 实现要点：tray_manager 是 Flutter 桌面插件（Windows 原生，无需外部下载）。
/// 托盘图标由 CMake 在构建时把 windows/runner/resources/app_icon.ico
/// 复制为 exe 同目录的 tray_icon.ico，这里用 Platform.resolvedExecutable
/// 拼出绝对路径，避免在 debug/release 不同工作目录下解析失败。
class SystemTrayService with TrayListener {
  SystemTrayService._();
  static final SystemTrayService instance = SystemTrayService._();

  bool _enabled = false; // 开关是否开启（来自设置）
  bool _trayActive = false; // 托盘图标是否已在通知栏

  /// 当前开关状态（供最小化按钮判断）。
  bool get enabled => _enabled;

  /// 托盘当前是否激活（图标在通知栏）。仅激活时最小化才收进系统栏。
  bool get isTrayActive => _trayActive;

  /// 应用开关状态：开启→初始化托盘；关闭→销毁托盘图标。
  /// 幂等：状态未变则不重复操作。
  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled && (_trayActive == enabled)) return;
    _enabled = enabled;
    if (enabled) {
      await _activateTray();
    } else {
      await _destroyTray();
    }
  }

  Future<void> _activateTray() async {
    if (_trayActive) return;
    trayManager.addListener(this);
    try {
      await trayManager.setIcon(_iconPath());
      await trayManager.setToolTip('$_appName · 后台运行中');
      final menu = Menu(items: [
        MenuItem(key: 'show_window', label: '打开主界面'),
        MenuItem.separator(),
        MenuItem(key: 'exit_app', label: '退出'),
      ]);
      await trayManager.setContextMenu(menu);
      _trayActive = true;
    } catch (_) {
      // 图标缺失/加载失败等：不阻断启动，最小化退回普通最小化。
      trayManager.removeListener(this);
    }
  }

  Future<void> _destroyTray() async {
    if (!_trayActive) return;
    trayManager.removeListener(this);
    try {
      await trayManager.destroy();
    } catch (_) {}
    _trayActive = false;
  }

  String _iconPath() {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    return p.join(exeDir, 'tray_icon.ico');
  }

  String get _appName => 'Olivia-安可 4.0';

  /// 最小化按钮调用：收进系统栏（隐藏窗口，后台继续运行）。
  /// 若托盘未激活（理论上不会发生，因为 enabled 时即激活），退回普通最小化。
  Future<void> minimizeToTray() async {
    if (!_trayActive) {
      await windowManager.minimize();
      return;
    }
    await windowManager.hide();
  }

  /// 从托盘恢复窗口并置顶聚焦。
  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  /// 从托盘菜单真正退出（与关闭(X)行为一致：直接退出）。
  Future<void> exitApp() async {
    await windowManager.close();
  }

  // —— TrayListener ——

  @override
  void onTrayIconMouseDown() {
    // 左键单击：直接恢复主界面（更直观）。
    showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    // 右键：弹出上下文菜单（打开主界面 / 退出）。
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconRightMouseUp() {}

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') {
      showWindow();
    } else if (menuItem.key == 'exit_app') {
      exitApp();
    }
  }
}
