import 'package:flutter/material.dart';
import 'package:olivia_ank4/app/theme.dart';
import 'package:olivia_ank4/domain/memory_state.dart';
import 'package:olivia_ank4/domain/models.dart';
import 'package:olivia_ank4/domain/persona_state.dart';
import 'package:olivia_ank4/features/library/library_page.dart';
import 'package:olivia_ank4/features/mailbox/mailbox_page.dart';
import 'package:olivia_ank4/features/review/review_page.dart';
import 'package:olivia_ank4/features/settings/settings_page.dart';
import 'package:olivia_ank4/features/user/user_page.dart';
import 'package:olivia_ank4/services/birthday_service.dart';
import 'package:olivia_ank4/services/memory_service.dart';
import 'package:olivia_ank4/services/pending_reply_service.dart';
import 'package:olivia_ank4/services/persona_service.dart';

enum AppPage { user, library, mailbox, review, settings }

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 2; // 默认进入「信箱」

  // 不能用 static const 缓存页面实例：const 实例每次取到的是同一个对象，
  // Flutter 会认为 widget 未变化而跳过重建，切换主题后各页读不到新的 AppColors。
  // 这里改为每次 build 生成新实例（State 仍会保留，因为 canUpdate 成立）。
  List<Widget> get _pages => [
        UserPage(),
        LibraryPage(),
        MailboxPage(),
        ReviewPage(),
        SettingsPage(),
      ];

  @override
  void initState() {
    super.initState();
    _initPersona();
    _initMemory();
    // 启动延迟收信监视器：解锁后即检查，覆盖软件关闭期间已到期的回信
    PendingReplyWatcher.instance.start();
    // 生日系统：若今天是用户生日，林离主动写一封生日信到信箱
    BirthdayService.checkAndSend().then((letter) {
      if (letter != null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('🎂 林离给你写了一封生日信，去信箱看看吧'),
            ),
          );
        });
      }
    });
  }

  /// 启动即读取本地记忆库条数，驱动底部面板显示
  Future<void> _initMemory() async {
    try {
      final all = await MemoryService.loadAll();
      memoryState.setCount(all.length);
    } catch (_) {
      memoryState.setCount(0);
    }
  }

  /// 应用启动即从 bundled 资源 + 本地配置装载当前生效人设
  Future<void> _initPersona() async {
    try {
      final builtin = await PersonaService.loadDefault();
      final cfg = await PersonaService.loadConfig();
      final persona = Persona(
        id: cfg.selectedPersonaId,
        name: builtin.name,
        source: cfg.customPrompt != null ? PersonaSource.custom : PersonaSource.builtin,
        systemPrompt: cfg.customPrompt ?? builtin.systemPrompt,
        createdAt: builtin.createdAt,
      );
      activePersona.set(cfg, persona);
    } catch (_) {
      // 资源未就绪时保留默认占位（人设：林离）
    }
  }

  @override
  Widget build(BuildContext context) {
    // 每帧只生成一次页面列表，避免 _pages 取值重复构造
    final pages = _pages;
    return Scaffold(
      body: Row(
        children: [
          _buildNavRail(),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      for (int i = 0; i < pages.length; i++)
                        Offstage(
                          offstage: i != _selectedIndex,
                          child: _AnimatedEnter(
                            key: i == _selectedIndex
                                ? ValueKey<int>(_selectedIndex)
                                : null,
                            child: pages[i],
                          ),
                        ),
                    ],
                  ),
                ),
                // 不用 const：同上，主题切换时播放栏需要重建以读新的 AppColors
                _BottomPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavRail() {
    return Container(
      width: 92,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(right: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        children: [
          _navButton(0, Icons.person_outline, '用户'),
          const SizedBox(height: 12),
          _navButton(1, Icons.library_music_outlined, '曲库'),
          const SizedBox(height: 12),
          _navButton(2, Icons.mail_outline, '信箱'),
          const SizedBox(height: 12),
          _navButton(3, Icons.insights_outlined, '回顾'),
          const Spacer(),
          _navButton(4, Icons.settings_outlined, '设置'),
        ],
      ),
    );
  }

  Widget _navButton(int index, IconData icon, String label) {
    final selected = _selectedIndex == index;
    final color = selected ? Colors.black87 : AppColors.textSecondary;
    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.pillSelected : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部面板：状态/上下文栏（P0 占位，后续承载播放控制 / 当前人设 / 记忆状态）
class _BottomPanel extends StatelessWidget {
  const _BottomPanel();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([activePersona, memoryState]),
      builder: (_, __) {
        final name = activePersona.persona?.name ?? '林离';
        final custom = activePersona.config.customPrompt != null;
        return Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_outlined, size: 16, color: AppColors.accent),
          const SizedBox(width: 8),
          Text(
              '人设：$name${custom ? '（自定义）' : ''} · 记忆：${memoryState.count} 条',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const Spacer(),
          Text('播放/状态栏 · 待开发',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
        );
      },
    );
  }
}

/// 界面切换时的入场过渡：淡入 + 轻微横向位移。
/// 通过 [key] 变化（切换选中页时）重新触发动画；[child] 始终复用同一页面实例，
/// 配合外层 [Offstage] 保证未显示页保持挂载（不丢草稿/滚动位置等状态）。
class _AnimatedEnter extends StatefulWidget {
  final Widget child;
  const _AnimatedEnter({super.key, required this.child});

  @override
  State<_AnimatedEnter> createState() => _AnimatedEnterState();
}

class _AnimatedEnterState extends State<_AnimatedEnter> {
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: 1),
      child: widget.child,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset((1 - v) * 18, 0),
          child: child,
        ),
      ),
    );
  }
}
