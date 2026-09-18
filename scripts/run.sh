#!/usr/bin/env bash
# 从 android/amap.properties 读高德 Key，拼成 --dart-define 传给 flutter，
# 保证 Dart 侧与原生侧用的是同一份 Key。
#
#   ./scripts/run.sh                 # flutter run
#   ./scripts/run.sh build apk       # 其它 flutter 子命令照常透传
set -euo pipefail

cd "$(dirname "$0")/.."

PROPS="android/amap.properties"
ANDROID_KEY=""
IOS_KEY=""

if [ -f "$PROPS" ]; then
  ANDROID_KEY=$(grep -E '^AMAP_ANDROID_KEY=' "$PROPS" | cut -d= -f2- || true)
  IOS_KEY=$(grep -E '^AMAP_IOS_KEY=' "$PROPS" | cut -d= -f2- || true)
else
  echo "提示：没有找到 $PROPS，地图将显示为本地示意图。" >&2
  echo "     复制 android/amap.properties.example 并填入自己的 Key。" >&2
fi

CMD=("${@:-run}")

exec flutter "${CMD[@]}" \
  --dart-define=AMAP_ANDROID_KEY="$ANDROID_KEY" \
  --dart-define=AMAP_IOS_KEY="$IOS_KEY"
