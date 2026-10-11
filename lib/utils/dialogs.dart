import 'package:flutter/material.dart';

/// 简单的 Snackbar 封装
void showSnack(BuildContext ctx, String msg, {bool error = false}) {
  ScaffoldMessenger.of(ctx).showSnackBar(
    SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error
          ? Theme.of(ctx).colorScheme.errorContainer
          : null,
    ),
  );
}

/// 自定义 confirm 对话框(避免依赖原生 confirm 在 Web 不可用)
Future<bool> confirmDialog(
  BuildContext ctx, {
  required String title,
  required String message,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: ctx,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel)),
        FilledButton(
          style: destructive
              ? ButtonTheme
                  .fromButtonThemeData(
                    ButtonThemeData(),
                  )
                  .copyWith()
                  .copyWith(
                    backgroundColor:
                        WidgetStateProperty.all(Colors.red.shade400),
                  )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
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
  return showDialog<String>(
    context: ctx,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}