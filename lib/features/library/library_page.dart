import 'package:flutter/material.dart';
import 'package:olivia_ank4/widgets/placeholder_body.dart';

/// 曲库页（P0 占位；演奏链路为 v2 范围）
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderBody(
      icon: Icons.library_music_outlined,
      title: '曲库',
      subtitle: 'MIDI / 演奏生成 · 待开发（演奏链路 v2）',
    );
  }
}
