import 'package:flutter/material.dart';

import '../../theme/spacing.dart';
import 'streaming_text.dart';
import 'typing_dots.dart';

/// 流式输出中的助手气泡。
/// 与 MessageBubble 共用形状与配色,避免流结束时跳变。
/// 文本逐字淡入(见 StreamingText),结束后由聊天页替换为 Markdown 气泡。
class StreamingBubble extends StatelessWidget {
  final String text;
  const StreamingBubble({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = theme.colorScheme;

    if (text.isEmpty) return const SizedBox.shrink();

    const r16 = Radius.circular(16);
    const r4 = Radius.circular(4);
    final style = theme.textTheme.bodyLarge
        ?.copyWith(color: s.onSurface, height: 1.5);

    return Semantics(
      liveRegion: true,
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
              padding:
                  const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.sm),
              child: StreamingText(
                text,
                style: style,
                cursorColor: s.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// 首 token 到达之前的占位气泡:与流式气泡同形状,内容为三点动画。
class ThinkingBubble extends StatelessWidget {
  const ThinkingBubble({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    const r16 = Radius.circular(16);
    const r4 = Radius.circular(4);
    return Semantics(
      liveRegion: true,
      label: 'AI 正在思考',
      child: Align(
        alignment: Alignment.centerLeft,
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
            padding: const EdgeInsets.fromLTRB(Gap.lg, 14, Gap.lg, 14),
            child: TypingDots(color: s.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
