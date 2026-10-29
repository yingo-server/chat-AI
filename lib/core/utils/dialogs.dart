import 'package:flutter/material.dart';

/// 对话框 / 提示条 — 统一走 M3 语义色与组件
/// (Snackbar / Dialog 的视觉规范已在 AppTheme 里集中定义)

void showSnack(BuildContext ctx, String msg, {bool error = false}) {
  final s = Theme.of(ctx).colorScheme;
  ScaffoldMessenger.maybeOf(ctx)
    ?..removeCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: error ? TextStyle(color: s.onErrorContainer) : null,
        ),
        backgroundColor: error ? s.errorContainer : null,
      ),
    );
}

Future<bool> confirmDialog(
  BuildContext ctx, {
  required String title,
  required String message,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool destructive = false,
}) async {
  final s = Theme.of(ctx).colorScheme;
  final result = await showDialog<bool>(
    context: ctx,
    builder: (dialogCtx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: s.error,
                  foregroundColor: s.onError,
                )
              : null,
          onPressed: () => Navigator.pop(dialogCtx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<String?> inputDialog(
  BuildContext ctx, {
  required String title,
  String? hint,
  String initialValue = '',
}) {
  final ctrl = TextEditingController(text: initialValue);
  void submit(BuildContext c) => Navigator.pop(c, ctrl.text.trim());
  return showDialog<String>(
    context: ctx,
    builder: (dialogCtx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => submit(dialogCtx),
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => submit(dialogCtx),
          child: const Text('确定'),
        ),
      ],
    ),
  ).whenComplete(ctrl.dispose);
}
