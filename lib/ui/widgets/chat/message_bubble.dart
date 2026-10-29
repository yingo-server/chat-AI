import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../domain/chat.dart';
import '../../../core/theme/spacing.dart';

/// 单条消息气泡
/// 用户消息按纯文本渲染(输入即所见);助手消息用 flutter_markdown 渲染。
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
                    MarkdownBody(
                      data: message.content,
                      selectable: true,
                      styleSheet:
                          MarkdownStyleSheet.fromTheme(theme).copyWith(
                        p: theme.textTheme.bodyLarge
                            ?.copyWith(color: fg, height: 1.5),
                        code: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          backgroundColor: s.surfaceContainerHighest,
                          color: s.onSurface,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: s.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: s.outlineVariant),
                        ),
                        codeblockPadding:
                            const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        blockquoteDecoration: BoxDecoration(
                          border: Border(
                              left: BorderSide(color: s.primary, width: 3)),
                        ),
                        h1: theme.textTheme.headlineSmall
                            ?.copyWith(color: s.onSurface),
                        h2: theme.textTheme.titleLarge
                            ?.copyWith(color: s.onSurface),
                        h3: theme.textTheme.titleMedium
                            ?.copyWith(color: s.onSurface),
                        listBullet: theme.textTheme.bodyLarge
                            ?.copyWith(color: fg),
                        tableBorder: TableBorder.all(color: s.outlineVariant),
                        tableHead: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
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
