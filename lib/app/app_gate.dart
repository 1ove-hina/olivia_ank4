import 'package:flutter/material.dart';
import 'package:olivia_ank4/app/app_shell.dart';
import 'package:olivia_ank4/app/theme.dart';
import 'package:olivia_ank4/features/setup/setup_screen.dart';
import 'package:olivia_ank4/features/setup/unlock_screen.dart';
import 'package:olivia_ank4/services/credential_store.dart';
import 'package:olivia_ank4/services/crypto_service.dart';
import 'dart:async';
import 'package:olivia_ank4/services/settings_service.dart';
import 'package:olivia_ank4/services/wallpaper_service.dart';
import 'package:olivia_ank4/services/wallpaper_native.dart';
import 'package:olivia_ank4/services/wallpaper_music_service.dart';
import 'package:olivia_ank4/services/system_tray_service.dart';

/// 启动闸门：主密码**只在初始化时输入一次**，之后进入软件无需再输入。
/// - 首次运行（无 settings.enc）：进入初始化设置，设定主密码 + 可选 API 配置。
/// - 之后每次启动：用本机凭据（Windows DPAPI）里记住的主密码自动解锁，
///   直接进入主界面，不弹密码框。
/// - 仅当本机凭据缺失/失效（换设备、手动清除）时才要求补输一次，
///   成功后会记回凭据，下次继续免密。
/// 另一处仍需密码的场合是「转移数据」（导出/导入，见设置页 BackupService）。
class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

enum _GatePhase { loading, setup, unlock, ready }

class _AppGateState extends State<AppGate> {
  _GatePhase _phase = _GatePhase.loading;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final exists = await SettingsService.exists();
    if (!mounted) return;
    if (!exists) {
      // 首次运行：唯一一次要求设定主密码
      setState(() => _phase = _GatePhase.setup);
      return;
    }
    // 已初始化：优先用本机记住的主密码自动解锁，之后进入软件无需输入密码
    final saved = await CredentialStore.read();
    if (saved != null && saved.isNotEmpty) {
      final s = await SettingsService.load(saved);
      if (s != null) {
        // 密码正确 → 直接解锁会话进入主界面
        CryptoService.setSessionPassphrase(saved);
        // 应用已保存的主题
        themeModeController.set(parseThemeMode(s.themeMode));
        accentColorController.set(colorFromHex(s.accentColor));
        if (!mounted) return;
        setState(() => _phase = _GatePhase.ready);
        return;
      }
    }
    // 本机凭据缺失或已失效：补输一次，成功后会记回，下次继续免密
    if (!mounted) return;
    setState(() => _phase = _GatePhase.unlock);
  }

  Future<void> _onReady() async {
    // 初始化 / 解锁完成后，根据已加载的设置应用主题（两条路径都走这里）
    final p = CryptoService.sessionPassphrase;
    if (p != null && p.isNotEmpty) {
      final s = await SettingsService.load(p);
      if (s != null) {
        themeModeController.set(parseThemeMode(s.themeMode));
        accentColorController.set(colorFromHex(s.accentColor));
        // 系统栏最小化：按保存偏好初始化托盘（开启则图标出现在通知栏，
        // 之后最小化按钮收进系统栏；关闭(X)仍直接退出）。
        unawaited(SystemTrayService.instance.setEnabled(s.minimizeToTray));
      }
    }
    if (!mounted) return;
    setState(() => _phase = _GatePhase.ready);
    // 进入主界面后，按偏好自动套用动态桌面（失败静默，不阻断启动）
    unawaited(_applyWallpaperIfEnabled());
  }

  /// 若用户开启动态桌面且有已导入素材，则自动设为桌面壁纸
  Future<void> _applyWallpaperIfEnabled() async {
    final prefs = await WallpaperService.loadPrefs();
    if (!prefs.enabled) return;
    final now = DateTime.now();
    final path = await WallpaperService.resolveCurrent(
      now,
      variant: prefs.variant,
      take: prefs.take,
    );
    if (path == null) return;
    await WallpaperNative.start(path);
    // 壁纸播放时随机播放背景音乐（与壁纸生命周期绑定）
    if (prefs.musicEnabled) {
      unawaited(WallpaperMusicService.instance.start(dir: prefs.musicDir));
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _GatePhase.loading:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case _GatePhase.setup:
        return SetupScreen(onDone: _onReady);
      case _GatePhase.unlock:
        return UnlockScreen(onUnlocked: _onReady);
      case _GatePhase.ready:
        // 不能用 const：const 实例不会被重建，切换主题后侧边栏/播放栏
        // 拿不到新的 AppColors。这里每次返回新实例，主题变更即可随父级重建。
        return AppShell();
    }
  }
}
