import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/chat.dart';
import '../../theme/spacing.dart';
import 'markdown_renderer.dart';

/// 单条消息气泡
/// 用户消息按纯文本渲染(输入即所见);助手消息按 Markdown 渲染。
class MessageBubble extends StatelessWidget {
  final Message message;
  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
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
            onLongPress: () => _copy(context),
            child: Padding(
              padding: Insets.bubble,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isUser)
                    SelectionArea(
                      child: Text(
                        message.content.isEmpty ? ' ' : message.content,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: fg, height: 1.5),
                      ),
                    )
                  else
                    MarkdownText(
                      message.content,
                      // 助手消息继承气泡文字色
                      textStyle: theme.textTheme.bodyLarge
                          ?.copyWith(color: fg, height: 1.5),
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

  String _formatTime(DateTime t) {
    final local = t.toLocal();
    final now = DateTime.now();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final sameDay = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (sameDay) return '$hh:$mm';
    final md = '${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    return '$md $hh:$mm';
  }
}
