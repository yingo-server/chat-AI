import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/chat.dart';
import '../../theme/spacing.dart';

/// 单条消息气泡 — 严格按 M3:
/// - 角色 → 色彩角色(user: primaryContainer / assistant: surfaceContainerHighest)
/// - 形状刻度:large(16) + 尾部 extra-small(4)
/// - Card 必须裁剪,否则 InkWell 波纹会溢出圆角
/// - 时间戳使用 bodySmall + onSurfaceVariant(可读性达标),并做本地时区/跨日处理
class MessageBubble extends StatelessWidget {
  final Message message;
  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    // 非对话消息(系统/压缩摘要)不出现在气泡列表里
    if (message.role != MessageRole.user &&
        message.role != MessageRole.assistant) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final isUser = message.role == MessageRole.user;

    final bg = isUser ? s.primaryContainer : s.surfaceContainerHighest;
    final fg = isUser ? s.onPrimaryContainer : s.onSurface;
    final metaFg = isUser ? s.onPrimaryContainer : s.onSurfaceVariant;

    const r16 = Radius.circular(16);
    const r4 = Radius.circular(4);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.86,
        ),
        child: Card(
          color: bg,
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          margin: const EdgeInsets.symmetric(vertical: Gap.xs),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: r16,
              topRight: r16,
              bottomLeft: isUser ? r16 : r4,
              bottomRight: isUser ? r4 : r16,
            ),
          ),
          child: InkWell(
            // M3:长按 → 复制(与系统上下文菜单习惯一致)
            onLongPress: () => _copy(context),
            child: Padding(
              padding: Insets.bubble,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectionArea(
                    child: Text(
                      message.content.isEmpty ? ' ' : message.content,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(color: fg, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: Gap.xs),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _formatTime(message.createdAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: metaFg),
                        ),
                      ),
                      const SizedBox(width: Gap.xs),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: '复制',
                        iconSize: 16,
                        color: metaFg,
                        icon: const Icon(Icons.copy_rounded),
                        onPressed: () => _copy(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _copy(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    Clipboard.setData(ClipboardData(text: message.content));
    messenger
      ?..removeCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已复制')));
  }

  /// 本地时区;今天只显示时间,跨日补日期,避免歧义
  String _formatTime(DateTime t) {
    final local = t.toLocal();
    final now = DateTime.now();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final sameDay =
        local.year == now.year && local.month == now.month && local.day == now.day;
    if (sameDay) return '$hh:$mm';
    final md = '${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    return '$md $hh:$mm';
  }
}
