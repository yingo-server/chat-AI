import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/spacing.dart';

/// 设置页 —— 用户可见的全部"配置"仅两项:
///   1. 字号
///   2. 主题色
///   3. 输出速度(5–100 字/秒)
///
/// 流式输出缓冲上限固定为 100 字,由应用内部控制以抵抗网络抖动,
/// 不提供用户调节入口。
class SettingsScreen extends StatefulWidget {
  final ConfigController controller;
  const SettingsScreen({super.key, required this.controller});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late UserPrefs _prefs;

  @override
  void initState() {
    super.initState();
    _prefs = widget.controller.config.userPrefs;
  }

  void _update(UserPrefs next) {
    setState(() => _prefs = next);
    widget.controller.updateUserPrefs(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: Insets.page,
        children: [
          _Section(
            icon: Icons.text_fields,
            title: '字号',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('A', style: theme.textTheme.bodySmall),
                    Expanded(
                      child: Slider(
                        min: 12,
                        max: 24,
                        divisions: 12,
                        label: '${_prefs.fontSize}',
                        value: _prefs.fontSize.toDouble().clamp(12, 24),
                        onChanged: (v) =>
                            _update(_prefs.copyWith(fontSize: v.round())),
                      ),
                    ),
                    Text('A', style: theme.textTheme.headlineSmall),
                  ],
                ),
                Text('${_prefs.fontSize} sp',
                    style: theme.textTheme.labelLarge),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),
          _Section(
            icon: Icons.palette_outlined,
            title: '颜色',
            child: Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: [
                for (var i = 0; i < UserPrefs.seedColors.length; i++)
                  _ColorSwatch(
                    color: Color(UserPrefs.seedColors[i]),
                    selected: _prefs.seedColorIndex == i,
                    onTap: () => _update(_prefs.copyWith(seedColorIndex: i)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),
          _Section(
            icon: Icons.speed_outlined,
            title: '输出速度',
            subtitle: '每秒最多显示的字数,用于平滑流式输出',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Slider(
                  min: 5,
                  max: 100,
                  divisions: 19,
                  label: '${_prefs.streamSpeed} 字/秒',
                  value: _prefs.streamSpeed.clamp(5, 100).toDouble(),
                  onChanged: (v) =>
                      _update(_prefs.copyWith(streamSpeed: v.round())),
                ),
                Text(
                  '${_prefs.streamSpeed} 字/秒',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: Gap.sm),
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 14, color: s.onSurfaceVariant),
                    const SizedBox(width: Gap.xs),
                    Expanded(
                      child: Text(
                        '缓冲上限固定 100 字,用于吸收网络抖动,不可调整',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: s.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 颜色选项 —— 48dp 可点击区域 + 选中勾选 + 语义标注
class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '主题颜色',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: Gap.minTouchTarget,
          height: Gap.minTouchTarget,
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? s.onSurface : s.outlineVariant,
                  width: selected ? 3 : 1,
                ),
              ),
              child: selected
                  ? Icon(
                      Icons.check,
                      size: 20,
                      color: ThemeData.estimateBrightnessForColor(color) ==
                              Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  const _Section({
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    return Card(
      color: s.surfaceContainerLow,
      child: Padding(
        padding: Insets.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: s.onSurfaceVariant),
                const SizedBox(width: Gap.md),
                Text(title, style: theme.textTheme.titleMedium),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: Gap.xs),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: s.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: Gap.md),
            child,
          ],
        ),
      ),
    );
  }
}
