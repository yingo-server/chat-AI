# AI Chat — Flutter

对话管理 + 聊天窗口。极简界面,所有配置隐藏在 `config.json`。

## 用户能看到的 UI
- **对话列表**:新建 / 重命名 / 删除
- **对话窗口**:输入消息 + 附加图片 + 附加文件 + 导出 MD(一问一答)
- **设置**:字号 / 颜色 (6 选 1) / 缓冲区大小 / 输出速度(后两项互斥)

## 开发者看到的 (`config.json`)
- 仅含非敏感参数:`ai`(model / temperature / maxTokens 等非机密字段)、`systemPrompts` / `recurringPrompts` / `context` / `userPrefs`
- `endpoint` / `apiKey` **不在 config.json 中**,由 native vault 保护

## 端点 / 密钥如何注入
真实值不在仓库内。CI 在构建时从 `VAULT_MASTER` secret 生成 `assets/vault.bin`(SHA-256 keystream XOR 加密)和 `android/app/src/main/cpp/vault_master.h`(混淆后的 master),两者均已列入 `.gitignore`,不会提交。

运行时,`libvault.so` 用内嵌 master 解密 `vault.bin`,endpoint / apiKey 只存在于内存中的 `AiConfig`。

## 混淆 / 压缩措施
1. **Flutter `--obfuscate --split-debug-info`** — 类名 / 方法名混淆,symbols 单独上传到 artifact
2. **R8 + minify + shrinkResources** — 死代码删除,资源压缩
3. **ProGuard 规则** — `android/app/proguard-rules.pro`:`-optimizationpasses 5` `-allowaccessmodification` `-overloadaggressively` `-repackageclasses ''`
4. **Native vault** — 端点 / 密钥以 SHA-256 keystream XOR 密文存于 `vault.bin`,master 以混淆形式内嵌于 native 库;错误码为负数
5. **`config.example.json`** 不含真实密钥,占位符空字符串

## 模型选择
默认模型:`cn:deepseek-v4-flash`(在 `AiConfig` 中统一配置;占位示例端点 `https://your-endpoint/v1`,密钥 `YOUR_API_KEY`)。

## 提示词轮询策略(开发者档)
- **持久系统提示词**:始终作为第一条 system 消息
- **隐藏轮询注入**:每 2~4 轮(user-assistant 对数计),在 user 消息前再注入一次持久 system 提示词 — 防止长对话遗忘约束;UI 不显示任何提示词标记
- **上下文压缩**:消息数 ≥ `compressTriggerMessages`(默认 80)就调 LLM 摘要早期对话

## 构建
```bash
flutter pub get
flutter build apk --release --obfuscate --split-debug-info=build/symbols
```
(vault.bin / vault_master.h 由 CI 从 `VAULT_MASTER` secret 生成,本地构建需自行生成这两个文件。)
