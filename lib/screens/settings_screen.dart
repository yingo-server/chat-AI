import 'package:flutter/material.dart';

import '../models/app_config.dart';
import '../services/config_store.dart';

/// 设置页 — 编辑 AI / 上下文 / 周期提示词 / 系统提示词模板
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _store = ConfigStore();
  late ConfigController _controller;
  late AppConfig _cfg;

  @override
  void initState() {
    super.initState();
    _controller = ConfigController();
    _controller.addListener(_onChanged);
    _bootstrap();
  }

  void _onChanged() {
    setState(() => _cfg = _controller.config);
    _store.save(_cfg);
  }

  Future<void> _bootstrap() async {
    final cfg = await _store.load();
    setState(() {
      _cfg = cfg;
      _controller.replace(cfg);
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _section('AI 接口', [
            _aiTile(),
          ]),
          _section('上下文压缩(后台自动运行)', [_contextTile()]),
          _section('系统提示词模板', _promptTiles()),
          _section('周期提示词', _recurringTiles()),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '修改保存到应用文档目录的 config.json',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    )),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _aiTile() {
    final ai = _cfg.ai;
    return Column(
      children: [
        TextFormField(
          initialValue: ai.endpoint,
          decoration: const InputDecoration(labelText: 'Endpoint'),
          onChanged: (v) =>
              _controller.updateAi(ai.copyWith(endpoint: v.trim())),
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: ai.apiKey,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'API Key'),
          onChanged: (v) => _controller.updateAi(ai.copyWith(apiKey: v.trim())),
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: ai.model,
          decoration: const InputDecoration(labelText: 'Model'),
          onChanged: (v) => _controller.updateAi(ai.copyWith(model: v.trim())),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextFormField(
              initialValue: ai.temperature.toString(),
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Temperature'),
              onChanged: (v) {
                final t = double.tryParse(v) ?? ai.temperature;
                _controller.updateAi(ai.copyWith(temperature: t));
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              initialValue: ai.maxTokens.toString(),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Max tokens'),
              onChanged: (v) {
                final n = int.tryParse(v) ?? ai.maxTokens;
                _controller.updateAi(ai.copyWith(maxTokens: n));
              },
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Slider(
              value: ai.streamCharsPerSecond.clamp(4, 120),
              min: 4,
              max: 120,
              divisions: 23,
              label: '${ai.streamCharsPerSecond.toStringAsFixed(0)} 字/秒',
              onChanged: (v) => _controller
                  .updateAi(ai.copyWith(streamCharsPerSecond: v)),
            ),
          ),
          const SizedBox(width: 8),
          Text('${ai.streamCharsPerSecond.toStringAsFixed(0)} 字/秒'),
        ]),
        Text('流式输出缓冲节流速度:数值越大 AI 文字出现得越快',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _contextTile() {
    final ctx = _cfg.context;
    Widget numField(String label, int val, void Function(int) onChange) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextFormField(
          initialValue: val.toString(),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label),
          onChanged: (v) {
            final n = int.tryParse(v);
            if (n != null) onChange(n);
          },
        ),
      );
    }

    return Column(
      children: [
        numField('最大消息数(超过再次压缩)', ctx.maxContextMessages,
            (v) => _controller.updateContext(ctx.copyWith(maxContextMessages: v))),
        numField('触发压缩的消息数', ctx.compressTriggerMessages,
            (v) => _controller.updateContext(ctx.copyWith(compressTriggerMessages: v))),
        numField('压缩后保留的最近消息数', ctx.keepRecentMessages,
            (v) => _controller.updateContext(ctx.copyWith(keepRecentMessages: v))),
        const SizedBox(height: 4),
        TextFormField(
          initialValue: ctx.compressModel,
          decoration: const InputDecoration(
              labelText: '压缩使用的模型(留空则用主模型)'),
          onChanged: (v) =>
              _controller.updateContext(ctx.copyWith(compressModel: v.trim())),
        ),
        const SizedBox(height: 4),
        TextFormField(
          initialValue: ctx.compressPrompt,
          maxLines: 3,
          decoration:
              const InputDecoration(labelText: '压缩提示词'),
          onChanged: (v) =>
              _controller.updateContext(ctx.copyWith(compressPrompt: v)),
        ),
      ],
    );
  }

  List<Widget> _promptTiles() {
    return [
      for (final p in _cfg.systemPrompts)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(p.name),
          subtitle: Text(p.content, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final next = await _editTextDialog(
                  title: '编辑系统提示词', value: p.content);
              if (next == null) return;
              final list = [..._cfg.systemPrompts];
              list[list.indexWhere((e) => e.id == p.id)] =
                  SystemPrompt(id: p.id, name: p.name, content: next);
              _controller.updatePrompts(list);
            },
          ),
        ),
    ];
  }

  List<Widget> _recurringTiles() {
    return [
      for (final p in _cfg.recurringPrompts)
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                      child: Text(p.id,
                          style: const TextStyle(fontFamily: 'monospace'))),
                  Switch(
                    value: p.enabled,
                    onChanged: (v) {
                      final list = [..._cfg.recurringPrompts];
                      list[list.indexWhere((e) => e.id == p.id)] =
                          p.copyWith(enabled: v);
                      _controller.updateRecurring(list);
                    },
                  ),
                ]),
                Row(children: [
                  const Text('每 '),
                  SizedBox(
                    width: 60,
                    child: TextFormField(
                      initialValue: p.intervalTurns.toString(),
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        final n = int.tryParse(v);
                        if (n == null) return;
                        final list = [..._cfg.recurringPrompts];
                        list[list.indexWhere((e) => e.id == p.id)] =
                            p.copyWith(intervalTurns: n);
                        _controller.updateRecurring(list);
                      },
                    ),
                  ),
                  const Text(' 轮注入一次'),
                  const Spacer(),
                  DropdownButton<PromptRotation>(
                    value: p.rotation,
                    onChanged: (v) {
                      if (v == null) return;
                      final list = [..._cfg.recurringPrompts];
                      list[list.indexWhere((e) => e.id == p.id)] =
                          p.copyWith(rotation: v);
                      _controller.updateRecurring(list);
                    },
                    items: const [
                      DropdownMenuItem(
                          value: PromptRotation.roundRobin,
                          child: Text('轮询')),
                      DropdownMenuItem(
                          value: PromptRotation.all,
                          child: Text('全部')),
                      DropdownMenuItem(
                          value: PromptRotation.random,
                          child: Text('随机')),
                    ],
                  ),
                ]),
                const SizedBox(height: 4),
                TextFormField(
                  initialValue: p.content,
                  maxLines: 3,
                  onChanged: (v) {
                    final list = [..._cfg.recurringPrompts];
                    list[list.indexWhere((e) => e.id == p.id)] =
                        p.copyWith(content: v);
                    _controller.updateRecurring(list);
                  },
                ),
              ],
            ),
          ),
        ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('新增周期提示词'),
          onPressed: () {
            final id = 'rp_${DateTime.now().millisecondsSinceEpoch}';
            final list = [
              ..._cfg.recurringPrompts,
              RecurringPrompt(
                  id: id,
                  content: '请补充…',
                  intervalTurns: 1,
                  enabled: true,
                  rotation: PromptRotation.roundRobin),
            ];
            _controller.updateRecurring(list);
          },
        ),
      ),
    ];
  }

  Future<String?> _editTextDialog(
      {required String title, required String value}) async {
    final ctrl = TextEditingController(text: value);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          maxLines: 6,
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

extension on AiConfig {
  AiConfig copyWith({
    String? endpoint,
    String? apiKey,
    String? model,
    double? temperature,
    int? maxTokens,
    int? requestTimeoutSeconds,
  }) =>
      AiConfig(
        endpoint: endpoint ?? this.endpoint,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        temperature: temperature ?? this.temperature,
        maxTokens: maxTokens ?? this.maxTokens,
        requestTimeoutSeconds:
            requestTimeoutSeconds ?? this.requestTimeoutSeconds,
      );
}

extension on ContextConfig {
  ContextConfig copyWith({
    int? maxContextMessages,
    int? compressTriggerMessages,
    int? keepRecentMessages,
    String? compressPrompt,
    String? compressModel,
  }) =>
      ContextConfig(
        maxContextMessages: maxContextMessages ?? this.maxContextMessages,
        compressTriggerMessages:
            compressTriggerMessages ?? this.compressTriggerMessages,
        keepRecentMessages: keepRecentMessages ?? this.keepRecentMessages,
        compressPrompt: compressPrompt ?? this.compressPrompt,
        compressModel: compressModel ?? this.compressModel,
      );
}