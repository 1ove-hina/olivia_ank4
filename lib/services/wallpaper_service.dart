import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';

/// 动态桌面壁纸：按本地时间段挑选林离动态场景视频
///
/// 视频命名规则（取自 Olivia 原版素材，3 × 3 × 3 = 27 个）：
///   {变体}_{镜头}_{时段}.mp4
///   变体：A / B / C
///   镜头：R1 / R2 / R3
///   时段：1200 / 1730 / 2000
///
/// 时段映射（按本地时间，依据用户最新规则）：
///   06:00 – 14:00 → 1200
///   14:00 – 18:00 → 1730
///   18:00 – 次日 06:00 → 2000   // 用户确认：夜间播 2000
///
/// 变体与镜头：设置页可锁定某一取值，或保持「随机」。
class WallpaperService {
  WallpaperService._();

  static const List<String> variants = ['A', 'B', 'C'];
  static const List<String> takes = ['R1', 'R2', 'R3'];
  static const String _prefsFile = 'wallpaper_prefs.json';

  /// 原版素材目录，仅用于设置页预填（不存在时忽略）
  static const String defaultSourceDir =
      r'E:\work\BSide Olivia Lin Test\0.0.9.615\assets\Wallpaper_Presence';

  /// 壁纸背景音乐默认目录（用户指定）
  static const String defaultMusicDir = r'E:\456';

  static final Random _rnd = Random();

  /// 根据本地时间返回时段关键字
  static String timeKeyFor(DateTime t) {
    final h = t.hour;
    if (h >= 6 && h < 14) return '1200';
    if (h >= 14 && h < 18) return '1730';
    return '2000'; // 18:00 – 次日 06:00（用户规则：夜间播 2000）
  }

  /// 时段中文说明（设置页展示用）
  static String slotLabelFor(DateTime t) {
    switch (timeKeyFor(t)) {
      case '1200':
        return '白天 06:00–14:00（素材 1200）';
      case '1730':
        return '午后 14:00–18:00（素材 1730）';
      case '2000':
        return '夜间 18:00–次日 06:00（素材 2000）';
      default:
        return '未知时段';
    }
  }

  /// 组装目标文件名。
  /// [variant]/[take] 传 'random'（或省略）则随机，否则锁定取值。
  static String pickFileName(
    DateTime t, {
    String variant = 'random',
    String take = 'random',
  }) {
    final key = timeKeyFor(t);
    final v = (variant == 'random' || !variants.contains(variant))
        ? variants[_rnd.nextInt(variants.length)]
        : variant;
    final r = (take == 'random' || !takes.contains(take))
        ? takes[_rnd.nextInt(takes.length)]
        : take;
    return '${v}_${r}_$key.mp4';
  }

  /// 壁纸「外部自定义」存放目录：优先用偏好里的 source，否则回落默认原版目录。
  static Future<String> resolveSourceDir() async {
    final p = await loadPrefs();
    final s = p.source.trim();
    return s.isEmpty ? defaultSourceDir : s;
  }

  /// 扫描指定目录下全部 .mp4 视频（完整路径）。
  /// 目录不存在或无访问权限时返回空列表（不抛异常）。
  static Future<List<String>> _scanDir(String dirPath) async {
    final d = Directory(dirPath);
    if (!d.existsSync()) return [];
    try {
      return d
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.mp4'))
          .map((f) => f.path)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 外部素材目录中可用的视频数量（设置页展示用）。
  static Future<int> countInSource([String? sourceDir]) async {
    final dir = sourceDir ?? await resolveSourceDir();
    return (await _scanDir(dir)).length;
  }

  /// 解析当前应播放的视频（**直接读取外部自定义目录**，不再复制到应用数据）：
  /// 优先命中的「变体_镜头_时段」→ 退化为同时段任意 → 再退化为任意已找到。
  /// 返回完整文件路径；无匹配时返回 null。
  static Future<String?> resolveCurrent(
    DateTime t, {
    String variant = 'random',
    String take = 'random',
    String? sourceDir,
  }) async {
    final dir = sourceDir ?? await resolveSourceDir();
    final files = await _scanDir(dir);
    if (files.isEmpty) return null;
    final key = timeKeyFor(t);
    final wanted = pickFileName(t, variant: variant, take: take);
    for (final f in files) {
      if (f.endsWith(wanted)) return f;
    }
    final sameSlot = files.where((f) => f.endsWith('$key.mp4')).toList();
    if (sameSlot.isNotEmpty) {
      sameSlot.shuffle(_rnd);
      return sameSlot.first;
    }
    final any = List<String>.of(files)..shuffle(_rnd);
    return any.first;
  }

  // ---- 偏好持久化（独立明文文件，不含敏感信息，不依赖主密码）----

  static Future<File> _prefsPath() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_prefsFile');
  }

  static Future<WallpaperPrefs> loadPrefs() async {
    final f = await _prefsPath();
    if (!f.existsSync()) return const WallpaperPrefs();
    try {
      final m = jsonDecode(await f.readAsString());
      if (m is Map<String, dynamic>) return WallpaperPrefs.fromJson(m);
    } catch (_) {
      // 损坏则回落默认
    }
    return const WallpaperPrefs();
  }

  static Future<void> savePrefs(WallpaperPrefs p) async {
    final f = await _prefsPath();
    await f.writeAsString(jsonEncode(p.toJson()));
  }
}

/// 动态桌面偏好（独立持久化，非加密）
class WallpaperPrefs {
  final bool enabled;
  final String variant; // 'random' | 'A' | 'B' | 'C'
  final String take; // 'random' | 'R1' | 'R2' | 'R3'
  final String source; // 外部自定义素材目录（用户可选，默认回落原版目录）
  final bool musicEnabled; // 壁纸播放时是否随机播放背景音乐
  final String musicDir; // 背景音乐目录（默认 E:\456）

  const WallpaperPrefs({
    this.enabled = false,
    this.variant = 'random',
    this.take = 'random',
    this.source = WallpaperService.defaultSourceDir,
    this.musicEnabled = true,
    this.musicDir = WallpaperService.defaultMusicDir,
  });

  factory WallpaperPrefs.fromJson(Map<String, dynamic> j) => WallpaperPrefs(
        enabled: j['enabled'] as bool? ?? false,
        variant: j['variant'] as String? ?? 'random',
        take: j['take'] as String? ?? 'random',
        source: j['source'] as String? ?? WallpaperService.defaultSourceDir,
        musicEnabled: j['musicEnabled'] as bool? ?? true,
        musicDir: j['musicDir'] as String? ?? WallpaperService.defaultMusicDir,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'variant': variant,
        'take': take,

        'source': source,
        'musicEnabled': musicEnabled,
        'musicDir': musicDir,
      };

  WallpaperPrefs copyWith({
    bool? enabled,
    String? variant,
    String? take,
    String? source,
    bool? musicEnabled,
    String? musicDir,
  }) =>
      WallpaperPrefs(
        enabled: enabled ?? this.enabled,
        variant: variant ?? this.variant,
        take: take ?? this.take,
        source: source ?? this.source,
        musicEnabled: musicEnabled ?? this.musicEnabled,
        musicDir: musicDir ?? this.musicDir,
      );
}
