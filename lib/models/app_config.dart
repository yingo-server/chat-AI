import 'dart:convert';
import 'package:flutter/foundation.dart';

/// 配置结构 — 完全对应 assets/config.example.json
class AppConfig {
  final AiConfig ai;
  final ContextConfig context;
  final List<RecurringPrompt> recurringPrompts;
  final List<SystemPrompt> systemPrompts;

  AppConfig({
    required this.ai,
    required this.context,
    required this.recurringPrompts,
    required this.systemPrompts,
  });

  factory AppConfig.empty() => AppConfig(
        ai: AiConfig.empty(),
        context: ContextConfig.empty(),
        recurringPrompts: const [],
        systemPrompts: [SystemPrompt.defaultPrompt()],
      );

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final ai = AiConfig.fromJson(json['ai'] as Map<String, dynamic>? ?? {});
    final ctx = ContextConfig.fromJson(
        json['context'] as Map<String, dynamic>? ?? {});
    final rp = (json['recurringPrompts'] as List? ?? const [])
        .map((e) => RecurringPrompt.fromJson(e as Map<String, dynamic>))
        .toList();
    final sp = (json['systemPrompts'] as List? ?? const [])
        .map((e) => SystemPrompt.fromJson(e as Map<String, dynamic>))
        .toList();
    return AppConfig(
      ai: ai,
      context: ctx,
      recurringPrompts: rp,
      systemPrompts: sp,
    );
  }

  Map<String, dynamic> toJson() => {
        'ai': ai.toJson(),
        'context': context.toJson(),
        'recurringPrompts': recurringPrompts.map((e) => e.toJson()).toList(),
        'systemPrompts': systemPrompts.map((e) => e.toJson()).toList(),
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  AppConfig copyWith({
    AiConfig? ai,
    ContextConfig? context,
    List<RecurringPrompt>? recurringPrompts,
    List<SystemPrompt>? systemPrompts,
  }) =>
      AppConfig(
        ai: ai ?? this.ai,
        context: context ?? this.context,
        recurringPrompts: recurringPrompts ?? this.recurringPrompts,
        systemPrompts: systemPrompts ?? this.systemPrompts,
      );

  SystemPrompt? promptById(String id) {
    for (final p in systemPrompts) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 给定会话的"已发生轮次数",筛出本轮应注入的周期提示词(轮询模式)
  ///
  /// 轮询规则:
  /// - 每条提示词 `intervalTurns` 表示该提示词"最小间隔轮数"
  /// - 同一会话的注入历史用一个 round-robin 计数器维护(外部传入 [_cursor])
  /// - 若提示词上次注入到现在 < intervalTurns,则跳过,继续轮到下一个
  List<RecurringPrompt> promptsForTurn({
    required int turnsCompleted,
    required int cursor,
    required Map<String, int> lastInjectedTurn, // id -> 上次注入的轮数
  }) {
    final enabled = recurringPrompts.where((p) => p.enabled).toList();
    if (enabled.isEmpty) return const [];

    // 从 cursor 开始顺序扫描,挑出第一个满足"间隔允许"的
    final out = <RecurringPrompt>[];
    var i = cursor % enabled.length;
    var scanned = 0;
    while (scanned < enabled.length) {
      final p = enabled[i];
      final last = lastInjectedTurn[p.id] ?? -10000;
      if (turnsCompleted - last >= p.intervalTurns) {
        out.add(p);
        lastInjectedTurn[p.id] = turnsCompleted;
        // 指针后移一位,留给下次
        return out;
      }
      i = (i + 1) % enabled.length;
      scanned++;
    }
    return const [];
  }
}

class AiConfig {
  final String endpoint;
  final String apiKey;
  final String model;
  final double temperature;
  final int maxTokens;
  final int requestTimeoutSeconds;
  final double streamCharsPerSecond; // 流式输出节流速率

  AiConfig({
    required this.endpoint,
    required this.apiKey,
    required this.model,
    required this.temperature,
    required this.maxTokens,
    required this.requestTimeoutSeconds,
    required this.streamCharsPerSecond,
  });

  factory AiConfig.empty() => AiConfig(
        endpoint: '',
        apiKey: '',
        model: 'gpt-4o-mini',
        temperature: 0.7,
        maxTokens: 2048,
        requestTimeoutSeconds: 120,
        streamCharsPerSecond: 24, // ~每秒 24 字,自然阅读节奏
      );

  factory AiConfig.fromJson(Map<String, dynamic> j) => AiConfig(
        endpoint: j['endpoint'] as String? ?? '',
        apiKey: j['apiKey'] as String? ?? '',
        model: j['model'] as String? ?? 'gpt-4o-mini',
        temperature: (j['temperature'] as num? ?? 0.7).toDouble(),
        maxTokens: j['maxTokens'] as int? ?? 2048,
        requestTimeoutSeconds: j['requestTimeoutSeconds'] as int? ?? 120,
        streamCharsPerSecond:
            (j['streamCharsPerSecond'] as num? ?? 24).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'endpoint': endpoint,
        'apiKey': apiKey,
        'model': model,
        'temperature': temperature,
        'maxTokens': maxTokens,
        'requestTimeoutSeconds': requestTimeoutSeconds,
        'streamCharsPerSecond': streamCharsPerSecond,
      };

  bool get isValid => endpoint.isNotEmpty && apiKey.isNotEmpty;

  AiConfig copyWith({
    String? endpoint,
    String? apiKey,
    String? model,
    double? temperature,
    int? maxTokens,
    int? requestTimeoutSeconds,
    double? streamCharsPerSecond,
  }) =>
      AiConfig(
        endpoint: endpoint ?? this.endpoint,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        temperature: temperature ?? this.temperature,
        maxTokens: maxTokens ?? this.maxTokens,
        requestTimeoutSeconds:
            requestTimeoutSeconds ?? this.requestTimeoutSeconds,
        streamCharsPerSecond:
            streamCharsPerSecond ?? this.streamCharsPerSecond,
      );
}

class ContextConfig {
  final int maxContextMessages;
  final int compressTriggerMessages;
  final int keepRecentMessages;
  final String compressPrompt;
  final String compressModel;

  ContextConfig({
    required this.maxContextMessages,
    required this.compressTriggerMessages,
    required this.keepRecentMessages,
    required this.compressPrompt,
    required this.compressModel,
  });

  factory ContextConfig.empty() => ContextConfig(
        maxContextMessages: 40,
        compressTriggerMessages: 30,
        keepRecentMessages: 12,
        compressPrompt: '请把以下对话历史压缩成客观摘要,保留关键事实和约定,不超过 300 字。',
        compressModel: '',
      );

  factory ContextConfig.fromJson(Map<String, dynamic> j) => ContextConfig(
        maxContextMessages: j['maxContextMessages'] as int? ?? 40,
        compressTriggerMessages: j['compressTriggerMessages'] as int? ?? 30,
        keepRecentMessages: j['keepRecentMessages'] as int? ?? 12,
        compressPrompt: j['compressPrompt'] as String? ??
            '请把以下对话历史压缩成客观摘要,保留关键事实和约定,不超过 300 字。',
        compressModel: j['compressModel'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'maxContextMessages': maxContextMessages,
        'compressTriggerMessages': compressTriggerMessages,
        'keepRecentMessages': keepRecentMessages,
        'compressPrompt': compressPrompt,
        'compressModel': compressModel,
      };

  ContextConfig copyWith({
    int? maxContextMessages,
    int? compressTriggerMessages,
    int? keepRecentMessages,
    String? compressPrompt,
    String? compressModel,
  }) =>
      ContextConfig(
        maxContextMessages: maxContextMessages ?? this.maxContextMessages,
        compressTriggerMessages:
            compressTriggerMessages ?? this.compressTriggerMessages,
        keepRecentMessages: keepRecentMessages ?? this.keepRecentMessages,
        compressPrompt: compressPrompt ?? this.compressPrompt,
        compressModel: compressModel ?? this.compressModel,
      );
}

class RecurringPrompt {
  final String id;
  final String content;
  final int intervalTurns;
  final bool enabled;
  final PromptRotation rotation; // 轮询模式

  RecurringPrompt({
    required this.id,
    required this.content,
    required this.intervalTurns,
    required this.enabled,
    required this.rotation,
  });

  factory RecurringPrompt.fromJson(Map<String, dynamic> j) => RecurringPrompt(
        id: j['id'] as String,
        content: j['content'] as String,
        intervalTurns: j['intervalTurns'] as int,
        enabled: j['enabled'] as bool? ?? true,
        rotation: PromptRotation.values.firstWhere(
          (r) => r.name == (j['rotation'] as String? ?? 'roundRobin'),
          orElse: () => PromptRotation.roundRobin,
        ),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'intervalTurns': intervalTurns,
        'enabled': enabled,
        'rotation': rotation.name,
      };

  RecurringPrompt copyWith({
    String? content,
    int? intervalTurns,
    bool? enabled,
    PromptRotation? rotation,
  }) =>
      RecurringPrompt(
        id: id,
        content: content ?? this.content,
        intervalTurns: intervalTurns ?? this.intervalTurns,
        enabled: enabled ?? this.enabled,
        rotation: rotation ?? this.rotation,
      );
}

/// 轮询模式
enum PromptRotation {
  /// 多条提示词按顺序轮流注入(默认)
  roundRobin,

  /// 全部并行注入(用户希望同时生效)
  all,

  /// 随机注入一条
  random,
}

class SystemPrompt {
  final String id;
  final String name;
  final String content;

  SystemPrompt({required this.id, required this.name, required this.content});

  factory SystemPrompt.defaultPrompt() => SystemPrompt(
        id: 'default',
        name: '默认助手',
        content: '你是一个 helpful 的中文助手。回答简洁、准确。',
      );

  factory SystemPrompt.fromJson(Map<String, dynamic> j) => SystemPrompt(
        id: j['id'] as String,
        name: j['name'] as String,
        content: j['content'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'content': content,
      };
}

class ConfigController extends ChangeNotifier {
  AppConfig _config = AppConfig.empty();
  AppConfig get config => _config;

  /// 全局轮询游标 + 每条提示词上次注入轮数 — 由 ChatService 维护
  int _cursor = 0;
  int get cursor => _cursor;
  void rotateCursor() {
    _cursor = (_cursor + 1) % 9999;
    notifyListeners();
  }

  void replace(AppConfig next) {
    _config = next;
    notifyListeners();
  }

  void updateAi(AiConfig ai) {
    _config = _config.copyWith(ai: ai);
    notifyListeners();
  }

  void updateContext(ContextConfig ctx) {
    _config = _config.copyWith(context: ctx);
    notifyListeners();
  }

  void updateRecurring(List<RecurringPrompt> list) {
    _config = _config.copyWith(recurringPrompts: list);
    notifyListeners();
  }

  void updatePrompts(List<SystemPrompt> list) {
    _config = _config.copyWith(systemPrompts: list);
    notifyListeners();
  }
}

/// 提示词调度器 — 跟踪每条提示词的上次注入轮数,返回本轮应注入的提示词
class PromptScheduler {
  final Map<String, int> _lastInjectedTurn = {};
  int _cursor = 0;

  /// 当前轮询游标(只读)
  int get cursor => _cursor;

  /// 每条提示词上次注入的轮数
  Map<String, int> get lastInjectedTurn =>
      Map.unmodifiable(_lastInjectedTurn);

  /// 每轮调用一次。
  /// [turnsCompleted] 已完成的"用户-助手"对数(0 起算)。
  /// 返回本轮要注入的列表(可能为空)。
  List<RecurringPrompt> pick(AppConfig cfg, int turnsCompleted) {
    final pool =
        cfg.recurringPrompts.where((p) => p.enabled).toList(growable: false);
    if (pool.isEmpty) return const [];

    switch (pool.first.rotation) {
      case PromptRotation.roundRobin:
        return _pickRoundRobin(pool, turnsCompleted);
      case PromptRotation.all:
        // 全部注入
        for (final p in pool) {
          _lastInjectedTurn[p.id] = turnsCompleted;
        }
        return List.unmodifiable(pool);
      case PromptRotation.random:
        // 随机一条(若全部都满足间隔)
        final allowed = pool.where((p) {
          final last = _lastInjectedTurn[p.id] ?? -10000;
          return turnsCompleted - last >= p.intervalTurns;
        }).toList();
        if (allowed.isEmpty) return const [];
        final pick = (allowed..shuffle()).first;
        _lastInjectedTurn[pick.id] = turnsCompleted;
        return [pick];
    }
  }

  List<RecurringPrompt> _pickRoundRobin(
      List<RecurringPrompt> pool, int turnsCompleted) {
    final out = <RecurringPrompt>[];
    var i = _cursor % pool.length;
    var scanned = 0;
    while (scanned < pool.length) {
      final p = pool[i];
      final last = _lastInjectedTurn[p.id] ?? -10000;
      if (turnsCompleted - last >= p.intervalTurns) {
        out.add(p);
        _lastInjectedTurn[p.id] = turnsCompleted;
        _cursor = (i + 1) % pool.length;
        return out;
      }
      i = (i + 1) % pool.length;
      scanned++;
    }
    return const [];
  }

  /// 重置(切换会话时调用)
  void reset() {
    _lastInjectedTurn.clear();
    _cursor = 0;
  }
}