import 'package:flutter/material.dart';

import 'error_code.dart';

/// 抛 AppError(Ec.ut0x)
void showSnack(BuildContext ctx, String msg, {bool error = false}) {
  try {
    final messenger = ScaffoldMessenger.maybeOf(ctx);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error
            ? Theme.of(ctx).colorScheme.errorContainer
            : null,
      ),
    );
  } catch (e, st) {
    throw AppError(Ec.ut00.code, Ec.ut00.message, cause: e, stack: st);
  }
}

Future<bool> confirmDialog(
  BuildContext ctx, {
  required String title,
  required String message,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool destructive = false,
}) async {
  try {
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
                    backgroundColor: Colors.red.shade400,
                    foregroundColor: Colors.white,
                  )
                : null,
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  } catch (e, st) {
    throw AppError(Ec.ut01.code, Ec.ut01.message, cause: e, stack: st);
  }
}

Future<String?> inputDialog(
  BuildContext ctx, {
  required String title,
  String? hint,
  String initialValue = '',
}) {
  try {
    final ctrl = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, ctrl.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  } catch (e, st) {
    throw AppError(Ec.ut02.code, Ec.ut02.message, cause: e, stack: st);
  }
}