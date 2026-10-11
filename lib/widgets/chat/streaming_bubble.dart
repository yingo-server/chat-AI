import 'package:flutter/material.dart';

import '../animation/message_animations.dart';

/// 流式回复的气泡 — 内置打字光标
/// 显示当前已缓冲的可见文本 + 闪烁光标
class StreamingBubble extends StatelessWidget {
  final String text;
  final bool finished;
  const StreamingBubble({super.key, required this.text, this.finished = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurface,
                            height: 1.55,
                          ),
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

/// 打字三点(M3 ProgressIndicator 简化版,完全用 Material 组件)
class TypingIndicator extends StatelessWidget {
  const TypingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Card(
        color: scheme.surfaceContainerHigh,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('正在思考…'),
            ],
          ),
        ),
      ),
    );
  }
}