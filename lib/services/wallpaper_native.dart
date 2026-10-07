import 'package:flutter/services.dart';

/// 动态桌面宿主能力（Windows WorkerW 注入 + 视频渲染）。
///
/// 宿主端由 windows/runner/wallpaper_engine.* 实现，并通过
/// MethodChannel('olivia/wallpaper') 暴露。非 Windows 平台或宿主未实现时，
/// 所有调用安全回落（不抛异常），保证设置页与 App 启动流程不被阻断。
class WallpaperNative {
  static const MethodChannel _ch = MethodChannel('olivia/wallpaper');

  /// 当前平台/宿主是否支持动态桌面（宿主需返回 true）。
  static Future<bool> get isSupported async {
    try {
      final r = await _ch.invokeMethod<bool>('isSupported');
      return r ?? false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 以指定视频文件设为动态桌面壁纸。
  /// 返回诊断字符串：空串 '' 表示成功；否则为失败原因
  /// （如 'no_workerw_parent' / 'renderfile_failed:0x...' / 'com_init_failed'）。
  /// 宿主未实现时回落为空串之外的安全值（这里返回 'host_unavailable'）。
  static Future<String> start(String filePath) async {
    try {
      final r = await _ch.invokeMethod<String>('start', {'path': filePath});
      return r ?? 'host_unavailable';
    } on PlatformException {
      return 'host_unavailable';
    } catch (_) {
      return 'host_unavailable';
    }
  }

  /// 停止动态桌面，恢复系统原壁纸。
  static Future<bool> stop() async {
    try {
      await _ch.invokeMethod<void>('stop');
      return true;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
