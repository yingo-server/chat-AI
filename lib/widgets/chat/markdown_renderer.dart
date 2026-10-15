import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

/// Markdown 渲染器 —— 纯控件树,无 WebView。
///
/// 支持 GitHub Flavored Markdown:标题、加粗/斜体/删除线、行内代码、围栏代码块
/// (语言标签 + 等宽 + 横向滚动)、引用、有序/无序/任务列表、分割线、表格、链接。
/// 未识别语法降级为纯文本,不抛异常。
class MarkdownText extends StatefulWidget {
  final String data;
  final bool selectable;
  final void Function(String url)? onTapLink;

  /// 正文文字样式(标题/列表/代码等在此基础上派生)
  final TextStyle? textStyle;

  const MarkdownText(
    this.data, {
    super.key,
    this.selectable = true,
    this.onTapLink,
    this.textStyle,
  });

  @override
  State<MarkdownText> createState() => _MarkdownTextState();
}

class _MarkdownTextState extends State<MarkdownText> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = widget.textStyle ?? theme.textTheme.bodyLarge!;
    final doc = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    );
    // markdown 包:顶层入口是 Document.parseLines / Document.parse
    final blocks = doc.parse(widget.data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final b in blocks)
          _Block(
            node: b,
            theme: theme,
            baseStyle: base,
            selectable: widget.selectable,
            onTapLink: widget.onTapLink,
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 块级
// ─────────────────────────────────────────────────────────────

class _Block extends StatelessWidget {
  final md.Node node;
  final ThemeData theme;
  final TextStyle baseStyle;
  final bool selectable;
  final void Function(String url)? onTapLink;

  const _Block({
    required this.node,
    required this.theme,
    required this.baseStyle,
    required this.selectable,
    this.onTapLink,
  });

  @override
  Widget build(BuildContext context) {
    final s = theme.colorScheme;

    // 只处理 Element;Text 节点直接作为段落
    if (node is! md.Element) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: _Inline(
          node,
          theme,
          base: baseStyle,
          selectable: selectable,
          onTapLink: onTapLink,
        ),
      );
    }

    final el = node as md.Element;
    final tag = el.tag;

    // ---- 标题 ----
    if (tag.startsWith('h') && tag.length == 2) {
      final level = int.tryParse(tag.substring(1)) ?? 6;
      final style = switch (level) {
        1 => theme.textTheme.headlineMedium,
        2 => theme.textTheme.headlineSmall,
        3 => theme.textTheme.titleLarge,
        4 => theme.textTheme.titleMedium,
        _ => theme.textTheme.titleSmall,
      };
      return Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: _Inline(
          el,
          theme,
          base: style ?? baseStyle,
          selectable: selectable,
          onTapLink: onTapLink,
        ),
      );
    }

    // ---- 围栏代码块 ----
    if (tag == 'pre') {
      final inner = el.children?.isNotEmpty == true ? el.children!.first : null;
      final code = inner is md.Element ? inner.textContent : '';
      final lang = el.attributes['class']?.replaceFirst('language-', '');
      return _CodeBlock(
        code: code,
        language: lang,
        theme: theme,
        baseStyle: baseStyle,
      );
    }

    // ---- 引用块 ----
    if (tag == 'blockquote') {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: s.primary, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in el.children ?? const <md.Node>[])
              _Block(
                node: c,
                theme: theme,
                baseStyle: baseStyle,
                selectable: selectable,
                onTapLink: onTapLink,
              ),
          ],
        ),
      );
    }

    // ---- 列表 ----
    if (tag == 'ul' || tag == 'ol') {
      final items =
          (el.children ?? const <md.Node>[]).whereType<md.Element>().toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++)
            _ListItem(
              item: items[i],
              index: i,
              ordered: tag == 'ol',
              theme: theme,
              baseStyle: baseStyle,
              selectable: selectable,
              onTapLink: onTapLink,
            ),
        ],
      );
    }

    // ---- 分割线 ----
    if (tag == 'hr') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Divider(color: s.outlineVariant),
      );
    }

    // ---- 表格 ----
    if (tag == 'table') {
      return _Table(
        element: el,
        theme: theme,
        baseStyle: baseStyle,
      );
    }

    // ---- 段落 / 其他容器:递归 ----
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: _Inline(
        el,
        theme,
        base: baseStyle,
        selectable: selectable,
        onTapLink: onTapLink,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 列表项
// ─────────────────────────────────────────────────────────────

class _ListItem extends StatelessWidget {
  final md.Element item;
  final int index;
  final bool ordered;
  final ThemeData theme;
  final TextStyle baseStyle;
  final bool selectable;
  final void Function(String url)? onTapLink;

  const _ListItem({
    required this.item,
    required this.index,
    required this.ordered,
    required this.theme,
    required this.baseStyle,
    required this.selectable,
    this.onTapLink,
  });

  @override
  Widget build(BuildContext context) {
    final s = theme.colorScheme;
    final isTask = item.attributes['type'] == 'checkbox';
    final checked = item.attributes['checked'] == 'true';
    final marker = ordered ? '${index + 1}.' : '•';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isTask)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 6),
              child: Icon(
                checked
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 16,
                color: checked ? s.primary : s.onSurfaceVariant,
              ),
            )
          else
            SizedBox(
              width: 18,
              child: Text(
                marker,
                textAlign: TextAlign.right,
                style: baseStyle,
              ),
            ),
          const SizedBox(width: 6),
          Expanded(
            child: _Inline(
              item,
              theme,
              base: baseStyle,
              selectable: selectable,
              onTapLink: onTapLink,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 代码块
// ─────────────────────────────────────────────────────────────

class _CodeBlock extends StatelessWidget {
  final String code;
  final String? language;
  final ThemeData theme;
  final TextStyle baseStyle;

  const _CodeBlock({
    required this.code,
    required this.theme,
    required this.baseStyle,
    this.language,
  });

  @override
  Widget build(BuildContext context) {
    final s = theme.colorScheme;
    final mono = baseStyle.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Roboto Mono'],
      fontSize: (baseStyle.fontSize ?? 14) - 1,
      height: 1.45,
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: s.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: s.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (language != null && language!.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              color: s.surfaceContainerHigh,
              child: Text(
                language!,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: s.onSurfaceVariant),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: SelectableText(
              code.replaceAll(RegExp(r'\n+$'), ''),
              style: mono,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 表格
// ─────────────────────────────────────────────────────────────

class _Table extends StatelessWidget {
  final md.Element element;
  final ThemeData theme;
  final TextStyle baseStyle;

  const _Table({
    required this.element,
    required this.theme,
    required this.baseStyle,
  });

  @override
  Widget build(BuildContext context) {
    final s = theme.colorScheme;
    final rows =
        (element.children ?? const <md.Node>[]).whereType<md.Element>().toList();

    String cellText(md.Element cell) => cell.textContent.trim();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: s.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < rows.length; r++)
            for (var c = 0; c < (rows[r].children ?? const []).length; c++)
              _TableCell(
                text: cellText((rows[r].children![c] as md.Element)),
                header: r == 0,
                isLast: r == rows.length - 1,
                theme: theme,
                baseStyle: baseStyle,
              ),
        ],
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  final String text;
  final bool header;
  final bool isLast;
  final ThemeData theme;
  final TextStyle baseStyle;

  const _TableCell({
    required this.text,
    required this.header,
    required this.isLast,
    required this.theme,
    required this.baseStyle,
  });

  @override
  Widget build(BuildContext context) {
    final s = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: header ? s.surfaceContainerHigh : null,
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: s.outlineVariant)),
      ),
      child: SelectableText(
        text,
        style: header
            ? baseStyle.copyWith(fontWeight: FontWeight.w600)
            : baseStyle,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 行内
// ─────────────────────────────────────────────────────────────

class _Inline extends StatefulWidget {
  final md.Node node;
  final ThemeData theme;
  final TextStyle? base;
  final bool selectable;
  final void Function(String url)? onTapLink;

  const _Inline(
    this.node,
    this.theme, {
    this.base,
    required this.selectable,
    this.onTapLink,
  });

  @override
  State<_Inline> createState() => _InlineState();
}

class _InlineState extends State<_Inline> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer? _recognizerFor(String url) {
    final onTap = widget.onTapLink;
    if (onTap == null) return null;
    final r = TapGestureRecognizer()..onTap = () => onTap(url);
    _recognizers.add(r);
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.base ?? widget.theme.textTheme.bodyLarge!;
    final span = _spansFor(widget.node, base);
    return widget.selectable
        ? SelectableText.rich(span)
        : Text.rich(span);
  }

  TextSpan _spansFor(md.Node node, TextStyle style) {
    if (node is md.Text) {
      return TextSpan(text: node.text, style: style);
    }
    if (node is md.Element) {
      final children = (node.children ?? const <md.Node>[])
          .map((c) => _spansFor(c, style))
          .toList();
      switch (node.tag) {
        case 'strong':
          return TextSpan(
            children: children,
            style: style.copyWith(fontWeight: FontWeight.w700),
          );
        case 'em':
          return TextSpan(
            children: children,
            style: style.copyWith(fontStyle: FontStyle.italic),
          );
        case 'del':
          return TextSpan(
            children: children,
            style: style.copyWith(decoration: TextDecoration.lineThrough),
          );
        case 'code':
          return TextSpan(
            children: children,
            style: style.copyWith(
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Menlo', 'Consolas'],
              backgroundColor: widget.theme.colorScheme.surfaceContainerHighest,
            ),
          );
        case 'a':
          final url = node.attributes['href'] ?? '';
          return TextSpan(
            children: children,
            style: style.copyWith(
              color: widget.theme.colorScheme.primary,
              decoration: TextDecoration.underline,
              decorationColor: widget.theme.colorScheme.primary,
            ),
            recognizer: _recognizerFor(url),
          );
        case 'br':
          return const TextSpan(text: '\n');
        default:
          return TextSpan(children: children, style: style);
      }
    }
    return TextSpan(text: node.textContent, style: style);
  }
}
