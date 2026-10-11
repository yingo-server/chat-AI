# 镜像(仅本地使用)

> CI runner(GitHub Actions 等)有直连,不需要走代理。本节只描述**本地构建**时的加速。

## 本地
- 运行 `./setup-mirrors.sh` 一键设置:
  - `PUB_HOSTED_URL=https://proxy.344977.xyz/pub.dev`
  - `FLUTTER_STORAGE_BASE_URL=https://proxy.344977.xyz/flutter_infra_release`
  - Gradle init.gradle 走 `https://maven.proxy.344977.xyz/dl/android/maven2/...`

## 镜像映射规则
- `https://pub.dev/...`  → `https://proxy.344977.xyz/pub.dev/...`
- `https://storage.googleapis.com/flutter_infra_release/...` → `https://proxy.344977.xyz/flutter_infra_release/...`
- `https://dl.google.com/dl/android/maven2/...` → `https://maven.proxy.344977.xyz/dl/android/maven2/...`

> 仓库本身**不包含任何敏感凭据**。API key、token、密码都不要提交。