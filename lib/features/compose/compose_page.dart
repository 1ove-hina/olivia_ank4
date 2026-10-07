import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:olivia_ank4/app/theme.dart';
import 'package:olivia_ank4/domain/memory_state.dart';
import 'package:olivia_ank4/domain/models.dart';
import 'package:olivia_ank4/domain/persona_state.dart';
import 'package:olivia_ank4/features/compose/prompt_builder.dart';
import 'package:olivia_ank4/features/persona/persona_editor_dialog.dart';
import 'package:olivia_ank4/services/crypto_service.dart';
import 'package:olivia_ank4/services/embedding_service.dart';
import 'package:olivia_ank4/services/letter_quota_service.dart';
import 'package:olivia_ank4/services/letter_service.dart';
import 'package:olivia_ank4/services/llm_service.dart';
import 'package:olivia_ank4/services/memory_service.dart';
import 'package:olivia_ank4/services/pending_reply_service.dart';
import 'package:olivia_ank4/services/persona_service.dart';
import 'package:olivia_ank4/services/settings_service.dart';
import 'package:olivia_ank4/widgets/master_pass_dialog.dart';

/// 写信页（P3 接入 LLM，P4 接入记忆检索 RAG，P5 接入信箱持久化）
/// - 来信草稿：用户写给林离的信；**尚未收到回信时独占整宽**
/// - 林离的回信：只在延迟投递**送达之后**才出现（等待期间只显示草稿 +
///   一行「预计送达 / 倒计时」，不再常驻占位面板），送达后可复制
/// - 头部实时显示当前人设；可「保存到记忆」把本次来信与回信写入本地向量库
/// - [letter] 非空时进入「继续编辑」模式，预填内容并复用同一封信 id
class ComposePage extends StatefulWidget {
  final Letter? letter;
  final VoidCallback onClose;
  final VoidCallback? onSaved;
  const ComposePage(
      {super.key, this.letter, required this.onClose, this.onSaved});

  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  final _draft = TextEditingController();
  final _reply = ValueNotifier<String?>(null);
  final _error = ValueNotifier<String?>(null);
  final _memoryNote = ValueNotifier<String?>(null);
  final _waitHint = ValueNotifier<String?>(null);
  String? _letterId;
  bool _busy = false;
  PendingReply? _pending; // 当前信处于「待投递」状态时非空
  Timer? _countdownTimer;

  /// 今日还可寄出的封数（默认上限，加载后以磁盘记录为准）
  int _remaining = LetterQuotaService.dailyLimit;

  @override
  void initState() {
    super.initState();
    final l = widget.letter;
    if (l != null) {
      _letterId = l.id;
      final userMsg =
          l.messages.where((m) => m.role == 'user').firstOrNull?.content ?? '';
      final aiMsg = l.messages
          .where((m) => m.role == 'assistant')
          .firstOrNull
          ?.content;
      _draft.text = userMsg;
      if (aiMsg != null) _reply.value = aiMsg;
    }
    // 监听全局投递事件（退出再回来后由 Watcher 补投，这里即时显示）
    PendingReplyWatcher.instance.addListener(_onDelivered);
    _restorePending();
    _loadQuota();
  }

  /// 载入今日剩余寄信封数（每日上限见 [LetterQuotaService.dailyLimit]）
  Future<void> _loadQuota() async {
    final left = await LetterQuotaService.remainingToday();
    if (mounted) setState(() => _remaining = left);
  }

  /// 若正在编辑一封「尚无回信、但已排入待投递」的信，恢复其等待态
  Future<void> _restorePending() async {
    if (_letterId == null) return;
    final p = await PendingReplyService.forLetter(_letterId!);
    if (p != null && mounted) {
      setState(() => _pending = p);
      _startCountdown();
    }
  }

  /// 全局投递回调：仅当投递的是当前这封信时，才把回信显示出来
  void _onDelivered(PendingReply p) {
    if (p.letterId != _letterId) return;
    if (!mounted) return;
    setState(() {
      _reply.value = p.reply;
      _pending = null;
    });
    _stopCountdown();
    _waitHint.value = null;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('林离回信了 ♥'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _startCountdown() {
    _stopCountdown();
    _updateWaitHint();
    _countdownTimer = Timer.periodic(
        const Duration(seconds: 1), (_) => _updateWaitHint());
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  void _updateWaitHint() {
    if (_pending == null) {
      _waitHint.value = null;
      return;
    }
    final remain = _pending!.dueTime.difference(DateTime.now());
    final eta = _pending!.dueTime;
    final etas =
        '${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';
    if (remain.isNegative) {
      _waitHint.value = '林离正在回信…（预计 $etas 送达）';
      return;
    }
    final mm = remain.inMinutes;
    final ss = remain.inSeconds % 60;
    _waitHint.value =
        '林离正在回信… 预计 $etas 送达（约剩 ${mm}分${ss.toString().padLeft(2, '0')}秒）';
  }

  @override
  void dispose() {
    PendingReplyWatcher.instance.removeListener(_onDelivered);
    _stopCountdown();
    _draft.dispose();
    _reply.dispose();
    _error.dispose();
    _memoryNote.dispose();
    _waitHint.dispose();
    super.dispose();
  }

  Future<void> _openPersona() async {
    await showDialog(
        context: context, builder: (_) => const PersonaEditorDialog());
  }

  /// 取得主密码（已解锁复用会话密码，否则弹窗）
  Future<String?> _ensurePass() async {
    String? pass = CryptoService.sessionPassphrase;
    if (pass == null || pass.isEmpty) {
      pass = await showMasterPassDialog(context);
    }
    return pass;
  }

  Future<void> _generate() async {
    final letter = _draft.text.trim();
    if (letter.isEmpty) return;

    // 每日寄信上限：送出前重读磁盘记录，避免页面长时间停留、跨天或重开后
    // 仍按旧计数放行（也防止配额文件被其它实例修改时判定失准）。
    final left = await LetterQuotaService.remainingToday();
    if (!mounted) return;
    if (left != _remaining) setState(() => _remaining = left);
    if (left <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('今天的 ${LetterQuotaService.dailyLimit} 封信已经写完了，'
              '明天 00:00 后可再写'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    _error.value = null;
    _memoryNote.value = null;

    // 1) 主密码 → API 配置
    final pass = await _ensurePass();
    if (pass == null) {
      setState(() => _busy = false);
      return;
    }
    final settings = await SettingsService.load(pass);
    if (settings == null) {
      _error.value = '主密码错误';
      setState(() => _busy = false);
      return;
    }
    if (settings.apiKey.isEmpty) {
      _error.value = '请先在「设置」中填写 API Key';
      setState(() => _busy = false);
      return;
    }

    // 2) 生效人设 systemPrompt
    final systemPrompt = activePersona.persona?.systemPrompt ??
        (await PersonaService.loadDefault()).systemPrompt;

    // 3) 上下文参考
    // - 已配置 Embedding 模型：用来信向量检索本地记忆库（RAG）
    // - 未配置 Embedding 模型：回退到「此前写的最近 3 封信」全文作为上下文参考
    String augmented = systemPrompt;
    final embeddingConfigured = settings.embeddingModel.trim().isNotEmpty;
    if (embeddingConfigured) {
      List<MemoryChunk> memories = [];
      try {
        final queryVec =
            await EmbeddingService.embed(settings: settings, text: letter);
        memories = await MemoryService.retrieve(queryVec, topK: 4);
      } catch (e) {
        // 检索失败不应阻断写信，仅提示
        _memoryNote.value =
            '记忆检索暂不可用：${e.toString().replaceFirst('Exception: ', '')}';
      }
      augmented = buildAugmentedPrompt(systemPrompt, memories);
      if (memories.isNotEmpty) {
        _memoryNote.value = '已结合 ${memories.length} 条记忆';
      }
    } else {
      // 未配置 Embedding：直接取此前信箱中最近 3 封信（排除当前正在编辑的这封）
      // 作为背景，帮助林离延续关系、语气与未竟之事。
      final prev = (await LetterService.loadAll())
          .where((l) => l.id != _letterId)
          .take(3)
          .toList();
      if (prev.isNotEmpty) {
        augmented = appendLettersToPrompt(systemPrompt, prev);
        _memoryNote.value = '未配置 Embedding，已用最近 ${prev.length} 封信作为参考';
      } else {
        _memoryNote.value = '未配置 Embedding，且无历史信件可参考';
      }
    }

    // 4) 调模型
    try {
      final result = await LLMService.chat(
        settings: settings,
        systemPrompt: augmented,
        userLetter: letter,
      );
      // 延迟收信：回信已生成，但不立即展示，按 15–60 分钟（随机）延迟投递。
      _letterId ??= LetterService.newId();
      final draft = _draft.text.trim();
      // 先清掉同一封信可能残留的旧待投递项（避免重复投递）
      final oldPending = await PendingReplyService.forLetter(_letterId!);
      if (oldPending != null) await PendingReplyService.remove(oldPending.id);
      // 仅先把「来信」落盘（回信待投递时再追加），信箱里这封信此时只有用户侧
      await _persistInitialLetter(draft);
      // 随机延迟 15–60 分钟
      final dueAt =
          DateTime.now().add(Duration(minutes: 15 + Random().nextInt(46)));
      final p = await PendingReplyService.schedule(
        letterId: _letterId!,
        draft: draft,
        reply: result,
        dueAt: dueAt,
      );
      if (mounted) {
        setState(() {
          _pending = p;
          // 重新生成的情况：旧回信立即撤下，等新回信送达后再显示，
          // 与 _persistInitialLetter 只落盘「来信」的状态保持一致。
          _reply.value = null;
        });
        _startCountdown();
        // 信已真正送出，记入今日配额
        await LetterQuotaService.recordSend();
        final after = await LetterQuotaService.remainingToday();
        if (!mounted) return;
        setState(() => _remaining = after);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('信已寄出 · 林离预计 ${formatHM(dueAt)} 回信'
                '（15–60 分钟内随机送达）'
                '${after > 0 ? ' · 今日还可送 $after 封' : ''}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      _error.value = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 仅把「来信」写入信箱（回信将延迟投递时再追加），便于信箱即可见已寄出但待回信
  Future<void> _persistInitialLetter(String draft) async {
    if (draft.isEmpty) return;
    _letterId ??= LetterService.newId();
    final now = DateTime.now();
    final lines = draft
        .split('\n')
        .where((s) => s.trim().isNotEmpty)
        .map((s) => s.trim())
        .toList();
    final raw = lines.isNotEmpty ? lines.first : '';
    final title = raw.isEmpty
        ? '未命名信件'
        : (raw.length > 40 ? '${raw.substring(0, 40)}…' : raw);
    final existing = await LetterService.get(_letterId!);
    final created = existing?.createdAt ?? now;
    final letter = Letter(
      id: _letterId!,
      title: title,
      personaId: activePersona.persona?.id ?? 'linli',
      messages: [Message(role: 'user', content: draft, createdAt: created)],
      createdAt: created,
      updatedAt: now,
    );
    await LetterService.save(letter);
    widget.onSaved?.call();
  }

  /// 把当前草稿 + 回信写入信箱（P5）：首次生成创建新信件，再次生成复用同一 id
  Future<void> _persistLetter() async {
    final draft = _draft.text.trim();
    final reply = _reply.value;
    if (draft.isEmpty || reply == null || reply.isEmpty) return;
    _letterId ??= LetterService.newId();
    final now = DateTime.now();
    final lines = draft
        .split('\n')
        .where((s) => s.trim().isNotEmpty)
        .map((s) => s.trim())
        .toList();
    final raw = lines.isNotEmpty ? lines.first : '';
    final title = raw.isEmpty
        ? '未命名信件'
        : (raw.length > 40 ? '${raw.substring(0, 40)}…' : raw);
    final existing = await LetterService.get(_letterId!);
    final created = existing?.createdAt ?? now;
    final letter = Letter(
      id: _letterId!,
      title: title,
      personaId: activePersona.persona?.id ?? 'linli',
      messages: [
        Message(role: 'user', content: draft, createdAt: created),
        Message(role: 'assistant', content: reply, createdAt: now),
      ],
      createdAt: created,
      updatedAt: now,
    );
    await LetterService.save(letter);
    widget.onSaved?.call();
  }

  /// 保存到记忆：把本次来信与回信切块 + Embedding 写入本地向量库
  Future<void> _saveMemory() async {
    final letter = _draft.text.trim();
    final reply = _reply.value;
    if (letter.isEmpty || reply == null || reply.isEmpty) return;

    _error.value = null;
    setState(() => _busy = true);
    final pass = await _ensurePass();
    if (pass == null) {
      setState(() => _busy = false);
      return;
    }
    final settings = await SettingsService.load(pass);
    if (settings == null) {
      _error.value = '主密码错误';
      setState(() => _busy = false);
      return;
    }
    try {
      final added = await MemoryService.addTexts(
        texts: [letter, reply],
        settings: settings,
        letterId: 'compose',
      );
      await _refreshMemoryCount();
      await _persistLetter();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已存入 $added 段记忆'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      _error.value = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshMemoryCount() async {
    final all = await MemoryService.loadAll();
    memoryState.setCount(all.length);
  }

  Future<void> _copyReply() async {
    final text = _reply.value;
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制回信'), duration: Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * 14),
          child: child,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: widget.onClose,
                icon: Icon(Icons.arrow_back, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 8),
              Text('写信',
                  style: TextStyle(fontSize: 20, color: AppColors.textPrimary)),
              const Spacer(),
              AnimatedBuilder(
                animation: activePersona,
                builder: (_, __) => Text(
                    '人设：${activePersona.persona?.name ?? '林离'}',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: _openPersona,
                tooltip: '人设设置',
                icon: Icon(Icons.person_outline,
                    color: AppColors.textSecondary, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            // 回信区只在「回信已送达」后出现：没有回信时草稿区独占整宽。
            child: ValueListenableBuilder<String?>(
              valueListenable: _reply,
              builder: (_, reply, __) {
                if (reply == null) return _draftPanel();
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 4, child: _draftPanel()),
                    const SizedBox(width: 12),
                    Expanded(flex: 6, child: _replyPanel()),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ValueListenableBuilder<String?>(
                valueListenable: _error,
                builder: (_, e, __) => e == null
                    ? const SizedBox.shrink()
                    : Expanded(
                        child: Text('⚠ $e',
                            style: const TextStyle(
                                color: Colors.redAccent, fontSize: 12))),
              ),
              ValueListenableBuilder<String?>(
                valueListenable: _memoryNote,
                builder: (_, n, __) => n == null
                    ? const SizedBox.shrink()
                    : Text(n,
                        style: TextStyle(
                            color: AppColors.accent, fontSize: 12)),
              ),
              const Spacer(),
              if (_reply.value != null)
                TextButton.icon(
                  onPressed: _busy ? null : _saveMemory,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: const Text('保存到记忆'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                  ),
                ),
              const SizedBox(width: 8),
              if (_busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                FilledButton.icon(
                  onPressed: (_draft.text.isEmpty ||
                          _pending != null ||
                          _remaining <= 0)
                      ? null
                      : _generate,
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('生成回信'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onAccent,
                    disabledBackgroundColor: AppColors.surfaceVariant,
                    disabledForegroundColor: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  Widget _draftPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
        image: const DecorationImage(
          image: AssetImage('assets/backgrounds/user_bg.webp'),
          fit: BoxFit.cover,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('来信草稿',
                  style: TextStyle(
                      color: AppColors.paperTextSecondary, fontSize: 12)),
              const Spacer(),
              // 每日寄信上限的常驻提示：用满时按钮会置灰，这里说明原因
              Text(
                _remaining > 0
                    ? '今日还可送 $_remaining 封'
                    : '今日 ${LetterQuotaService.dailyLimit} 封已写完 · 明天再来',
                style: TextStyle(
                  color: _remaining > 0
                      ? AppColors.paperTextSecondary
                      : AppColors.accent,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          // 等待回信期间的状态行：信已寄出但回信未到，此时右侧不显示回信区，
          // 用小字在此处给出「预计送达 / 倒计时」，避免发送后没有任何可久留的反馈。
          ValueListenableBuilder<String?>(
            valueListenable: _waitHint,
            builder: (_, hint, __) => hint == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.mark_email_unread_outlined,
                            size: 14, color: AppColors.paperTextSecondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            hint,
                            style: TextStyle(
                                color: AppColors.paperTextSecondary,
                                fontSize: 12,
                                height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TextField(
              controller: _draft,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: '写给林离…',
                hintStyle: TextStyle(color: AppColors.paperTextSecondary),
              ),
              style: TextStyle(color: AppColors.paperTextPrimary, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _replyPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
        image: const DecorationImage(
          image: AssetImage('assets/backgrounds/linli_bg.webp'),
          fit: BoxFit.cover,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('林离的回信',
                  style: TextStyle(color: AppColors.paperTextSecondary, fontSize: 12)),
              const Spacer(),
              ValueListenableBuilder<String?>(
                valueListenable: _reply,
                builder: (_, r, __) => r == null
                    ? const SizedBox.shrink()
                    : IconButton(
                        onPressed: _copyReply,
                        tooltip: '复制',
                        icon: Icon(Icons.copy_outlined,
                            color: AppColors.paperTextSecondary, size: 18),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ValueListenableBuilder<String?>(
              valueListenable: _reply,
              builder: (_, reply, __) {
                // 该面板只在「回信已送达」时被构建，这里主要覆盖重新生成时的等待态
                if (_busy) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (reply == null) return const SizedBox.shrink();
                return SingleChildScrollView(
                  child: SelectableText(reply,
                      style: TextStyle(
                          color: AppColors.paperTextPrimary, height: 1.6)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
