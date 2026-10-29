/// 消息角色
enum MessageRole {
  system,
  user,
  assistant,
  compressed; // 压缩摘要占位,不直接展示,仅参与上下文

  String get apiRole {
    switch (this) {
      case MessageRole.system: return 'system';
      case MessageRole.user: return 'user';
      case MessageRole.assistant: return 'assistant';
      case MessageRole.compressed: return 'system'; // 注入为 system 消息
    }
  }
}

/// 单条消息
class Message {
  final int? id;
  final int chatId;
  final MessageRole role;
  final String content;
  final DateTime createdAt;

  /// 原始 token 数(可选,若服务端回传则记录)
  final int? tokenCount;

  /// 是否已被压缩 — true 表示被旧的摘要取代,UI 不再显示
  final bool compressed;

  Message({
    this.id,
    required this.chatId,
    required this.role,
    required this.content,
    DateTime? createdAt,
    this.tokenCount,
    this.compressed = false,
  }) : createdAt = createdAt ?? DateTime.now();

  Message copyWith({
    int? id,
    int? chatId,
    MessageRole? role,
    String? content,
    DateTime? createdAt,
    int? tokenCount,
    bool? compressed,
  }) {
    return Message(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      tokenCount: tokenCount ?? this.tokenCount,
      compressed: compressed ?? this.compressed,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'chat_id': chatId,
        'role': role.name,
        'content': content,
        'created_at': createdAt.millisecondsSinceEpoch,
        'token_count': tokenCount,
        'compressed': compressed ? 1 : 0,
      };

  factory Message.fromMap(Map<String, dynamic> m) => Message(
        id: m['id'] as int?,
        chatId: m['chat_id'] as int,
        role: MessageRole.values.firstWhere((r) => r.name == m['role'],
            orElse: () => MessageRole.assistant),
        content: m['content'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (m['created_at'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch),
        tokenCount: m['token_count'] as int?,
        compressed: (m['compressed'] as int? ?? 0) == 1,
      );
}

/// 一个对话
class Chat {
  final int? id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 当前使用的系统提示词 ID(关联到 config.json)
  final String systemPromptId;

  /// 自定义追加在该对话上的系统提示词(仅本对话生效)
  final String? extraSystemPrompt;

  Chat({
    this.id,
    required this.title,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.systemPromptId = 'default',
    this.extraSystemPrompt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Chat copyWith({
    int? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? systemPromptId,
    String? extraSystemPrompt,
  }) {
    return Chat(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      systemPromptId: systemPromptId ?? this.systemPromptId,
      extraSystemPrompt: extraSystemPrompt ?? this.extraSystemPrompt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'system_prompt_id': systemPromptId,
        'extra_system_prompt': extraSystemPrompt,
      };

  factory Chat.fromMap(Map<String, dynamic> m) => Chat(
        id: m['id'] as int?,
        title: m['title'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (m['created_at'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
            (m['updated_at'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch),
        systemPromptId: m['system_prompt_id'] as String? ?? 'default',
        extraSystemPrompt: m['extra_system_prompt'] as String?,
      );
}