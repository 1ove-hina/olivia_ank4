# 重装系统后环境恢复指南

适用场景：Windows 重装后源码已恢复到项目目录，但 Flutter / Dart / Git / VS 工具链归零。
构建由 VS Code 的 `.vscode/tasks.json` 驱动，无需任何 `.bat`。

## 一、安装工具（按顺序）

1. **Git for Windows**（确保 `git` 在 PATH）
2. **Flutter SDK 3.47.2**（解压到 `C:\flutter`，把 `C:\flutter\bin` 加入 PATH）
3. **Visual Studio 2022**，工作负载勾选「使用 C++ 的桌面开发」
4. **NSIS**（可选，仅用于向导式安装 exe）

> Flutter 版本务必用 **3.47.2**：升/降大版本可能导致 `window_manager`、`tray_manager`、`just_audio_windows` 等插件不兼容。

## 二、一键初始化

装完上面三步后，在 VS Code 里 `终端 ▸ 运行任务 ▸ setup environment`，自动完成：

- `flutter config --enable-windows-desktop` 启用桌面目标
- `flutter doctor` 自检工具链

镜像已在 `tasks.json` 的任务 env 中设置，构建时自动生效，无需手动配置。
如需让镜像在**任意**终端都生效（不只在 VS Code 任务里），在 cmd 执行一次：

```bat
setx PUB_HOSTED_URL "https://pub.flutter-io.cn"
setx FLUTTER_STORAGE_BASE_URL "https://storage.flutter-io.cn"
```

## 三、验证

```bat
flutter doctor -v
:: 应见 [√] Visual Studio（Desktop development with C++）、[√] Windows 桌面开发已启用

:: VS Code：终端 ▸ 运行任务 ▸ build windows
:: 或命令行：
flutter build windows --release     :: 产物 build\windows\x64\runner\Release\olivia_ank4.exe
```

出包（MSIX 侧载包 / NSIS 向导 exe）：运行对应的 `build installer` 任务，或 `flutter pub run msix:create`。

## 四、要点

- **不缺密钥/配置文件**：API key 与 baseUrl 来自应用内设置页，无 `.env` / 证书文件被忽略。
- **旧 `build/` 必须清**：重装 / 换机后用 `rebuild windows (clean)` 任务（先 `flutter clean`）即可避免旧 CMake 缓存路径冲突；也可手动 `flutter clean`。
- **镜像变量统一**为 `PUB_HOSTED_URL`（写入 `tasks.json` 任务 env）。
- **网络仍不通**：可改用清华镜像 `https://mirrors.tuna.tsinghua.edu.cn/dart-pub` 与 `https://mirrors.tuna.tsinghua.edu.cn/flutter`（同步改 `tasks.json` 的 env 与上面 `setx`）。
