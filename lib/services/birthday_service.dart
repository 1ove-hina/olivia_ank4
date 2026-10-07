import 'package:olivia_ank4/domain/models.dart';
import 'package:olivia_ank4/services/crypto_service.dart';
import 'package:olivia_ank4/services/letter_service.dart';
import 'package:olivia_ank4/services/llm_service.dart';
import 'package:olivia_ank4/services/persona_service.dart';
import 'package:olivia_ank4/services/settings_service.dart';
import 'package:olivia_ank4/services/user_profile_service.dart';

/// 生日系统：在用户生日当天，林离会主动写一封生日信到信箱。
///
/// - 启动（解锁后）检测：今天是否生日 + 今年是否已送过。
/// - 满足条件则调用 LLM（生效人设的 systemPrompt）生成一封生日祝福信，
///   以 assistant 消息写入一封新信件，并标记今年已送。
/// - 幂等：进程内只尝试一次；网络/配置失败则静默跳过（保留未送标记，下次启动重试），
///   不阻断应用启动。
/// - 纯判定逻辑（isBirthday / alreadyGreeted）抽出便于单测，不依赖 IO。
class BirthdayService {
  static bool _initialized = false;
  final List<void Function(Letter)> _listeners = [];
  static final BirthdayService instance = BirthdayService._();
  BirthdayService._();

  /// 订阅「林离写好生日信」事件，供信箱实时刷新
  void addListener(void Function(Letter) cb) => _listeners.add(cb);
  void removeListener(void Function(Letter) cb) => _listeners.remove(cb);

  /// 纯函数：今天是否为该生日（只比对月/日，与年份无关）
  static bool isBirthday(DateTime? birthday, DateTime today) {
    if (birthday == null) return false;
    return birthday.month == today.month && birthday.day == today.day;
  }

  /// 纯函数：今年是否已送过生日信
  static bool alreadyGreeted(int? lastYear, int thisYear) =>
      lastYear == thisYear;

  /// 启动入口：返回新建的生日信（未触发则为 null）。
  static Future<Letter?> checkAndSend() async {
    if (_initialized) return null;
    _initialized = true;

    final pass = CryptoService.sessionPassphrase;
    if (pass == null) return null; // 锁定态：无密码无法解密信箱，跳过

    final profile = await UserProfileService.load();
    final today = DateTime.now();
    if (!isBirthday(profile.birthday, today)) return null;
    if (alreadyGreeted(profile.lastBirthdayGreetYear, today.year)) return null;

    // 需要 API 配置才能写信
    final settings = await SettingsService.load(pass);
    if (settings == null) {
      _initialized = false; // 配置缺失，下次启动再试
      return null;
    }

    // 取生效人设（与 AppShell._initPersona 保持一致）
    final builtin = await PersonaService.loadDefault();
    final cfg = await PersonaService.loadConfig();
    final persona = Persona(
      id: cfg.selectedPersonaId,
      name: builtin.name,
      source: cfg.customPrompt != null
          ? PersonaSource.custom
          : PersonaSource.builtin,
      systemPrompt: cfg.customPrompt ?? builtin.systemPrompt,
      createdAt: builtin.createdAt,
    );

    final nickname = profile.nickname;
    final userLetter = '今天是$nickname的生日。请以「${persona.name}」的身份，'
        '给$nickname写一封真诚、温柔的生日祝福信，可以聊聊这一年的陪伴与回忆，'
        '并送上对未来的期许。用书信口吻，落款写你的名字。'
        '直接开始写正文，不要任何额外格式或标题。';

    try {
      final reply = await LLMService.chat(
        settings: settings,
        systemPrompt: persona.systemPrompt,
        userLetter: userLetter,
      );

      final now = DateTime.now();
      final letter = Letter(
        id: LetterService.newId(),
        title: '🎂 给$nickname的生日信',
        personaId: persona.id,
        messages: [
          Message(role: 'assistant', content: reply, createdAt: now),
        ],
        createdAt: now,
        updatedAt: now,
      );
      await LetterService.save(letter);

      // 标记今年已送，避免同日重复投递
      await UserProfileService.save(
        profile.copyWith(lastBirthdayGreetYear: now.year),
      );

      for (final cb in List.from(instance._listeners)) {
        cb(letter);
      }
      return letter;
    } catch (_) {
      // 生成失败：保留未送标记，下次启动重试
      _initialized = false;
      return null;
    }
  }
}
