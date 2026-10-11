import 'package:flutter/material.dart';

import '../../models/chat.dart';

/// 头像 + 名字 + 角色标签(M3 风格)
class UserIdentity extends StatelessWidget {
  final MessageRole role;
  final String name;
  final bool compact;

  const UserIdentity({
    super.key,
    required this.role,
    required this.name,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = role == MessageRole.user;
    final bg = isUser ? scheme.tertiaryContainer : scheme.secondaryContainer;
    final fg = isUser ? scheme.onTertiaryContainer : scheme.onSecondaryContainer;
    final iconData =
        isUser ? Icons.person : Icons.smart_toy_outlined;
    final roleLabel = isUser ? '我' : 'AI';
    final radius = compact ? 14.0 : 18.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: bg,
          foregroundColor: fg,
          child: Icon(iconData, size: radius * 1.3),
        ),
        if (!compact) ...[
          const SizedBox(width: 8),
          Text(
            name,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(width: 6),
          Chip(
            visualDensity: VisualDensity.compact,
            backgroundColor: bg,
            side: BorderSide.none,
            label: Text(roleLabel,
                style: TextStyle(color: fg, fontSize: 11)),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ],
    );
  }
}

/// 消息状态徽标 — "发送中 / 失败 / 已完成"
enum MessageDelivery { pending, failed, completed }

class MessageStatusChip extends StatelessWidget {
  final MessageDelivery status;
  const MessageStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    late final IconData icon;
    late final Color color;
    late final String label;
    switch (status) {
      case MessageDelivery.pending:
        icon = Icons.schedule;
        color = scheme.outline;
        label = '发送中';
        break;
      case MessageDelivery.failed:
        icon = Icons.error_outline;
        color = scheme.error;
        label = '失败';
        break;
      case MessageDelivery.completed:
        icon = Icons.check_circle_outline;
        color = scheme.primary;
        label = '已送达';
        break;
    }
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: color.withValues(alpha: 0.10),
      side: BorderSide(color: color.withValues(alpha: 0.30)),
      avatar: Icon(icon, color: color, size: 14),
      label: Text(label, style: TextStyle(color: color, fontSize: 11)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}