import 'package:flutter/material.dart';

import '../models/app_config.dart';
import '../theme/spacing.dart';

/// 设置页 — 用户可见的全部"配置":
/// 字号 / 颜色 / 缓冲区大小 / 输出速度(后两项互斥)。
/// 交互规范:M3 —— 可点击目标 ≥48dp、选中态有明确指示 + 语义标注、
/// 数值用 labelLarge 呈现,分区用 surface container 卡片。
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
                Text('${_prefs.fontSize} sp', style: theme.textTheme.labelLarge),
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),
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
          const SizedBox(height: Gap.lg),
          _Section(
            icon: Icons.layers_outlined,
            title: '缓冲区大小',
            subtitle: '缓冲模式:攒够这么多字再一次性显示',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Slider(
                  min: 0,
                  max: 200,
                  divisions: 20,
                  label: _prefs.bufferSize == 0
                      ? '关闭'
                      : '${_prefs.bufferSize} 字',
                  value: _prefs.bufferSize.toDouble().clamp(0, 200),
                  onChanged: (v) {
                    final n = v.round();
                    _update(n == 0
                        ? _prefs.copyWith(bufferSize: 0)
                        // 互斥:动缓冲 → 速度归零
                        : _prefs.copyWith(bufferSize: n, streamSpeed: 0));
                  },
                ),
                Text(
                  _prefs.bufferSize == 0 ? '关闭' : '${_prefs.bufferSize} 字',
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),
          _Section(
            icon: Icons.speed_outlined,
            title: '输出速度',
            subtitle: '限速模式:每秒最多显示这么多字',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Slider(
                  min: 0,
                  max: 120,
                  divisions: 30,
                  label: _prefs.streamSpeed == 0
                      ? '关闭'
                      : '${_prefs.streamSpeed} 字/秒',
                  value: _prefs.streamSpeed.toDouble().clamp(0, 120),
                  onChanged: (v) {
                    final n = v.round();
                    _update(n == 0
                        ? _prefs.copyWith(streamSpeed: 0)
                        // 互斥:动速度 → 缓冲归零
                        : _prefs.copyWith(streamSpeed: n, bufferSize: 0));
                  },
                ),
                Text(
                  _prefs.streamSpeed == 0 ? '关闭' : '${_prefs.streamSpeed} 字/秒',
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.xl),
          Center(
            child: Text(
              '缓冲区与输出速度互斥,同时只有一个生效',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// 颜色选项 — 48dp 可点击区域 + 选中勾选 + 语义标注
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
          width: 48,
          height: 48,
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
                      // 依据背景亮度选前景色,保证对比度
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
            const SizedBox(height: Gap.lg),
            child,
          ],
        ),
      ),
    );
  }
}
