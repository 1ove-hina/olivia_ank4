# Olivia 安可 4.0 —— 安装包构建说明

本项目为 Flutter 3.47.2 Windows 桌面端。安装包有两种产出方式，任选其一：

## 方式 A：MSIX 侧载包（Flutter 官方 msix 插件，零额外依赖）

1. 已修复 `pubspec.yaml` 的 `msix_config`（`capabilities` 必须是逗号分隔字符串）。
2. 在项目根目录执行：
   ```bat
   flutter pub get
   flutter build windows --release
   flutter pub run msix:create
   ```
3. 产物：`build\windows\x64\runner\Release\*.msix`
4. 安装：右键 `.msix` →“安装”；首次因自签名会弹 SmartScreen 警告，点“仍要安装”即可（如需无警告，需用正式代码签名证书替换 `msix_config` 的 publisher 并签名）。

## 方式 B：向导式 .exe 安装程序（推荐给普通用户，体验最熟悉）

1. 本机安装 NSIS：https://nsis.sourceforge.io/ （安装后 `makensis` 加入 PATH）
2. 先编译 Release：`flutter build windows --release`
3. 在 `packaging\` 目录执行：
   ```bat
   makensis installer.nsi
   ```
4. 产物：`packaging\OliviaAnk4-Setup-4.0.2.2.exe`
   - 当前用户安装（写入 `%LOCALAPPDATA%\Programs\OliviaAnk4`），无需管理员权限
   - 自动创建「开始菜单」「桌面」快捷方式，并注册卸载项（控制面板可卸载）

## 一键构建（A + B）

项目根目录已提供 `build_installer.bat`，双击即按顺序完成：
`flutter pub get` → `flutter build windows --release` → `msix:create` →（若已装 NSIS）NSIS 向导包。

## 构建环境要求

- Flutter 3.47.2 + Dart 3.13.2（Windows）
- Visual Studio 2022「使用 C++ 的桌面开发」工作负载（编译 Windows runner 必需）
- 国内网络建议在 `build_installer.bat` 中启用镜像环境变量（脚本内已附注）

## 版本号对照

- 软件版本：4.0Beta1
- 内部版本：2008.2.2
- MSIX / 安装包版本号：`4.0.2.2`（`msix_version` 与 NSIS `DisplayVersion` 保持一致）

## 备注

- 免密启动（仅首次初始化输一次主密码，之后自动解锁）的代码已落地：
  `lib/services/credential_store.dart`、`lib/app/app_gate.dart`、
  `lib/features/setup/setup_screen.dart`、`lib/features/setup/unlock_screen.dart`、
  `lib/features/settings/settings_page.dart`、`lib/services/backup_service.dart`。
  请在可运行 `flutter analyze` / `flutter build` 的环境确认无编译错误后随包交付。
- 图标：`windows/runner/resources/app_icon.ico`（已就位，Windows runner 自动采用）；
  `assets/logo/logo.png` 用于 MSIX 磁贴图标。
