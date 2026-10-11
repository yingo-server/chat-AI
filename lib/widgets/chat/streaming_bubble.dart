import 'package:flutter/material.dart';

import '../animation/message_animations.dart';

/// 流式占位气泡 — 跟随 theme 字号
class StreamingBubble extends StatelessWidget {
  final String text;
  final bool finished;
  const StreamingBubble({super.key, required this.text, this.finished = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.86),
        child: Card(
          color: scheme.surfaceContainerHigh,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: SelectionArea(
                    child: Text(
                      text.isEmpty ? ' ' : text,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurface, height: 1.55),
                    ),
                  ),
                ),
                if (!finished)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: BlinkingCursor(
                      height: 16,
                      color: scheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}