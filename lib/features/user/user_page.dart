import 'package:flutter/material.dart';
import 'package:olivia_ank4/app/theme.dart';
import 'package:olivia_ank4/domain/memory_state.dart';
import 'package:olivia_ank4/domain/persona_state.dart';
import 'package:olivia_ank4/domain/user_profile.dart';
import 'package:olivia_ank4/services/credential_store.dart';
import 'package:olivia_ank4/services/crypto_service.dart';
import 'package:olivia_ank4/services/stats_service.dart';
import 'package:olivia_ank4/services/user_profile_service.dart';
import 'package:olivia_ank4/widgets/master_pass_dialog.dart';

/// 用户页（P1）：个人资料、写信统计、当前人设与安全。
class UserPage extends StatefulWidget {
  const UserPage({super.key});

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  bool _loading = true;
  UserProfile _profile = UserProfileService.defaultProfile();
  LetterStats _stats = const LetterStats();
  bool _statsLocked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await UserProfileService.load();
    final stats = await _loadStats();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _stats = stats;
      _loading = false;
    });
  }

  Future<LetterStats> _loadStats() async {
    if (CryptoService.sessionPassphrase == null) {
      _statsLocked = true;
      return const LetterStats();
    }
    _statsLocked = false;
    return await StatsService.compute();
  }

  Future<void> _unlock() async {
    final ok = await ensureUnlocked(context);
    if (ok) await _load();
  }

  Future<void> _editNickname() async {
    final ctrl = TextEditingController(text: _profile.nickname);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('修改昵称', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 16,
          style: TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: '输入昵称',
            hintStyle: TextStyle(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.inputBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('保存', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final nickname = ctrl.text.trim();
      if (nickname.isNotEmpty) {
        final updated = _profile.copyWith(nickname: nickname);
        await UserProfileService.save(updated);
        setState(() => _profile = updated);
      }
    }
    ctrl.dispose();
  }

  Future<void> _clearAutoUnlock() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('清除本机自动解锁', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          '下次启动应用时将重新要求输入主密码。本地数据不会被删除。',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('清除', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await CredentialStore.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.surface,
            content: Text('已清除本机自动解锁', style: TextStyle(color: AppColors.textPrimary)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        color: AppColors.background,
        child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    return Container(
      color: AppColors.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildStats(),
            const SizedBox(height: 24),
            _buildPersonaCard(),
            const SizedBox(height: 24),
            _buildSecurity(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final joined =
        '${_profile.joinedAt.year}-${_profile.joinedAt.month.toString().padLeft(2, '0')}-${_profile.joinedAt.day.toString().padLeft(2, '0')}';
    return Row(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.divider),
          ),
          child: Icon(Icons.person_outline, size: 36, color: AppColors.accent),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _profile.nickname,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '加入于 $joined',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              _buildBirthdayRow(),
              const SizedBox(height: 8),
              _buildGenderRow(),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: _editNickname,
          icon: Icon(Icons.edit_outlined, size: 16, color: AppColors.accent),
          label: Text('改昵称', style: TextStyle(color: AppColors.accent)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: AppColors.divider),
            foregroundColor: AppColors.accent,
          ),
        ),
      ],
    );
  }

  Widget _buildBirthdayRow() {
    final b = _profile.birthday;
    if (b == null) {
      return InkWell(
        onTap: _editBirthday,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            '🎂 设置生日（当天林离会写信给你）',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.accent,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      );
    }
    final now = DateTime.now();
    final age = (b.year < now.year && b.year > 1900) ? now.year - b.year : null;
    return Row(
      children: [
        Text(
          '🎂 ${b.month}月${b.day}日${age != null ? '（${age}岁）' : ''}',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: _editBirthday,
          borderRadius: BorderRadius.circular(8),
          child: Text('修改',
              style: TextStyle(fontSize: 12, color: AppColors.accent)),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: _clearBirthday,
          borderRadius: BorderRadius.circular(8),
          child: Text('清除',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ),
      ],
    );
  }

  Widget _buildGenderRow() {
    return Row(
      children: [
        Icon(Icons.wc_outlined, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text('性别', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(width: 12),
        SegmentedButton<UserGender>(
          selected: {_profile.gender},
          onSelectionChanged: (set) {
            final g = set.first;
            if (g == _profile.gender) return;
            final updated = _profile.copyWith(gender: g);
            UserProfileService.save(updated);
            setState(() => _profile = updated);
          },
          style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: UserGender.male, label: Text('男')),
            ButtonSegment(value: UserGender.female, label: Text('女')),
            ButtonSegment(value: UserGender.unknown, label: Text('保密')),
          ],
        ),
      ],
    );
  }

  Future<void> _editBirthday() async {
    final initial =
        _profile.birthday ?? DateTime(DateTime.now().year - 18, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('zh', 'CN'),
      helpText: '选择你的生日',
      confirmText: '确定',
      cancelText: '取消',
    );
    if (picked != null && mounted) {
      final updated = _profile.copyWith(birthday: picked);
      await UserProfileService.save(updated);
      setState(() => _profile = updated);
    }
  }

  Future<void> _clearBirthday() async {
    final updated = _profile.copyWith(clearBirthday: true);
    await UserProfileService.save(updated);
    setState(() => _profile = updated);
  }

  Widget _buildStats() {
    if (_statsLocked) {
      return _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('写信统计', style: _sectionTitle()),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.lock_outline, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '数据已加密，输入主密码后查看统计。',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  ),
                ),
                TextButton(
                  onPressed: _unlock,
                  child: Text('解锁', style: TextStyle(color: AppColors.accent)),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final items = [
      _statTile('信件', _stats.letters.toString(), Icons.mail_outline),
      _statTile('消息', _stats.messages.toString(), Icons.chat_bubble_outline),
      _statTile('字数', _stats.chars.toString(), Icons.text_fields),
      _statTile('记忆', memoryState.count.toString(), Icons.auto_awesome_outlined),
    ];

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('写信统计', style: _sectionTitle()),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.1,
            children: items,
          ),
        ],
      ),
    );
  }

  Widget _buildPersonaCard() {
    return AnimatedBuilder(
      animation: activePersona,
      builder: (_, __) {
        final name = activePersona.persona?.name ?? '林离';
        final custom = activePersona.config.customPrompt != null;
        return _card(
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.face_outlined, size: 26, color: AppColors.accent),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('当前 AI 人设', style: _sectionTitle()),
                    const SizedBox(height: 4),
                    Text(
                      '$name${custom ? '（自定义提示词）' : '（内置）'}',
                      style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSecurity() {
    return _card(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('安全', style: _sectionTitle()),
                const SizedBox(height: 4),
                Text(
                  '清除本机记住的主密码，下次启动需重新输入。',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: _clearAutoUnlock,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.divider),
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('清除自动解锁'),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: child,
    );
  }

  Widget _statTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: AppColors.accent),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  TextStyle _sectionTitle() =>
      TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary);
}
