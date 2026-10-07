import 'package:flutter/material.dart';
import 'package:olivia_ank4/app/theme.dart';
import 'package:olivia_ank4/app/app_info.dart';
import 'package:olivia_ank4/services/system_tray_service.dart';
import 'package:window_manager/window_manager.dart';

/// 自定义窗口栏：隐藏系统标题栏后，由软件自绘顶部栏。
/// - 左侧为可拖拽区（显示软件名），右侧为 最小化 / 最大化 / 关闭 按钮。
/// 用法：包在 App 根（home）外层，使 初始化 / 解锁 / 主界面 都带统一窗口栏。
class WindowChrome extends StatelessWidget {
  final Widget child;
  const WindowChrome({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _titleBar(),
        Expanded(child: child),
      ],
    );
  }

  Widget _titleBar() {
    return Container(
      height: 38,
      color: AppColors.background,
      child: Row(
        children: [
          // 拖拽区（显示软件名）
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              child: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 14),
                child: Text(
                  '${AppInfo.appName} · ${AppInfo.marketingVersion}',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ),
          _WindowButton(
            icon: Icons.remove,
            onPressed: () async {
              // 开启「最小化到系统栏」且托盘已激活时，收进通知栏后台运行；
              // 否则保持普通最小化（落到任务栏）。
              if (SystemTrayService.instance.isTrayActive) {
                await SystemTrayService.instance.minimizeToTray();
              } else {
                await windowManager.minimize();
              }
            },
          ),
          _WindowButton(
            icon: Icons.crop_square,
            onPressed: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
          _WindowButton(
            icon: Icons.close,
            hoverColor: Colors.white,
            hoverBg: const Color(0xFFE5484D),
            onPressed: () => windowManager.close(),
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  // 悬停配色默认为主题色（主题可切换，故不能在默认值里写死 AppColors），
  // 因此改为可空并在 build 里用 ?? 回落到当前主题色。
  final Color? hoverColor;
  final Color? hoverBg;
  const _WindowButton({
    required this.icon,
    required this.onPressed,
    this.hoverColor,
    this.hoverBg,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: 38,
          color: _hover
              ? (widget.hoverBg ?? AppColors.surfaceVariant)
              : Colors.transparent,
          child: Icon(
            widget.icon,
            size: 16,
            color: _hover
                ? (widget.hoverColor ?? AppColors.textPrimary)
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
