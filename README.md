# AI Chat — Flutter

对话管理 + 聊天窗口。极简界面,所有配置隐藏在 `config.json`。

## 用户能看到的 UI
- **对话列表**:新建 / 重命名 / 删除
- **对话窗口**:输入消息 + 附加图片 + 附加文件 + 导出 MD(一问一答)
- **设置**:字号 / 颜色 (6 选 1) / 缓冲区大小 / 输出速度(后两项互斥)

## 开发者看到的 (`config.json`)
- `endpoint` / `apiKey`:**以密文持久化**(XOR + base64,密钥随机生成存于 `.chat_ai_salt`)
- `systemPrompts` / `recurringPrompts` / `context` 等全部结构

## 端点 / 密钥如何注入
仓库中 `assets/config.example.json` 只放占位符。**真实值不在仓库内**,通过两种方式注入:

### A) GitHub Actions Secrets(推荐,CI 用)
在仓库 **Settings → Secrets and variables → Actions → New repository secret** 添加:
- `API_ENDPOINT` = `https://server.344977.xyz:3001/v1`
- `API_KEY` = `wbk_8a15b5d6367d990a0f520074a667de9fd392f531d5689978`
- `API_MODEL` = `cn:deepseek-v4.1-flash`

CI 会以 `--dart-define` 注入到编译产物。运行时不会出现在明文日志或文件中。

### B) 本地构建
```bash
flutter build apk --release --obfuscate \
  --split-debug-info=build/symbols \
  --dart-define=API_ENDPOINT="..." \
  --dart-define=API_KEY="..." \
  --dart-define=API_MODEL="cn:deepseek-v4.1-flash"
```

应用首次启动时,内存中读到的 endpoint/apiKey 会被加密写入 `config.json`,之后不再需要 dart-define。

## 混淆 / 压缩措施
1. **Flutter `--obfuscate --split-debug-info`** — 类名 / 方法名混淆,symbols 单独上传到 artifact
2. **R8 + minify + shrinkResources** — 死代码删除,资源压缩
3. **ProGuard 规则** — `android/app/proguard-rules.pro`:`-optimizationpasses 5` `-allowaccessmodification` `-overloadaggressively` `-repackageclasses ''`
4. **SecretBox** — 端点 / 密钥运行时明文不入文件,以 XOR 密文存
5. **`config.example.json`** 不含真实密钥,占位符空字符串

## 模型选择
各模型 credits 比较(经 `https://server.344977.xyz:3001/v1/models` 抓取):
- 选 fast:**GLM-5.3-Flash / Deepseek-V4.1-Flash / Hy3-X / Space-Bunny**
- 默认:`cn:deepseek-v4.1-flash`(1M ctx, 393k 输出,x0.11 credit)

## 提示词轮询策略(开发者档)
- 持久系统提示词(始终在第一条 system 消息)
- 每 2~4 轮(user-assistant 对数计),在 user 消息前再注入一次持久 system 提示词 — 防止长对话遗忘约束;UI 不显示任何提示词标记
- 上下文压缩:消息数 ≥ `compressTriggerMessages`(默认 80)就调 LLM 摘要早期对话

## 构建
```bash
flutter pub get
flutter build apk --release --obfuscate --split-debug-info=build/symbols \
  --dart-define=API_ENDPOINT=... \
  --dart-define=API_KEY=... \
  --dart-define=API_MODEL=cn:deepseek-v4.1-flash
```