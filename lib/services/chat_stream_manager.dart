import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../models/app_config.dart';
import '../models/chat.dart';
import '../widgets/stream/stream_buffer.dart';
import 'chat_service.dart';

/// 应用级流式会话管理器。
///
/// 目的:把"流的所有权"从页面移到应用层,从而
///   1. 离开对话页后仍在后台继续流式输出并落库;
///   2. 多个对话可以同时流式输出(每个 chatId 一个会话);
///   3. 首页可以显示哪些对话"正在回复"。
///
/// 用法:
///   ChatStreamManager.instance.start(...)          // 发起
///   ChatStreamManager.instance.isBusy(chatId)      // 查询
///   ChatStreamManager.instance.partialOf(chatId)   // 读取实时文本
///   监听自身(ChangeNotifier)以在开始/结束时刷新界面
class ChatStreamManager extends ChangeNotifier {
  ChatStreamManager._();
  static final ChatStreamManager instance = ChatStreamManager._();

  final Map<int, _Session> _sessions = {};

  /// 每个对话复用同一个 ChatService —— 其中的 PromptScheduler 保存着
  /// 隐藏提示词的注入节奏;若每次发送都新建实例,节奏会被重置。
  final Map<int, ChatService> _services = {};
  final Map<int, AppConfig> _serviceConfig = {};

  ChatService _serviceFor(int chatId, AppConfig config) {
    final cached = _services[chatId];
    if (cached != null && identical(_serviceConfig[chatId], config)) {
      return cached;
    }
    final svc = ChatService(config);
    _services[chatId] = svc;
    _serviceConfig[chatId] = config;
    return svc;
  }

  /// 是否有会话正在流式输出
  bool isBusy(int chatId) => _sessions.containsKey(chatId);

  /// 任意会话是否在跑(首页用于显示汇总提示)
  bool get hasAny => _sessions.isNotEmpty;

  /// 正在流式的对话集合(首页打标用)
  Set<int> get activeChatIds => _sessions.keys.toSet();

  /// 实时文本(经限速缓冲,上限固定 100 字)
  ValueListenable<String>? partialOf(int chatId) => _sessions[chatId]?.partial;

  /// 会话是否已被请求停止(停止为协作式:不再向 UI 推送,但请求会自然结束)
  void cancel(int chatId) {
    // 立即从活动集合移除 → 界面马上停止流式显示;
    // 已发出的请求仍会自然结束并落库(HTTP 流无法中途 abort)。
    final s = _sessions.remove(chatId);
    if (s == null) return;
    s.cancelled = true;
    notifyListeners();
  }

  /// 发起一次流式请求。
  /// [alreadyPersistedUserText] 为 true 表示调用方已把用户消息写入数据库。
  Future<void> start({
    required Chat chat,
    required AppConfig config,
    required String userText,
    bool alreadyPersistedUserText = false,
  }) async {
    final id = chat.id;
    if (id == null) return;
    if (_sessions.containsKey(id)) return; // 同一对话同时只允许一个流

    final session = _Session(config.userPrefs.streamSpeed.toDouble());
    _sessions[id] = session;
    notifyListeners();

    final service = _serviceFor(id, config);
    try {
      final history = await AppDatabase.instance
          .listMessages(id, includeCompressed: false);
      await for (final _ in service.sendStream(
        chat: chat,
        history: history,
        userText: userText,
        alreadyPersistedUserText: alreadyPersistedUserText,
        onDelta: (d) {
          if (session.cancelled) return;
          session.buffer.add(d); // 限速 + 上限 100 字
        },
      )) {
        // 流结束(内容已在 sendStream 内落库)
      }
    } catch (e) {
      session.error = e.toString();
    } finally {
      // 冲刷剩余文本,先把最后一段交给界面,再移除会话
      try {
        await session.buffer.flush();
      } catch (_) {}
      _sessions.remove(id);
      notifyListeners();
      // 页面在收到通知后会用数据库内容替换流式占位,
      // 因此延后释放缓冲器,避免正在监听的组件访问已释放的 notifier。
      Future<void>.delayed(const Duration(seconds: 3), session.buffer.dispose);
    }
  }

  /// 最近一次错误(供页面提示)
  String? _lastError;
  String? get lastError => _lastError;
}

class _Session {
  _Session(double charsPerSecond)
      : buffer = StreamBuffer(
          charsPerSecond: charsPerSecond,
          maxBuffer: StreamBuffer.fixedMaxBuffer,
        );

  /// 限速 + 固定 100 字上限的缓冲器(抵抗网络抖动)
  final StreamBuffer buffer;
  ValueListenable<String> get partial => buffer.displayed;

  bool cancelled = false;
  String? error;
}
