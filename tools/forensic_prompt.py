#!/usr/bin/env python3
"""取证:复刻 App 的完整请求链,输出最终 messages 序列。
逐层对照 lib/services/chat_service.dart 的 buildPrompt / sendStream。"""
import json

cfg = json.load(open('assets/config.example.json'))
SYS = cfg['systemPrompts'][0]['content']
WARM_P = '(session init — acknowledge with the single word: READY)'
WARM_R = 'READY'

def dump(title, msgs):
    print(f"--- {title} ---")
    for i, m in enumerate(msgs):
        c = m['content']
        print(f"  [{i}] {m['role']:9s} | {len(c):4d} ch | {c[:44]!r}{'...' if len(c) > 44 else ''}")
    n_sys = sum(1 for m in msgs if m['role'] == 'system')
    print(f"  => system x{n_sys}, total {len(msgs)} msgs\n")

# ============ 场景 A:新对话首轮(history 空) ============
# buildPrompt(visible=[], injectHidden=true)
a = [
    {'role': 'system', 'content': SYS},           # 顶部 system
    {'role': 'system', 'content': SYS},           # 隐藏注入(每轮)
    {'role': 'user', 'content': WARM_P},          # 预热段(buildPrompt 附加)
    {'role': 'assistant', 'content': WARM_R},
]
# sendStream: prompt.add(ApiMessage('user', userText))
# 但 sendStream 里还有一处: "三明治"注入在 user 之前再加一次 system?
# 这里按 chat_service.dart 当前实现核对 —— 见下方真实代码引用
a.append({'role': 'user', 'content': '你好'})
dump('A: 新对话首轮(buildPrompt + sendStream)', a)

# ============ 场景 B:第 3 轮(有 2 轮历史) ============
b = [
    {'role': 'system', 'content': SYS},
    {'role': 'system', 'content': SYS},
    {'role': 'user', 'content': WARM_P},
    {'role': 'assistant', 'content': WARM_R},
    {'role': 'user', 'content': 'Q1'},
    {'role': 'assistant', 'content': 'A1' * 100},
    {'role': 'user', 'content': 'Q2'},
    {'role': 'assistant', 'content': 'A2' * 100},
    {'role': 'user', 'content': '你好'},
]
dump('B: 第 3 轮', b)

# ============ 审查点 ============
print("=== 审查点 ===")
print("1. 预热段位置:是否在 system 之后、真实历史之前?")
print("2. 三明治 system:是否插在预热段之后(会打断 system-user-assistant 连续前缀,破坏缓存)?")
print("3. 压缩摘要注入点:在哪个 system 里?")
print("4. 隐藏注入的 system 与顶部 system 是否重复相邻(浪费 token 且可能被服务端去重)?")
