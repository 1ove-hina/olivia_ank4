/// 应用版本信息（集中维护，便于设置页与窗口标题等处复用）。
///
/// 单一权威来源约定：
///   - pubspec.yaml 的 `version: <semver>+<build>` 为唯一规范来源，须为三段式 semver（如 4.0.3）+ 构建号；
///   - 本文件的 [version] 取 semver 部分、[buildNumber] 取 build 部分，须与之一致；
///   - Windows 侧的 msix_config.msix_version 与 packaging/installer.nsi 的 VERSION 须为四段式（如 4.0.3.0），
///     由 semver 后补 `.0` 修订号得到，二者同源；
///   - [marketingVersion] 仅用于窗口标题等对外展示，可独立于规范号演进。
class AppInfo {
  static const String appName = 'Olivia 安可';
  static const String appNameCn = '林离的来信';

  /// 对外展示的营销版本号（窗口标题用，可独立于规范号）
  static const String marketingVersion = '4.0Beta3';

  /// 规范版本号（单一来源：与 pubspec.yaml `version` 的三段式 semver 一致）
  static const String version = '4.0.3';

  /// 内部构建号（与 pubspec.yaml `version` 的 +build 部分一致）
  static const String buildNumber = '2008.2.5';
}