import 'package:flutter/material.dart';

import '../models/app_config.dart';

/// 设置页 — 用户眼前唯一的"配置"
/// 只有 4 个控件:字号 / 颜色 / 缓冲区大小 / 输出速度
/// 后两项**互斥** — 拖一个,另一个归零。
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          _SectionCard(
            icon: Icons.text_fields,
            title: '字号',
            child: Column(
              children: [
                Row(
                  children: [
                    const Text('Aa', style: TextStyle(fontSize: 12)),
                    Expanded(
                      child: Slider(
                        min: 12,
                        max: 24,
                        divisions: 12,
                        label: '${_prefs.fontSize}',
                        value: _prefs.fontSize.toDouble(),
                        onChanged: (v) =>
                            _update(_prefs.copyWith(fontSize: v.toInt())),
                      ),
                    ),
                    const Text('Aa', style: TextStyle(fontSize: 24)),
                  ],
                ),
                Text('${_prefs.fontSize} sp', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.palette,
            title: '颜色',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < UserPrefs.seedColors.length; i++)
                  GestureDetector(
                    onTap: () =>
                        _update(_prefs.copyWith(seedColorIndex: i)),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Color(UserPrefs.seedColors[i]),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _prefs.seedColorIndex == i
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          width: _prefs.seedColorIndex == i ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.layers_outlined,
            title: '缓冲区大小',
            subtitle: '缓冲模式:攒满这么多字才一次性输出',
            child: Column(
              children: [
                Slider(
                  min: 0,
                  max: 200,
                  divisions: 20,
                  label:
                      '${_prefs.bufferSize} 字${_prefs.bufferSize == 0 ? "(禁用)" : ""}',
                  value: _prefs.bufferSize.toDouble(),
                  onChanged: (v) {
                    final n = v.toInt();
                    if (n == 0) {
                      _update(_prefs.copyWith(bufferSize: 0));
                      return;
                    }
                    // 互斥:动 buffer,速度归 0
                    _update(_prefs.copyWith(
                      bufferSize: n,
                      streamSpeed: 0,
                    ));
                  },
                ),
                Text(_prefs.bufferSize == 0
                    ? '关闭'
                    : '${_prefs.bufferSize} 字'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.speed,
            title: '输出速度',
            subtitle: '限速模式:每秒最多这么多字',
            child: Column(
              children: [
                Slider(
                  min: 0,
                  max: 120,
                  divisions: 30,
                  label:
                      '${_prefs.streamSpeed} 字/秒${_prefs.streamSpeed == 0 ? "(禁用)" : ""}',
                  value: _prefs.streamSpeed.toDouble(),
                  onChanged: (v) {
                    final n = v.toInt();
                    if (n == 0) {
                      _update(_prefs.copyWith(streamSpeed: 0));
                      return;
                    }
                    // 互斥:动速度,buffer 归 0
                    _update(_prefs.copyWith(
                      streamSpeed: n,
                      bufferSize: 0,
                    ));
                  },
                ),
                Text(_prefs.streamSpeed == 0
                    ? '关闭'
                    : '${_prefs.streamSpeed} 字/秒'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '缓冲区 与 输出速度 互斥 — 同时只有一个生效',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon,
                    color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(title,
                    style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        )),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}