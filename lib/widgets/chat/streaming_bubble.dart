import 'package:flutter/material.dart';

import '../animation/message_animations.dart';
import '../../theme/spacing.dart';

/// 流式输出中的助手气泡。
/// 与 MessageBubble 保持完全一致的形状/配色,避免流结束时"跳变";
/// 光标内联在文本末尾(WidgetSpan),换行时不会跑到最右侧。
class StreamingBubble extends StatelessWidget {
  final String text;
  final bool finished;
  const StreamingBubble({super.key, required this.text, this.finished = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = theme.colorScheme;

    if (text.isEmpty && finished) return const SizedBox.shrink();

    const r16 = Radius.circular(16);
    const r4 = Radius.circular(4);

    return Semantics(
      liveRegion: true, // 无障碍:读屏播报流式内容
      label: 'AI 正在回复',
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.86,
          ),
          child: Card(
            color: s.surfaceContainerHighest,
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            margin: const EdgeInsets.symmetric(vertical: Gap.xs),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                topLeft: r16,
                topRight: r16,
                bottomLeft: r4,
                bottomRight: r16,
              ),
            ),
            child: Padding(
              padding: Insets.bubble,
              child: SelectionArea(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: text.isEmpty ? '' : text),
                      if (!finished)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.only(left: Gap.xs),
                            child: BlinkingCursor(color: s.primary),
                          ),
                        ),
                    ],
                  ),
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: s.onSurface, height: 1.5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
