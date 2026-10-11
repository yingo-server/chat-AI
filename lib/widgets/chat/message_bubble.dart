import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/chat.dart';
import 'user_identity.dart';

/// 单条消息的气泡(Material 3 风格,无自绘)
/// 用户消息 = Filled Card + primaryContainer 背景
/// 助手消息 = Filled Card + surfaceContainer
class MessageBubble extends StatelessWidget {
  final Message message;
  final bool showHeader;
  final MessageDelivery delivery;
  final VoidCallback? onRetry;
  final VoidCallback? onCopy;
  final VoidCallback? onShare;

  const MessageBubble({
    super.key,
    required this.message,
    this.showHeader = true,
    this.delivery = MessageDelivery.completed,
    this.onRetry,
    this.onCopy,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isUser = message.role == MessageRole.user;

    final bg =
        isUser ? scheme.primaryContainer : scheme.surfaceContainerHigh;
    final fg = isUser ? scheme.onPrimaryContainer : scheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.86,
        ),
        child: Card(
          color: bg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(isUser ? 20 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 20),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showHeader)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      UserIdentity(role: message.role, name: _displayName(isUser)),
                      Row(
                        children: [
                          if (delivery != MessageDelivery.completed)
                            MessageStatusChip(status: delivery),
                          PopupMenuButton<String>(
                            tooltip: '操作',
                            icon: Icon(Icons.more_horiz, color: fg),
                            onSelected: (v) {
                              switch (v) {
                                case 'copy':
                                  Clipboard.setData(
                                      ClipboardData(text: message.content));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('已复制到剪贴板'),
                                          behavior: SnackBarBehavior.floating));
                                  onCopy?.call();
                                  break;
                                case 'share':
                                  onShare?.call();
                                  break;
                                case 'retry':
                                  onRetry?.call();
                                  break;
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                  value: 'copy',
                                  child: ListTile(
                                      leading: Icon(Icons.copy),
                                      title: Text('复制'))),
                              const PopupMenuItem(
                                  value: 'share',
                                  child: ListTile(
                                      leading: Icon(Icons.ios_share),
                                      title: Text('分享'))),
                              if (isUser && onRetry != null)
                                const PopupMenuItem(
                                    value: 'retry',
                                    child: ListTile(
                                        leading: Icon(Icons.refresh),
                                        title: Text('重发'))),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                if (showHeader) const SizedBox(height: 4),
                // 文本块(自渲染,这里依然用 flutter_markdown;若要 100% Material,可换 SelectionArea + Text)
                SelectionArea(
                  child: Text(
                    message.content.isEmpty ? ' ' : message.content,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: fg,
                      height: 1.55,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      _formatTime(message.createdAt),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: fg.withValues(alpha: 0.55)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _displayName(bool isUser) => isUser ? '我' : 'AI 助手';

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '今天 $hh:$mm';
    }
    return '${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} $hh:$mm';
  }
}