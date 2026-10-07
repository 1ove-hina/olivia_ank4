import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:olivia_ank4/app/theme.dart';
import 'package:olivia_ank4/domain/persona_state.dart';
import 'package:olivia_ank4/domain/settings.dart';
import 'package:olivia_ank4/features/persona/persona_editor_dialog.dart';
import 'package:olivia_ank4/services/backup_service.dart';
import 'package:olivia_ank4/services/credential_store.dart';
import 'package:olivia_ank4/services/crypto_service.dart';
import 'package:olivia_ank4/services/olivia_import_service.dart';
import 'package:olivia_ank4/app/app_info.dart';
import 'package:olivia_ank4/services/settings_service.dart';
import 'package:olivia_ank4/services/wallpaper_service.dart';
import 'package:olivia_ank4/services/wallpaper_native.dart';
import 'package:olivia_ank4/services/wallpaper_music_service.dart';
import 'package:olivia_ank4/services/system_tray_service.dart';
import 'package:file_selector/file_selector.dart';
import 'package:olivia_ank4/widgets/master_pass_dialog.dart';
import 'package:olivia_ank4/features/settings/widgets/settings_field.dart';
import 'package:olivia_ank4/features/settings/widgets/info_row.dart';
import 'package:olivia_ank4/features/settings/widgets/settings_section.dart';
import 'package:olivia_ank4/features/settings/widgets/color_wheel_picker.dart';

/// 设置页（P1，主密码加密持久化）
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _baseUrl = TextEditingController();
  final _apiKey = TextEditingController();
  final _chatModel = TextEditingController();
  final _embeddingModel = TextEditingController();
  bool _importing = false;
  String _themeMode = 'dark'; // Beta2：跟随系统/浅色/深色
  Color? _accentColor; // Beta3：自定义主题色（无极轮盘），null 表示用默认主题色

  // —— 窗口与系统栏（Beta2）——
  bool _trayMinimize = true; // 最小化到系统栏，默认开启

  // —— 动态桌面（Beta2）——
  bool _wpEnabled = false;
  String _wpVariant = 'random';
  String _wpTake = 'random';
  String _wpSource = WallpaperService.defaultSourceDir;
  int _wpFound = 0;
  bool _wpSupported = false;
  String? _wpPreview; // 当前将播放的视频完整路径（外部自定义目录）
  final _wpSourceCtrl =
      TextEditingController(text: WallpaperService.defaultSourceDir);

  // —— 壁纸背景音乐（Beta2）——
  bool _musicEnabled = true;
  String _musicDir = WallpaperService.defaultMusicDir;
  int _musicFound = 0;
  final _musicDirCtrl =
      TextEditingController(text: WallpaperService.defaultMusicDir);

  // 主密码解锁已由启动时 AppGate 统一处理，本页不再单独弹密码框。
  @override
  void initState() {
    super.initState();
    final p = CryptoService.sessionPassphrase;
    if (p != null && p.isNotEmpty) _load(p);
    _loadWallpaperPrefs();
  }

  Future<void> _load(String passphrase) async {
    final s = await SettingsService.load(passphrase);
    if (!mounted) return;
    if (s == null) return; // 异常路径：保持默认值，不弹密码框
    _baseUrl.text = s.baseUrl;
    _apiKey.text = s.apiKey;
    _chatModel.text = s.chatModel;
    _embeddingModel.text = s.embeddingModel;
    _themeMode = s.themeMode;
    _trayMinimize = s.minimizeToTray;
    // 自定义主题色：解析并立即应用（空串 => 默认主题色）
    _accentColor = colorFromHex(s.accentColor);
    accentColorController.set(_accentColor);
    if (mounted) setState(() {});
  }

  /// 动态桌面：加载偏好、刷新支持状态与预览
  Future<void> _loadWallpaperPrefs() async {
    _wpSupported = await WallpaperNative.isSupported;
    final prefs = await WallpaperService.loadPrefs();
    if (!mounted) return;
    _wpEnabled = prefs.enabled;
    _wpVariant = prefs.variant;
    _wpTake = prefs.take;
    _wpSource = prefs.source;
    _wpSourceCtrl.text = prefs.source;
    _wpFound = await WallpaperService.countInSource(_wpSource);
    _musicEnabled = prefs.musicEnabled;
    _musicDir = prefs.musicDir;
    _musicDirCtrl.text = prefs.musicDir;
    _musicFound = await WallpaperMusicService.countIn(_musicDir);
    await _refreshPreview();
  }

  Future<void> _refreshPreview() async {
    final path = await WallpaperService.resolveCurrent(
      DateTime.now(),
      variant: _wpVariant,
      take: _wpTake,
      sourceDir: _wpSource,
    );
    if (!mounted) return;
    _wpPreview = path; // 完整路径（外部自定义目录），_applyWallpaper 直接用它
    if (mounted) setState(() {});
  }

  Future<void> _saveWallpaperPrefs() async {
    await WallpaperService.savePrefs(WallpaperPrefs(
      enabled: _wpEnabled,
      variant: _wpVariant,
      take: _wpTake,
      source: _wpSource,
      musicEnabled: _musicEnabled,
      musicDir: _musicDir,
    ));
  }

  Future<void> _onWallpaperEnabled(bool v) async {
    if (!mounted) return;
    setState(() => _wpEnabled = v);
    await _saveWallpaperPrefs();
    if (v) {
      await _applyWallpaper();
    } else {
      await WallpaperNative.stop();
      unawaited(WallpaperMusicService.instance.stop()); // 壁纸停→音乐停
    }
  }

  Future<void> _applyWallpaper() async {
    // 基于当前 _wpSource（可能刚手动输入）重新解析并持久化，确保外部目录生效
    await _saveWallpaperPrefs();
    await _refreshPreview();
    if (_wpPreview == null) {
      _toast('尚未找到可播放的素材视频');
      return;
    }
    // 直接用外部自定义目录的完整路径调用宿主设壁纸；宿主回传诊断串（空串=成功）
    final diag = await WallpaperNative.start(_wpPreview!);
    if (!mounted) return;
    // 宿主成功时回传 "ok sp=0/1"（sp=SetParent 是否成功）；失败回传 decode_failed
    // / createwindow_failed 等诊断串。统一把 "ok" 前缀视为成功。
    if (diag.isEmpty || diag.startsWith('ok')) {
      _toast('已应用动态桌面 [$diag]');
      // 壁纸已应用：随机播放背景音乐（与壁纸生命周期绑定）
      if (_musicEnabled) {
        unawaited(WallpaperMusicService.instance.start(dir: _musicDir));
      }
    } else if (diag.startsWith('no_decoder:')) {
      final codec = diag.substring('no_decoder:'.length);
      _toast('动态桌面失败：系统缺少 $codec 解码器。'
          '请安装「HEVC 视频扩展」，或把素材转码为 H.264 后重试');
    } else {
      _toast('动态桌面失败：$diag');
    }
  }

  /// 用系统文件夹选择器挑选「外部自定义」壁纸素材目录
  Future<void> _pickSourceDir() async {
    final picked = await getDirectoryPath(
      initialDirectory: _wpSource.isNotEmpty ? _wpSource : null,
      confirmButtonText: '选择此目录',
    );
    if (picked == null || !mounted) return;
    setState(() => _wpSource = picked);
    _wpSourceCtrl.text = picked;
    await _saveWallpaperPrefs();
    _wpFound = await WallpaperService.countInSource(picked);
    await _refreshPreview();
    if (mounted) setState(() {});
  }

  /// 壁纸背景音乐开关：开启且壁纸已启用→随机播放；关闭→停止音乐。
  Future<void> _onMusicEnabled(bool v) async {
    if (!mounted) return;
    setState(() => _musicEnabled = v);
    await _saveWallpaperPrefs();
    if (v) {
      if (_wpEnabled) {
        unawaited(WallpaperMusicService.instance.start(dir: _musicDir));
      }
    } else {
      unawaited(WallpaperMusicService.instance.stop());
    }
  }

  /// 用系统文件夹选择器挑选背景音乐目录
  Future<void> _pickMusicDir() async {
    final picked = await getDirectoryPath(
      initialDirectory: _musicDir.isNotEmpty ? _musicDir : null,
      confirmButtonText: '选择此目录',
    );
    if (picked == null || !mounted) return;
    setState(() => _musicDir = picked);
    _musicDirCtrl.text = picked;
    await _saveWallpaperPrefs();
    _musicFound = await WallpaperMusicService.countIn(picked);
    if (mounted) setState(() {});
  }

  /// 立即（重新）应用背景音乐：停掉当前曲，从最新目录随机播放。
  Future<void> _applyMusic() async {
    if (!_musicEnabled) {
      _toast('请先开启「壁纸背景音乐」');
      return;
    }
    await WallpaperMusicService.instance.stop();
    unawaited(WallpaperMusicService.instance.start(dir: _musicDir));
    _toast('已应用背景音乐（$_musicFound 个音频随机循环）');
  }

  AppSettings _current() => AppSettings(
        baseUrl: _baseUrl.text.trim(),
        apiKey: _apiKey.text.trim(),
        chatModel: _chatModel.text.trim(),
        embeddingModel: _embeddingModel.text.trim(),
        themeMode: _themeMode,
        minimizeToTray: _trayMinimize,
        accentColor: _accentColor == null ? '' : colorToHex(_accentColor!),
      );

  /// 外观：切换主题并立即生效、持久化
  Future<void> _onThemeChanged(String mode) async {
    if (!mounted) return;
    setState(() => _themeMode = mode);
    themeModeController.set(parseThemeMode(mode));
    final p = CryptoService.sessionPassphrase;
    if (p != null && p.isNotEmpty) {
      await SettingsService.save(_current(), p);
    }
  }

  /// 外观 - 无极轮盘：拖动时即时预览（改全局控制器，不落盘）
  void _onAccentChanged(Color c) {
    if (!mounted) return;
    setState(() => _accentColor = c);
    accentColorController.set(c);
  }

  /// 持久化当前主题色（松手 / 确定后调用）
  Future<void> _persistAccent() async {
    final p = CryptoService.sessionPassphrase;
    if (p != null && p.isNotEmpty) {
      await SettingsService.save(_current(), p);
    }
  }

  /// 打开无极轮盘调色弹窗：拖动即时预览全应用配色，确定落盘，取消还原。
  Future<void> _openColorWheel() async {
    final original = _accentColor; // 用于「取消」还原
    var current = _accentColor ?? AppColors.accent;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('无极调色', style: TextStyle(color: AppColors.textPrimary)),
          content: SizedBox(
            width: 300,
            child: ColorWheelPicker(
              value: current,
              onChanged: (c) {
                current = c;
                _onAccentChanged(c); // 全应用即时预览
                setLocal(() {}); // 刷新弹窗内的预览与滑条
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('取消', style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('确定', style: TextStyle(color: AppColors.accent)),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await _persistAccent();
      _toast('已应用自定义主题色');
    } else {
      // 取消：还原到打开前的主题色
      if (!mounted) return;
      setState(() => _accentColor = original);
      accentColorController.set(original);
    }
  }

  /// 恢复默认主题色
  Future<void> _resetAccent() async {
    if (!mounted) return;
    setState(() => _accentColor = null);
    accentColorController.set(null);
    await _persistAccent();
    _toast('已恢复默认主题色');
  }

  /// 窗口与系统栏：切换「最小化到系统栏」——实时启停托盘并持久化
  Future<void> _onTrayMinimizeChanged(bool v) async {
    if (!mounted) return;
    setState(() => _trayMinimize = v);
    // 立即启停托盘（图标出现/消失），无需重启
    await SystemTrayService.instance.setEnabled(v);
    final p = CryptoService.sessionPassphrase;
    if (p != null && p.isNotEmpty) {
      await SettingsService.save(_current(), p);
    }
  }

  Widget _personaSection() {
    return AnimatedBuilder(
      animation: activePersona,
      builder: (_, __) {
        final name = activePersona.persona?.name ?? '林离';
        final custom = activePersona.config.customPrompt != null;
        return SettingsSection(
          title: '人设：$name${custom ? '（自定义提示词）' : '（内置）'}',
          subtitle: '写信时以该人设口吻回复；可切换或自定义系统提示词。',
          trailing: TextButton.icon(
            onPressed: _editPersona,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('编辑'),
            style: TextButton.styleFrom(foregroundColor: AppColors.accent),
          ),
          children: const [],
        );
      },
    );
  }

  Future<void> _editPersona() async {
    await showDialog(
        context: context, builder: (_) => const PersonaEditorDialog());
    if (mounted) setState(() {});
  }

  Widget _appearanceSection() {
    return SettingsSection(
      title: '外观',
      subtitle: '切换界面明暗主题；「跟随系统」将随操作系统设置变化。',
      children: [
        SegmentedButton<String>(
          selected: {_themeMode},
          onSelectionChanged: (set) => _onThemeChanged(set.first),
          style: SegmentedButton.styleFrom(
            selectedForegroundColor: AppColors.onAccent,
            selectedBackgroundColor: AppColors.accent,
          ),
          segments: const [
            ButtonSegment(
                value: 'system',
                label: Text('跟随系统'),
                icon: Icon(Icons.brightness_auto, size: 18)),
            ButtonSegment(
                value: 'light',
                label: Text('浅色'),
                icon: Icon(Icons.light_mode, size: 18)),
            ButtonSegment(
                value: 'dark',
                label: Text('深色'),
                icon: Icon(Icons.dark_mode, size: 18)),
          ],
        ),
        const SizedBox(height: 16),
        Divider(color: AppColors.divider, height: 1),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('主题色',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text('无极轮盘连续取色，拖动时全应用实时预览。',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.divider),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _accentColor == null ? '默认' : colorToHex(_accentColor!),
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _openColorWheel,
              icon: const Icon(Icons.palette_outlined, size: 16),
              label: const Text('无极调色'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.divider),
                foregroundColor: AppColors.accent,
              ),
            ),
            const SizedBox(width: 8),
            if (_accentColor != null)
              TextButton(
                onPressed: _resetAccent,
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary),
                child: const Text('恢复默认色彩'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _windowSection() {
    return SettingsSection(
      title: '窗口与系统栏',
      subtitle: '开启后，点击最小化(_) 把窗口收进通知栏后台运行（壁纸/音乐继续）；'
          '从托盘图标恢复，或右键「退出」。关闭(X) 始终直接退出。',
      children: [
        Row(
          children: [
            Expanded(
              child: Text('最小化到系统栏',
                  style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 13)),
            ),
            Switch(
              value: _trayMinimize,
              onChanged: (v) => _onTrayMinimizeChanged(v),
              activeThumbColor: AppColors.accent,
            ),
          ],
        ),
      ],
    );
  }

  Widget _wallpaperSection() {
    final now = DateTime.now();
    return SettingsSection(
      title: '动态桌面（Beta2）',
      subtitle:
          '按本地时段播放林离动态场景视频（需 Windows 实体机；当前平台${_wpSupported ? '已支持' : '暂不支持'}）。',
      trailing: Switch(
        value: _wpEnabled,
        onChanged: (v) => _onWallpaperEnabled(v),
        activeThumbColor: AppColors.accent,
      ),
      children: [
          infoRow('当前时段', WallpaperService.slotLabelFor(now)),
          const SizedBox(height: 8),
          infoRow('将播放',
              _wpPreview != null ? _wpPreview!.split(RegExp(r'[\\/]')).last : '（素材目录未找到匹配视频）'),
          const SizedBox(height: 14),
          Text('变体（A / B / C）',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            selected: {_wpVariant},
            onSelectionChanged: (set) async {
              if (!mounted) return;
              setState(() => _wpVariant = set.first);
              await _saveWallpaperPrefs();
              await _refreshPreview();
              if (_wpEnabled) await _applyWallpaper();
            },
            style: SegmentedButton.styleFrom(
              selectedForegroundColor: AppColors.onAccent,
              selectedBackgroundColor: AppColors.accent,
            ),
            segments: const [
              ButtonSegment(value: 'random', label: Text('随机')),
              ButtonSegment(value: 'A', label: Text('A')),
              ButtonSegment(value: 'B', label: Text('B')),
              ButtonSegment(value: 'C', label: Text('C')),
            ],
          ),
          const SizedBox(height: 12),
          Text('镜头（R1 / R2 / R3）',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            selected: {_wpTake},
            onSelectionChanged: (set) async {
              if (!mounted) return;
              setState(() => _wpTake = set.first);
              await _saveWallpaperPrefs();
              await _refreshPreview();
              if (_wpEnabled) await _applyWallpaper();
            },
            style: SegmentedButton.styleFrom(
              selectedForegroundColor: AppColors.onAccent,
              selectedBackgroundColor: AppColors.accent,
            ),
            segments: const [
              ButtonSegment(value: 'random', label: Text('随机')),
              ButtonSegment(value: 'R1', label: Text('R1')),
              ButtonSegment(value: 'R2', label: Text('R2')),
              ButtonSegment(value: 'R3', label: Text('R3')),
            ],
          ),
          const SizedBox(height: 14),
          Text('素材来源目录（外部自定义，可直接选任意含 mp4 的文件夹）',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
          TextField(
            controller: _wpSourceCtrl,
            onChanged: (v) => _wpSource = v.trim(),
            decoration: InputDecoration(
              hintText: WallpaperService.defaultSourceDir,
              hintStyle:
                  TextStyle(color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.inputBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.divider),
              ),
            ),
            style: TextStyle(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickSourceDir,
                  icon: const Icon(Icons.folder_open_outlined, size: 16),
                  label: const Text('选择目录'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: BorderSide(color: AppColors.divider),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _applyWallpaper(),
                  icon: const Icon(Icons.play_arrow_outlined, size: 16),
                  label: const Text('立即应用'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('在素材目录找到 $_wpFound 个视频（直接读取外部目录，无需导入）。',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
          Divider(height: 22, color: AppColors.divider),
          Row(
            children: [
              Expanded(
                child: Text('壁纸背景音乐',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
              Switch(
                value: _musicEnabled,
                onChanged: (v) => _onMusicEnabled(v),
                activeThumbColor: AppColors.accent,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('壁纸播放时，从下方目录随机循环播放本地音频（mp3/wav/flac/m4a…）。',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
          const SizedBox(height: 10),
          TextField(
            controller: _musicDirCtrl,
            onChanged: (v) => _musicDir = v.trim(),
            decoration: InputDecoration(
              hintText: WallpaperService.defaultMusicDir,
              hintStyle:
                  TextStyle(color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.inputBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.divider),
              ),
            ),
            style: TextStyle(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickMusicDir,
                  icon: const Icon(Icons.folder_open_outlined, size: 16),
                  label: const Text('选择目录'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: BorderSide(color: AppColors.divider),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _applyMusic(),
                  icon: const Icon(Icons.music_note_outlined, size: 16),
                  label: const Text('立即应用'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('在音乐目录找到 $_musicFound 个音频（随机循环播放）。',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
        ],
    );
  }

  Future<void> _save() async {
    await SettingsService.save(_current(), CryptoService.sessionPassphrase!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已保存（主密码加密）'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _export() {
    final json =
        const JsonEncoder.withIndent('  ').convert(_current().toJson());
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('导出配置（明文）',
            style: TextStyle(color: AppColors.textPrimary)),
        content: SingleChildScrollView(
          child: SelectableText(json,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('关闭', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  /// 导出数据备份：再次要求主密码（转移数据的唯一密码入口之一）
  Future<void> _exportBackup() async {
    final pass = await showMasterPassDialog(context);
    if (pass == null) return;
    final s = await SettingsService.load(pass);
    if (s == null) {
      _toast('主密码错误');
      return;
    }
    try {
      final path = await BackupService.exportBackup(pass);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('备份已导出',
              style: TextStyle(color: AppColors.textPrimary)),
          content: SelectableText(
              '已生成加密备份文件（内容仍由主密码保护）：\n\n$path\n\n'
              '将其复制到另一台设备后，用「导入备份」+ 同一主密码即可恢复全部信件与记忆。',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('知道了',
                  style: TextStyle(color: AppColors.accent)),
            ),
          ],
        ),
      );
    } catch (e) {
      _toast('导出失败：$e');
    }
  }

  /// 导入数据备份：再次要求主密码，并粘贴 .ank4backup 文件路径
  Future<void> _importBackup() async {
    final pass = await showMasterPassDialog(context);
    if (pass == null) return;
    final s = await SettingsService.load(pass);
    if (s == null) {
      _toast('主密码错误');
      return;
    }
    final pathCtrl = TextEditingController();
    final path = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('导入备份',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('粘贴 .ank4backup 文件的完整路径：',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: pathCtrl,
              decoration: InputDecoration(
                hintText: 'C:\\...\\olivia-ank4-backup-....ank4backup',
                hintStyle:
                    TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.inputBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.divider),
                ),
              ),
              style: TextStyle(color: AppColors.textPrimary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text('取消',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(pathCtrl.text.trim()),
            child: Text('导入',
                style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    pathCtrl.dispose();
    if (path == null || path.isEmpty) return;
    try {
      await BackupService.importBackup(pass, path);
      // 导入后生效的主密码可能变化，同步更新本机凭据，保证下次启动仍自动解锁
      await CredentialStore.save(pass);
      if (!mounted) return;
      _toast('导入成功，请重新进入信箱/记忆查看');
    } catch (e) {
      _toast('导入失败：$e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _chatModel.dispose();
    _embeddingModel.dispose();
    _wpSourceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildForm();
  }

  Widget _transferSection() {
    return SettingsSection(
      title: '转移数据',
      subtitle: '跨设备迁移时再次输入主密码，把信件与记忆打包为加密备份。',
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _exportBackup,
                icon: const Icon(Icons.file_upload_outlined, size: 16),
                label: const Text('导出备份'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: BorderSide(color: AppColors.divider),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _importBackup,
                icon: const Icon(Icons.file_download_outlined, size: 16),
                label: const Text('导入备份'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: BorderSide(color: AppColors.divider),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _oliviaImportSection() {
    return SettingsSection(
      title: '从 Olivia 原版导入',
      subtitle: '自动扫描 Olivia 本地缓存中的信件，解析后并入信箱（沿用当前主密码加密）。',
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _importing ? null : _importFromOlivia,
            icon: _importing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.move_to_inbox_outlined, size: 16),
            label: Text(_importing ? '正在导入…' : '导入 Olivia 原版信件'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: BorderSide(color: AppColors.divider),
            ),
          ),
        ),
      ],
    );
  }

  /// 从 Olivia 原版导入：先让用户确认/修正数据目录，再解析并入信箱
  Future<void> _importFromOlivia() async {
    final detected = OliviaImportService.discoverOliviaDir() ?? '';
    final ctrl = TextEditingController(text: detected);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('从 Olivia 原版导入信件',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '将扫描 Olivia 的本地缓存（HTTP 缓存中的信件 API 响应）并解析并入信箱。'
                '若自动路径不正确，可手动指定 Olivia 数据目录：',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              decoration: InputDecoration(
                hintText: r'C:\...\AppData\Roaming\miHoYo\Olivia-steam',
                hintStyle:
                    TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.inputBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.divider),
                ),
              ),
              style: TextStyle(color: AppColors.textPrimary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('开始导入',
                style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final root = ctrl.text.trim();
    ctrl.dispose();
    if (root.isEmpty) return;

    if (!mounted) return;
    setState(() => _importing = true);
    try {
      final letters = await OliviaImportService.parseDir(root);
      final res = await OliviaImportService.importLetters(letters);
      if (!mounted) return;
      _showImportResult(res);
    } catch (e) {
      if (mounted) _toast('导入失败：$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _showImportResult(OliviaImportResult res) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          res.ok ? '导入完成' : '导入未完成',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                res.ok
                    ? '解析到 ${res.parsed} 封 Olivia 原版信件，'
                        '成功导入 ${res.imported} 封，跳过已存在 ${res.skipped} 封。'
                    : '错误：${res.error}',
                style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 12),
              ),
              if (res.titles.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('已导入：',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
                const SizedBox(height: 4),
                ...res.titles
                    .take(20)
                    .map((t) => Text('· $t',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 11))),
                if (res.titles.length > 20)
                  Text('…等 ${res.titles.length} 封',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('知道了',
                style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('设置',
                style: TextStyle(fontSize: 20, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(
                'API 凭据以主密码加密存储（AES，可移植：在其它设备用同一主密码即可解密），其他应用无密码无法读取；本应用可正常导出。',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 20),
            _personaSection(),
            const SizedBox(height: 20),
            _appearanceSection(),
            const SizedBox(height: 20),
            _windowSection(),
            const SizedBox(height: 20),
            _wallpaperSection(),
            const SizedBox(height: 20),
            _apiSection(),
            const SizedBox(height: 20),
            _transferSection(),
            const SizedBox(height: 20),
            _oliviaImportSection(),
            const SizedBox(height: 20),
            _aboutSection(),
          ],
        ),
      ),
    );
  }

  Widget _apiSection() {
    return SettingsSection(
      title: 'API 与模型配置',
      subtitle: '配置调用大模型所需的接口地址、密钥与模型名称。',
      children: [
        settingsField('API Base URL', _baseUrl,
            hint: 'https://api.deepseek.com/v1'),
        const SizedBox(height: 14),
        settingsField('API Key', _apiKey, hint: 'sk-...', obscure: true),
        const SizedBox(height: 14),
        settingsField('Chat Model', _chatModel, hint: 'deepseek-chat'),
        const SizedBox(height: 14),
        settingsField('Embedding Model', _embeddingModel,
            hint: 'deepseek-embedding'),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: _export,
              icon: const Icon(Icons.upload_outlined, size: 18),
              label: const Text('导出配置'),
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('保存'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.onAccent,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _aboutSection() {
    return SettingsSection(
      title: '关于',
      subtitle: '${AppInfo.appName} · ${AppInfo.appNameCn}',
      children: [
        infoRow('软件版本', AppInfo.version),
        const SizedBox(height: 8),
        infoRow('内部版本号', AppInfo.buildNumber),
      ],
    );
  }

}
