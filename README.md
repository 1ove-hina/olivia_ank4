# Olivia 安可 4.0（olivia_ank4）

基于 Flutter 3.47.2 的 Windows 桌面端 AI 写信应用，内嵌 AI 人设「林离」。

## 环境要求

| 工具 | 版本 / 选项 |
|---|---|
| Git for Windows | 最新稳定版 |
| Flutter SDK | **3.47.2**（Dart `>=3.3.0 <4.0.0`） |
| Visual Studio 2022 | 工作负载「使用 C++ 的桌面开发」 |
| NSIS（可选） | 仅用于生成向导式安装 exe |

> 国内网络已预置 pub / flutter 镜像（`pub.flutter-io.cn`、`storage.flutter-io.cn`），镜像写入于 `.vscode/tasks.json` 的任务 env 中，构建时自动生效。

## 构建与打包

项目不依赖任何 `.bat`，构建由 VS Code 的 `.vscode/tasks.json` 定义（也可直接在终端跑 `flutter` 命令）。

**VS Code 方式**：`终端 ▸ 运行任务`，或 `Ctrl+Shift+B` 触发默认构建任务：

| 任务 | 作用 |
|---|---|
| `pub get` | 拉取依赖 |
| `build windows` | 构建 Release exe（默认构建任务） |
| `rebuild windows (clean)` | 先 `flutter clean` 再构建（重装 / 换机后用，避免旧 CMake 缓存路径冲突） |
| `build installer (msix)` | 生成 MSIX 侧载包 |
| `build installer (nsis)` | 生成向导式安装 exe（需本机装 NSIS） |
| `setup environment` | 启用 Windows 桌面目标 + `flutter doctor` 自检 |

**命令行方式**（需自行设置镜像，或先 `setx` 持久化，见 RECOVER_ENV.md）：

```bat
flutter pub get
flutter build windows --release     :: 产物 build\windows\x64\runner\Release\olivia_ank4.exe
flutter pub run msix:create          :: MSIX 侧载包
```

## 说明

- API key / baseUrl 由用户在应用内「设置页」填写，存于 `flutter_secure_storage`，不依赖 `.env` 或外部密钥文件。
- MSIX 默认自签名（本地侧载可装）；对外分发需自备代码签名证书并填入 `pubspec.yaml` 的 `msix_config.certificate_path`。
- 重装系统后的完整恢复流程见 `RECOVER_ENV.md`。
