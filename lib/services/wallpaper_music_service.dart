import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;

/// 动态桌面背景音乐：壁纸播放时，从指定目录随机循环播放本地音频。
///
/// 与壁纸生命周期绑定——壁纸启动后调用 [start]、壁纸停止时调用 [stop]。
/// Windows 后端用 just_audio + just_audio_windows（WinRT MediaPlayer，纯原生
/// 编译、无需下载 libmpv 等外部二进制），支持 mp3 / wav / flac / m4a / aac /
/// ogg / opus / wma 等常见格式。每首播完随机挑下一首（避免与当前曲重复），
/// 目录为空或无解码器时静默不播。
class WallpaperMusicService {
  WallpaperMusicService._();
  static final WallpaperMusicService instance = WallpaperMusicService._();

  final AudioPlayer _player = AudioPlayer();
  final Random _rnd = Random();
  static final Set<String> _audioExts = {
    'mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg', 'opus', 'wma',
  };

  List<File> _tracks = const [];
  int _current = -1;
  bool _playing = false;
  bool _currentPlaying = false; // 已真正开始播放（防 completed 重入死循环）
  bool _inited = false;

  /// 扫描目录内音频文件（完整路径）。目录不存在/无权限返回空，不抛。
  static Future<List<File>> scanAudio(String dir) async {
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    final out = <File>[];
    try {
      for (final e in d.listSync()) {
        if (e is File) {
          final ext = p.extension(e.path).toLowerCase();
          if (ext.length > 1 && _audioExts.contains(ext.substring(1))) {
            out.add(e);
          }
        }
      }
    } catch (_) {
      return const [];
    }
    return out;
  }

  /// 目录内音频数量（设置页展示用）。
  static Future<int> countIn(String dir) => scanAudio(dir).then((l) => l.length);

  void _ensureInit() {
    if (_inited) return;
    // just_audio 默认 MethodChannel 后端在 Windows 由 just_audio_windows 插件
    // （WinRT MediaPlayer，纯原生编译、无需下载 libmpv）自动接管，无需显式初始化。
    _player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed && _playing && _currentPlaying) {
        _currentPlaying = false;
        _playNext(); // 一首播完，随机下一首
      }
    });
    _inited = true;
  }

  /// 启动随机循环播放。幂等：已在播放则直接返回（不会重启当前曲）。
  /// [dir] 音频目录，默认 E:\456；[volume] 0..1，默认 0.5。
  Future<void> start({String dir = r'E:\456', double volume = 0.5}) async {
    _ensureInit();
    if (_playing) return;
    final files = await scanAudio(dir);
    if (files.isEmpty) return; // 无音频：静默不播
    _tracks = files;
    _playing = true;
    _currentPlaying = false;
    await _player.setVolume(volume);
    await _playNext();
  }

  Future<void> _playNext({int attempt = 0}) async {
    if (!_playing || _tracks.isEmpty) return;
    if (attempt >= _tracks.length) {
      // 全部文件都无法解码/播放，安静退出，避免死循环
      _playing = false;
      return;
    }
    final idx = (_tracks.length == 1)
        ? 0
        : (() {
            int i;
            do {
              i = _rnd.nextInt(_tracks.length);
            } while (i == _current);
            return i;
          })();
    _current = idx;
    _currentPlaying = false;
    try {
      await _player.setFilePath(_tracks[idx].path);
      await _player.play();
      _currentPlaying = true;
    } catch (_) {
      // 该文件无法播放，跳到下一首（携带 attempt 防止无限递归）
      await _playNext(attempt: attempt + 1);
    }
  }

  /// 停止播放（壁纸停止时调用）。
  Future<void> stop() async {
    _playing = false;
    _currentPlaying = false;
    _current = -1;
    try {
      await _player.stop();
    } catch (_) {}
  }

  /// 释放底层播放器（应用退出时可选调用）。
  Future<void> dispose() async {
    await stop();
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
