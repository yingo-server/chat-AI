# AI Chat — Flutter

Material 3 重写的本地 AI 对话应用。**单用户**,对话保存在本地 SQLite,无任何云端依赖(除 LLM API)。

## 特性

- ✅ **纯本地存储**:对话、消息、配置全部在应用文档目录
- ✅ **Material 3**:全部使用 M3 原生组件(`Card` / `Chip` / `MaterialBanner` / `PopupMenuButton` / `Slider` / `DropdownButton` / `NavigationBar` 等),无自定义 paint
- ✅ **流式缓冲**:LLM 输出按 ~24 字/秒自动节流,缓冲 50 字,设置页可调 4~120
- ✅ **后台上下文压缩**:达到阈值自动调 LLM 摘要早期消息,UI 无感
- ✅ **周期提示词轮询**:多条提示词按 roundRobin / all / random 模式自动注入
- ✅ **可配置提示词体系**:系统提示词模板 + 对话级追加提示词 + 周期提示词,均通过 `config.json` 驱动
- ✅ **导出**:JSON / Markdown / 纯文本,任意对话右上角分享按钮
- ✅ **提示词调度状态可视化**:仅开发者面板可见

## 目录结构

```
AI_Flutter/
├── lib/
│   ├── main.dart
│   ├── models/        # 数据模型 + AppConfig + PromptScheduler
│   ├── db/            # SQLite 持久层
│   ├── services/      # LLM 客户端、聊天服务、配置、导出
│   ├── screens/       # home / chat / settings
│   ├── widgets/       # chat / animation / stream / prompt
│   ├── theme/         # M3 主题
│   └── utils/
├── assets/config.example.json   # 默认配置示例
├── .github/workflows/build.yml  # GitHub Actions 自动构建
├── setup-mirrors.sh             # 镜像加速配置
├── build.sh                     # 本地构建脚本
└── MIRRORS.md
```

## CI / 构建

### GitHub Actions
`.github/workflows/build.yml`:
- 触发:push / PR / tag / 手动
- 输出:APK(分 ABI) + AAB,作为 artifact;tag 推送自动挂到 Release
- 加速:所有外部依赖走 `proxy.344977.xyz` 与 `gh.proxy.344977.xyz`

### 本地构建
```bash
./setup-mirrors.sh   # 配置加速镜像
./build.sh apk       # 或 aab / all
```

## 快速开始

1. 启动应用 → 进入设置页
2. 填写 API:
   - Endpoint (OpenAI 兼容)
   - API Key
   - Model 名
3. 流速按需调整(Slider 4~120 字/秒)
4. 添加系统提示词模板 / 周期提示词
5. 回首页 → 新建对话 → 开始

配置写入应用文档目录的 `config.json`,也可手动复制 `assets/config.example.json`。

## 镜像说明
详见 [MIRRORS.md](./MIRRORS.md)。