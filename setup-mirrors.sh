#!/usr/bin/env bash
# 配置 Flutter / pub / Gradle / Android Maven 镜像加速
# 已对接到 proxy.344977.xyz 与 gh.proxy.344977.xyz
set -e

PROXY_HOST="${PROXY_HOST:-proxy.344977.xyz}"
GH_PROXY="${GH_PROXY:-gh.proxy.344977.xyz}"

echo "==> 使用镜像前缀: $PROXY_HOST  / $GH_PROXY"

# Flutter 自身
export PUB_HOSTED_URL="https://$PROXY_HOST/pub.dev"
export FLUTTER_STORAGE_BASE_URL="https://$GH_PROXY/flutter_infra_release"
export FLUTTER_GIT_URL="https://$GH_PROXY/flutter/flutter.git"

# Dart pub 永久配置
mkdir -p ~/.config/dart
cat > ~/.config/dart/pub-cache.json <<JSON
{
  "fluttterRoot": null,
  "dependencyCaching": { "cacheMode": "use" }
}
JSON

# Gradle init.gradle — 强制所有 maven 走镜像
mkdir -p ~/.gradle
cat > ~/.gradle/init.gradle <<GRADLE
allprojects {
    buildscript {
        repositories {
            maven { url 'https://maven.$PROXY_HOST/dl/android/maven2/' }
            maven { url 'https://maven.$PROXY_HOST/google/' }
            mavenCentral()
            google()
        }
    }
    repositories {
        maven { url 'https://maven.$PROXY_HOST/dl/android/maven2/' }
        maven { url 'https://maven.$PROXY_HOST/google/' }
        mavenCentral()
        google()
    }
}
settingsEvaluated { settings ->
    settings.pluginManagement {
        repositories {
            maven { url 'https://maven.$PROXY_HOST/dl/android/maven2/gradle-plugins/' }
            gradlePluginPortal()
        }
    }
}
GRADLE

# 写一份给本项目 android/ 子目录看的 .properties 提示
cat > android/local.properties.example <<PROPS
sdk.dir=/opt/android-sdk
flutter.sdk=/opt/flutter
PROPS

echo "==> 镜像配置完成"
echo "现在可以运行:"
echo "   flutter pub get"
echo "   flutter build apk --release"