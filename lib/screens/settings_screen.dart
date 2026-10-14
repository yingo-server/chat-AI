import 'package:flutter/material.dart';

import '../models/app_config.dart';
import '../utils/error_code.dart';

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
    try {
      _prefs = widget.controller.config.userPrefs;
    } catch (e, st) {
      throw AppError(Ec.sc15.code, Ec.sc15.message, cause: e, stack: st);
    }
  }

  void _update(UserPrefs next) {
    try {
      setState(() => _prefs = next);
      widget.controller.updateUserPrefs(next);
    } catch (e, st) {
      throw AppError(Ec.sc09.code, Ec.sc09.message, cause: e, stack: st);
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      final theme = Theme.of(context);
      return Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section(theme, Icons.text_fields, '字号', Column(
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
            )),
            const SizedBox(height: 12),
            _section(theme, Icons.palette, '颜色', Wrap(
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
            )),
            const SizedBox(height: 12),
            _section(theme, Icons.layers_outlined, '缓冲区大小',
                '缓冲模式:攒满这么多字才一次性输出',
                Column(children: [
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
                      _update(_prefs.copyWith(
                          bufferSize: n, streamSpeed: 0));
                    },
                  ),
                  Text(_prefs.bufferSize == 0 ? '关闭' : '${_prefs.bufferSize} 字'),
                ])),
            const SizedBox(height: 12),
            _section(theme, Icons.speed, '输出速度',
                '限速模式:每秒最多这么多字',
                Column(children: [
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
                      _update(_prefs.copyWith(
                          streamSpeed: n, bufferSize: 0));
                    },
                  ),
                  Text(_prefs.streamSpeed == 0
                      ? '关闭'
                      : '${_prefs.streamSpeed} 字/秒'),
                ])),
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
    } on AppError {
      rethrow;
    } catch (e, st) {
      throw AppError(Ec.sc00.code, Ec.sc00.message, cause: e, stack: st);
    }
  }

  Widget _section(ThemeData theme, IconData icon, String title, Widget child,
      [String? subtitle]) {
    try {
      return Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: theme.colorScheme.primary)),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      );
    } catch (e, st) {
      throw AppError(Ec.wd00.code, Ec.wd00.message, cause: e, stack: st);
    }
  }
}