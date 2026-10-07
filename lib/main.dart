import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'package:olivia_ank4/app/app_gate.dart';
import 'package:olivia_ank4/app/theme.dart';
import 'package:olivia_ank4/app/window_chrome.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  // 窗口就绪后隐藏系统标题栏（由 WindowChrome 自绘），并设置尺寸/最小尺寸与居中。
  // 不能用 const：backgroundColor 取自可随主题切换的 AppColors（非编译期常量）
  final windowOptions = WindowOptions(
    size: Size(1280, 720),
    minimumSize: Size(900, 600),
    center: true,
    backgroundColor: AppColors.background,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(const OliviaApp());
}

class OliviaApp extends StatelessWidget {
  const OliviaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([themeModeController, accentColorController]),
      builder: (context, _) => MaterialApp(
        title: 'Olivia-安可 4.0',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeModeController.mode,
        // 中文本地化：DatePicker / 各种 Material 文案需要 MaterialLocalizations 祖先。
        // 未声明时传入 Locale('zh','CN') 会报 "No MaterialLocalizations found"。
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('zh', 'CN'),
          Locale('en', 'US'),
        ],
        // 注意：这里**不能**用 const。const 实例会被规范化（canonicalized），
        // Flutter 判定 widget 相等时直接跳过重建，导致切换主题后 WindowChrome
        // 不会重新执行 build，窗口栏读不到新的 AppColors（主题不生效）。
        home: WindowChrome(child: AppGate()),
      ),
    );
  }
}
      