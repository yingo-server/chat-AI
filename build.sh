#!/usr/bin/env bash
# 本地构建 APK / App Bundle
# 用法: ./build.sh [apk|aab|all] [--debug|--release]
set -e

PROXY_HOST="${PROXY_HOST:-proxy.344977.xyz}"
GH_PROXY="${GH_PROXY:-gh.proxy.344977.xyz}"

# ---- 镜像加速 ----
export PUB_HOSTED_URL="https://$PROXY_HOST/pub.dev"
export FLUTTER_STORAGE_BASE_URL="https://$GH_PROXY/flutter_infra_release"
export FLUTTER_GIT_URL="https://$GH_PROXY/flutter/flutter.git"

TARGET="${1:-apk}"
MODE="${2:---release}"

case "$TARGET" in
  apk|aab|all) ;;
  *) echo "用法: $0 [apk|aab|all] [--debug|--release]"; exit 1 ;;
esac

echo "==> Flutter 镜像: $FLUTTER_STORAGE_BASE_URL"
echo "==> Pub 镜像:   $PUB_HOSTED_URL"

flutter --version
flutter pub get

flutter analyze

if [[ "$TARGET" == "apk" || "$TARGET" == "all" ]]; then
  echo "==> 构建 APK ($MODE)..."
  if [[ "$MODE" == "--release" ]]; then
    flutter build apk --release --split-per-abi
  else
    flutter build apk --debug --split-per-abi
  fi
fi

if [[ "$TARGET" == "aab" || "$TARGET" == "all" ]]; then
  echo "==> 构建 App Bundle ($MODE)..."
  flutter build appbundle $MODE
fi

echo
echo "==> 产物:"
find build/app/outputs -maxdepth 4 \( -name "*.apk" -o -name "*.aab" \) -printf "  %p  (%s bytes)\n" 2>/dev/null || true