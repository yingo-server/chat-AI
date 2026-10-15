import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

/// Markdown 渲染器 —— 纯控件树,无 WebView,无外部服务。
///
/// 支持 GitHub Flavored Markdown:标题、加粗/斜体/删除线、行内代码、围栏代码块
/// (含语言标签与横向滚动)、引用、有序/无序/任务列表、分割线、表格、链接。
/// 对无法识别的语法降级为纯文本,不抛异常。
class MarkdownText extends StatefulWidget {
  final String data;

  /// 是否可选中复制(默认开启)
  final bool selectable;

  /// 链接点击;为空则忽略点击
  final void Function(String url)? onTapLink;

  /// 正文文字样式(标题/列表等在此基础上派生)
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
    final document = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    );
    final blocks = md.parse(widget.data, document);

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

/// 内部实现体(由上面的 State 驱动)
class _MarkdownBody extends StatelessWidget {
  final String data;
  final ThemeData theme;
  final TextStyle baseStyle;
  final bool selectable;
  final void Function(String url)? onTapLink;

  const _MarkdownBody({
    required this.data,
    required this.theme,
    required this.baseStyle,
    required this.selectable,
    this.onTapLink,
  });

  @override
  Widget build(BuildContext context) {
    final document = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    );
    final blocks = md.parse(data, document);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final b in blocks)
          _Block(
            node: b,
            theme: theme,
            baseStyle: baseStyle,
            selectable: selectable,
            onTapLink: onTapLink,
          ),
      ],
    );
  }
}

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

    // ---- 标题 ----
    if (node is md.Element && node.tag.startsWith('h')) {
      final level = int.tryParse(node.tag.substring(1)) ?? 6;
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
          node,
          theme,
          base: style,
          selectable: selectable,
          onTapLink: onTapLink,
        ),
      );
    }

    // ---- 围栏代码块 ----
    if (node is md.Element && node.tag == 'pre') {
      final code = node.children?.isNotEmpty == true
          ? (node.children!.first is md.Element
              ? (node.children!.first as md.Element).textContent
              : node.children!.first.textContent)
          : '';
      final lang = node.attributes['class']?.replaceFirst('language-', '');
      return _CodeBlock(
          code: code, language: lang, theme: theme, baseStyle: baseStyle);
    }

    // ---- 引用块 ----
    if (node is md.Element && node.tag == 'blockquote') {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: s.primary, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in node.children ?? const <md.Node>[])
              _Block(
                node: c,
                theme: theme,
                selectable: selectable,
                onTapLink: onTapLink,
              ),
          ],
        ),
      );
    }

    // ---- 列表(有序/无序/任务)----
    if (node is md.Element && node.tag == 'ul') {
      return _ListBlock(node: node, ordered: false, parent: this);
    }
    if (node is md.Element && node.tag == 'ol') {
      return _ListBlock(node: node, ordered: true, parent: this);
    }

    // ---- 分割线 ----
    if (node is md.Element && node.tag == 'hr') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Divider(color: s.outlineVariant),
      );
    }

    // ---- 段落 ----
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: _Inline(
        node,
        theme,
        base: theme.textTheme.bodyLarge,
        selectable: selectable,
        onTapLink: onTapLink,
      ),
    );
  }
}

/// 列表块:为每个列表项生成 bullet / 序号
class _ListBlock extends StatelessWidget {
  final md.Node node;
  final bool ordered;
  final _Block parent;

  const _ListBlock({
    required this.node,
    required this.ordered,
    required this.parent,
  });

  @override
  Widget build(BuildContext context) {
    final items = node.children?.whereType<md.Element>().toList() ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++)
          _ListItem(
            item: items[i],
            index: i,
            ordered: ordered,
            theme: parent.theme,
            baseStyle: parent.baseStyle,
            selectable: parent.selectable,
            onTapLink: parent.onTapLink,
          ),
      ],
    );
  }
}

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
            Container(
              width: 22,
              alignment: Alignment.topRight,
              padding: const EdgeInsets.only(top: 4, right: 6),
              child: Text(marker, style: baseStyle),
            ),
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

/// 代码块:等宽字体 + 横向滚动 + 语言标签
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
            padding: const EdgeInsets.all(12),
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

/// 行内内容:把 md.Node 转成 TextSpan(支持加粗/斜体/删除线/行内代码/链接)
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
    final span = _spansFor(widget.node, widget.base ?? widget.theme.textTheme.bodyLarge!);
    return widget.selectable
        ? SelectableText.rich(span)
        : Text.rich(span);
  }

  TextSpan _spansFor(md.Node node, TextStyle style) {
    if (node is md.Text) {
      return TextSpan(text: node.text, style: style);
    }
    if (node is md.Element) {
      switch (node.tag) {
        case 'strong':
          return TextSpan(
            children: _children(node),
            style: style.copyWith(fontWeight: FontWeight.w700),
          );
        case 'em':
          return TextSpan(
            children: _children(node),
            style: style.copyWith(fontStyle: FontStyle.italic),
          );
        case 'del':
          return TextSpan(
            children: _children(node),
            style: style.copyWith(decoration: TextDecoration.lineThrough),
          );
        case 'code':
          final bg = widget.theme.colorScheme.surfaceContainerHighest;
          return TextSpan(
            text: node.textContent,
            style: style.copyWith(
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Menlo', 'Consolas'],
              backgroundColor: bg,
            ),
          );
        case 'a':
          final url = node.attributes['href'] ?? '';
          final link = (widget.base ?? widget.theme.textTheme.bodyLarge!).copyWith(
            color: widget.theme.colorScheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: widget.theme.colorScheme.primary,
          );
          return TextSpan(
            text: node.textContent.isEmpty ? url : node.textContent,
            style: link,
            recognizer: _recognizerFor(url),
          );
        case 'br':
          return const TextSpan(text: '\n');
        default:
          // 段落、列表项容器等:递归子节点
          return TextSpan(children: _children(node), style: style);
      }
    }
    return TextSpan(text: node.textContent, style: style);
  }

  List<InlineSpan> _children(md.Node node) {
    return (node.children ?? const <md.Node>[])
        .map((c) => _spansFor(c, widget.base ?? widget.theme.textTheme.bodyLarge!))
        .toList();
  }
}
