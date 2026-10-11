import 'package:flutter/material.dart';

import '../../models/app_config.dart';

/// 周期提示词状态卡片 — 仅在 debug / 开发者面板显示。
/// 列出当前已启用提示词 + 上次注入轮数 + 当前轮询游标位置。
class RecurringPromptsStatusCard extends StatelessWidget {
  final List<RecurringPrompt> prompts;
  final int cursor;
  final int turnsCompleted;

  const RecurringPromptsStatusCard({
    super.key,
    required this.prompts,
    required this.cursor,
    required this.turnsCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (prompts.isEmpty) {
      return Card(
        color: theme.colorScheme.surfaceContainer,
        child: const ListTile(
          leading: Icon(Icons.rule),
          title: Text('未配置周期提示词'),
          subtitle: Text('在设置 → 周期提示词中新增'),
        ),
      );
    }
    return Card(
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.rule),
                const SizedBox(width: 8),
                Text('周期提示词调度状态',
                    style: theme.textTheme.titleSmall),
                const Spacer(),
                Chip(
                  label: Text('轮询游标 ${cursor % (prompts.isEmpty ? 1 : prompts.length)}'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('已完成轮数: $turnsCompleted',
                style: theme.textTheme.bodySmall),
            const Divider(height: 16),
            for (final p in prompts)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  p.enabled ? Icons.toggle_on : Icons.toggle_off,
                  color: p.enabled
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                title: Text(p.id,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontFamily: 'monospace')),
                subtitle: Text(
                  '间隔 ${p.intervalTurns} 轮 · 轮询 ${_rotationName(p.rotation)} · ${p.enabled ? "启用" : "停用"}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _rotationName(PromptRotation r) {
    switch (r) {
      case PromptRotation.roundRobin: return '轮询';
      case PromptRotation.all: return '全部';
      case PromptRotation.random: return '随机';
    }
  }
}