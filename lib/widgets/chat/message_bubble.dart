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
              // 用户气泡水平略收(14),短消息更紧凑;助手保持 16
              padding: isUser ? Insets.bubbleUser : Insets.bubble,
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
                      textStyle: theme.textTheme.bodyLarge
                          ?.copyWith(color: fg, height: 1.5),
                    ),
                  // 元信息行:时间戳 + 复制按钮。
                  // - 与正文之间 8dp;
                  // - 用 48dp 触达区(InkWell)包住 24dp 视觉图标,兼顾 M3 无障碍;
                  // - 负 margin 抵消多出的 12dp,使视觉重心仍与正文左缘对齐。
                  const SizedBox(height: Gap.sm),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        _formatTime(message.createdAt),
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: metaFg),
                      ),
                      const SizedBox(width: Gap.xs),
                      SizedBox(
                        width: Gap.minTouchTarget,
                        height: Gap.minTouchTarget,
                        child: Align(
                          alignment: Alignment.center,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _copy(context),
                            child: Padding(
                              padding: const EdgeInsets.all(Gap.md),
                              child: Icon(
                                Icons.copy_rounded,
                                size: 14,
                                color: metaFg,
                              ),
                            ),
                          ),
                        ),
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
