import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/chat.dart';
import '../error_code.dart';
import 'user_identity.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    try {
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
              maxWidth: MediaQuery.of(context).size.width * 0.86),
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
                  SelectionArea(
                    child: Text(
                      message.content.isEmpty ? ' ' : message.content,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: fg, height: 1.55),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: '复制',
                        icon: Icon(Icons.copy, size: 16, color: fg),
                        onPressed: () {
                          try {
                            Clipboard.setData(
                                ClipboardData(text: message.content));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                behavior: SnackBarBehavior.floating,
                                content: Text('已复制'),
                              ),
                            );
                          } on AppError {
                            rethrow;
                          } catch (e, st) {
                            throw AppError(Ec.pf04.code, Ec.pf04.message,
                                cause: e, stack: st);
                          }
                        },
                      ),
                      Text(
                        _formatTime(message.createdAt),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: fg.withOpacity(0.55)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e, st) {
      throw AppError(Ec.wd00.code, Ec.wd00.message, cause: e, stack: st);
    }
  }

  String _formatTime(DateTime t) {
    try {
      final hh = t.hour.toString().padLeft(2, '0');
      final mm = t.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    } catch (e, st) {
      throw AppError(Ec.ut03.code, Ec.ut03.message, cause: e, stack: st);
    }
  }
}