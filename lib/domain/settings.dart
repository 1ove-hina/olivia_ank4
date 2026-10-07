/// 应用设置（P1）：API 连接凭据，设备级静默加密持久化
class AppSettings {
  final String baseUrl;
  final String apiKey;
  final String chatModel;
  final String embeddingModel;
  // Beta2：界面主题，取值 'system' | 'light' | 'dark'，默认 'dark' 保持现状
  final String themeMode;
  // Beta2：最小化到系统栏（默认开启）。开启后最小化按钮收进通知栏后台运行，
  // 关闭(X)仍直接退出；可在设置页关闭恢复传统最小化到任务栏。
  final bool minimizeToTray;
  // Beta3：自定义主题强调色（无极轮盘调色）。'#RRGGBB'，空串表示使用默认主题色。
  final String accentColor;

  const AppSettings({
    this.baseUrl = '',
    this.apiKey = '',
    this.chatModel = '',
    this.embeddingModel = '',
    this.themeMode = 'dark',
    this.minimizeToTray = true,
    this.accentColor = '',
  });

  AppSettings copyWith({
    String? baseUrl,
    String? apiKey,
    String? chatModel,
    String? embeddingModel,
    String? themeMode,
    bool? minimizeToTray,
    String? accentColor,
  }) =>
      AppSettings(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        chatModel: chatModel ?? this.chatModel,
        embeddingModel: embeddingModel ?? this.embeddingModel,
        themeMode: themeMode ?? this.themeMode,
        minimizeToTray: minimizeToTray ?? this.minimizeToTray,
        accentColor: accentColor ?? this.accentColor,
      );

  Map<String, String> toJson() => {
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'chatModel': chatModel,
        'embeddingModel': embeddingModel,
        'themeMode': themeMode,
        'minimizeToTray': minimizeToTray ? '1' : '0',
        'accentColor': accentColor,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        baseUrl: json['baseUrl'] as String? ?? '',
        apiKey: json['apiKey'] as String? ?? '',
        chatModel: json['chatModel'] as String? ?? '',
        embeddingModel: json['embeddingModel'] as String? ?? '',
        themeMode: json['themeMode'] as String? ?? 'dark',
        minimizeToTray: json['minimizeToTray'] == '1' ||
            (json['minimizeToTray'] is bool && json['minimizeToTray'] == true),
        accentColor: json['accentColor'] as String? ?? '',
      );

  static const AppSettings empty = AppSettings();
}
