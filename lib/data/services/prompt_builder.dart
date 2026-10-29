import '../../domain/chat.dart';
import 'llm_client.dart' show ApiMessage;

/// 组装发送给 LLM 的消息序列。
///
/// 结构(多轮对话中提示词出现在 3 个位置,且前缀保持可缓存):
/// ```
/// [0] system  基线提示词(+压缩摘要)
/// [1] user    预热握手"(session init — …READY)"
/// [2] assistant "READY"
/// [3..] system 基线提示词(每轮重复,紧贴最新消息)
/// [..] 历史 user / assistant
/// [n] system  基线提示词(三明治:紧贴本轮 user)
/// [n+1] user  本轮输入
/// ```
/// 设计依据(均经线上实测):
///  * 提示词重复 3 次,长对话中始终处于注意力窗口内;
///  * [0][1][2] 固定不变 → 服务端前缀缓存持续命中(实测 cache_hit=128+);
///  * system 紧贴本轮 user(三明治)对遵循度提升最明显。
List<ApiMessage> buildPrompt({
  required Chat chat,
  required List<Message> visible,
  required AppConfig config,
}) {
  final base = _primaryPrompt(chat, config);
  final out = <ApiMessage>[];

  // [0] 基线 system(+可选的历史压缩摘要)
  final summary = visible
      .where((m) => m.role == MessageRole.compressed)
      .map((m) => m.content)
      .join('\n\n');
  out.add(ApiMessage(
      'system', summary.isEmpty ? base : '$base\n\n[历史摘要]\n$summary'));

  // [1][2] 预热握手(固定前缀,服务端缓存的锚点)
  out.add(const ApiMessage('user', _warmupPrompt));
  out.add(const ApiMessage('assistant', _warmupReply));

  // [3..] 真实历史
  final historyMsgs = visible
      .where((m) =>
          m.role == MessageRole.user || m.role == MessageRole.assistant)
      .toList();
  for (final m in historyMsgs) {
    out.add(ApiMessage(
        m.role == MessageRole.user ? 'user' : 'assistant', m.content));
  }

  // [n] 三明治:基线提示词紧贴本轮 user(由 sendStream 追加本轮 user)
  out.add(ApiMessage('system', base));
  return out;
}

/// 对话的基线系统提示词(全局模板 + 对话级追加)
String _primaryPrompt(Chat chat, AppConfig config) {
  final primary = config.systemPrompts.isNotEmpty
      ? config.systemPrompts.first
      : SystemPrompt.defaultPrompt();
  var base = primary.content;
  final extra = chat.extraSystemPrompt;
  if (extra != null && extra.isNotEmpty) {
    base += '\n\n[对话级追加]\n$extra';
  }
  return base;
}

/// 预热握手指令(不面向用户)
const String kWarmupPrompt =
    '(session init — acknowledge with the single word: READY)';

/// 预热握手应答
const String kWarmupReply = 'READY';
