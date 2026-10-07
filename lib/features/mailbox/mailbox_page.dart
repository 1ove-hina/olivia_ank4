import 'package:flutter/material.dart';
import 'package:olivia_ank4/app/theme.dart';
import 'package:olivia_ank4/domain/models.dart';
import 'package:olivia_ank4/features/compose/compose_page.dart';
import 'package:olivia_ank4/features/mailbox/letter_view_page.dart';
import 'package:olivia_ank4/services/birthday_service.dart';
import 'package:olivia_ank4/services/crypto_service.dart';
import 'package:olivia_ank4/services/letter_service.dart';
import 'package:olivia_ank4/services/pending_reply_service.dart';
import 'package:olivia_ank4/widgets/master_pass_dialog.dart';

/// 信箱页（P5：本地持久化信件列表 + 新建 + 详情/编辑/删除）
class MailboxPage extends StatefulWidget {
  const MailboxPage({super.key});

  @override
  State<MailboxPage> createState() => _MailboxPageState();
}

enum _View { list, compose, detail }

class _MailboxPageState extends State<MailboxPage> {
  _View _view = _View.list;
  Letter? _active;
  List<Letter> _letters = [];
  Set<String> _pendingIds = {}; // 处于「待林离回信」状态的信件 id

  @override
  void initState() {
    super.initState();
    PendingReplyWatcher.instance.addListener(_onDelivered);
    BirthdayService.instance.addListener(_onBirthdayLetter);
    _reload();
  }

  @override
  void dispose() {
    PendingReplyWatcher.instance.removeListener(_onDelivered);
    BirthdayService.instance.removeListener(_onBirthdayLetter);
    super.dispose();
  }

  /// 某封待投递回信被投递后，刷新列表（移除「待回信」标记）
  void _onDelivered(PendingReply p) => _reload();

  /// 林离主动写来的生日信，实时刷新信箱
  void _onBirthdayLetter(Letter l) => _reload();

  Future<void> _reload() async {
    final all = await LetterService.loadAll();
    final pendings = await PendingReplyService.loadAll();
    if (mounted) {
      setState(() {
        _letters = all;
        _pendingIds = pendings.map((p) => p.letterId).toSet();
      });
    }
  }

  void _openCompose([Letter? letter]) =>
      setState(() { _active = letter; _view = _View.compose; });
  void _openDetail(Letter l) =>
      setState(() { _active = l; _view = _View.detail; });
  void _backToList() {
    _active = null;
    _view = _View.list;
    _reload();
  }

  /// 解锁主密码后重新加载（用于锁定态的「解锁查看」按钮）
  Future<void> _unlock() async {
    final ok = await ensureUnlocked(context);
    if (ok) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_view == _View.compose) {
      return ComposePage(
        letter: _active,
        onClose: _backToList,
        onSaved: _reload,
      );
    }
    if (_view == _View.detail && _active != null) {
      return LetterViewPage(
        letter: _active!,
        onEdit: () => _openCompose(_active),
        onBack: _backToList,
      );
    }
    return _buildList();
  }

  Widget _buildList() {
    // 锁定态：未解锁主密码无法解密信件，引导解锁而非展示空列表
    if (CryptoService.sessionPassphrase == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('信箱',
                style: TextStyle(fontSize: 20, color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline,
                        size: 56, color: AppColors.textSecondary),
                    const SizedBox(height: 16),
                    Text('信件已加密',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _unlock,
                      icon: const Icon(Icons.lock_open_outlined, size: 18),
                      label: const Text('解锁查看'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.onAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('信箱',
                  style: TextStyle(fontSize: 20, color: AppColors.textPrimary)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _openCompose(),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('写信'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.onAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _letters.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mail_outline,
                            size: 56, color: AppColors.textSecondary),
                        SizedBox(height: 16),
                        Text('暂无信件',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _letters.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final l = _letters[i];
                      final preview = l.messages.isNotEmpty
                          ? l.messages.first.content
                          : '';
                      return _LetterTile(
                        letter: l,
                        preview: preview,
                        hasPending: _pendingIds.contains(l.id),
                        onOpen: () => _openDetail(l),
                        onDelete: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              backgroundColor: AppColors.surface,
                              title: Text('删除这封信？',
                                  style: TextStyle(color: AppColors.textPrimary)),
                              content: Text('删除后无法恢复。',
                                  style: TextStyle(
                                      color: AppColors.textSecondary)),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: Text('取消',
                                      style: TextStyle(
                                          color: AppColors.textSecondary)),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  child: const Text('删除',
                                      style: TextStyle(
                                          color: Colors.redAccent)),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await LetterService.delete(l.id);
                            _reload();
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _LetterTile extends StatelessWidget {
  final Letter letter;
  final String preview;
  final bool hasPending;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _LetterTile({
    required this.letter,
    required this.preview,
    this.hasPending = false,
    required this.onOpen,
    required this.onDelete,
  });

  String _fmt(DateTime d) =>
      '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final snippet = preview.length > 60 ? '${preview.substring(0, 60)}…' : preview;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(letter.title,
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  if (hasPending)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('待林离回信…',
                          style: TextStyle(
                              color: AppColors.accent, fontSize: 11)),
                    ),
                  Text(snippet,
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(_fmt(letter.updatedAt),
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            IconButton(
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline,
                  color: AppColors.textSecondary, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
