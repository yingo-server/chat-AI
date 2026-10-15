import 'package:flutter/material.dart';

import '../../theme/spacing.dart';
import '../animation/message_animations.dart';
import 'markdown_renderer.dart';

/// 流式输出中的助手气泡。
/// 与 MessageBubble 共用形状与配色,避免流结束时跳变。
/// 输出期间以纯文本渲染(每帧成本最低);结束后切换为 Markdown 渲染。
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
              padding: Insets.bubble,
              child: SelectionArea(
                child: finished
                    // 流式结束:完整 Markdown 渲染(代码块/列表/表格等)
                    ? MarkdownText(
                        text,
                        textStyle: theme.textTheme.bodyLarge
                            ?.copyWith(color: s.onSurface, height: 1.5),
                      )
                    // 输出中:纯文本 + 行内光标(避免每帧重建整棵语法树)
                    : Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: text,
                              style: theme.textTheme.bodyLarge
                                  ?.copyWith(color: s.onSurface, height: 1.5),
                            ),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: const EdgeInsets.only(left: Gap.xs),
                                child: BlinkingCursor(color: s.primary),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
