# 加速镜像

中国大陆 / 受限网络下,Flutter / pub / Gradle / Android Maven 都需要镜像。
本项目统一通过 `proxy.344977.xyz` 与 `gh.proxy.344977.xyz` 转发。

## CI(GitHub Actions)
见 `.github/workflows/build.yml`,已在脚本中写入镜像环境变量。

## 本地
- 运行 `./setup-mirrors.sh` 一键设置:
  - `PUB_HOSTED_URL=https://proxy.344977.xyz/pub.dev`
  - `FLUTTER_STORAGE_BASE_URL=https://gh.proxy.344977.xyz/flutter_infra_release`
  - `GRADLE_USER_HOME` 配 `init.gradle` 走 `https://maven.proxy.344977.xyz/...`
  - Android SDK 走 `https://dl.google.com.proxy.344977.xyz/...`

## 镜像映射规则
- `https://pub.dev/...`  → `https://proxy.344977.xyz/pub.dev/...`
- `https://github.com/...`(git clone) → `https://gh.proxy.344977.xyz/github.com/...`
- `https://storage.googleapis.com/flutter_infra_release/...` → `https://gh.proxy.344977.xyz/flutter_infra_release/...`
- `https://dl.google.com/dl/android/maven2/...` → `https://maven.proxy.344977.xyz/dl/android/maven2/...`

> 注意:仓库本身**不包含任何敏感凭据**。API key、token、密码都不要提交。