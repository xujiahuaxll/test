#!/usr/bin/env bash
# 下载离线中文语音识别模型，放进 assets/asr/。
#
# 为什么不把模型直接提交进仓库：那个 .onnx 有 78 MB。虽然没超 GitHub 单文件
# 100 MB 的上限，但它和仓库里其它东西的更新节奏毫无关系，提交进去的后果是
# 从此每次 clone 都要拖一份，而且以后换模型还会在历史里再留一份。
# 改成构建前下载，本地开发和 CI 跑同一个脚本，assets/asr/ 进 .gitignore。
#
# 用法：
#   bash scripts/fetch-asr-model.sh
# 已经下好就直接跳过，可以反复跑。

set -euo pipefail

MODEL_NAME="sherpa-onnx-paraformer-zh-small-2024-03-09"
BASE_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models"
ARCHIVE="${MODEL_NAME}.tar.bz2"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/assets/asr"

# 运行时真正用得上的只有这两个。压缩包里还有测试 wav、训练脚本和
# config.yaml，那些不进 APK——带上就是白白让安装包大一圈。
MODEL_FILE="model.int8.onnx"
TOKENS_FILE="tokens.txt"

# 一段官方的中文测试录音，给 test/asr_pipeline_test.dart 用。
# 不进 APK（放在 assets/ 之外），也不进 git。没有它测试会自动跳过。
SAMPLE_FILE="test_wavs/0.wav"
SAMPLE_DEST="$ROOT/.asr-test/sample.wav"

# 下完之后校验用。大小对不上说明下到一半断了，或者上游换了文件。
EXPECT_MODEL_BYTES=81828675
EXPECT_TOKENS_BYTES=75352

if [ -s "$DEST/$MODEL_FILE" ] && [ -s "$DEST/$TOKENS_FILE" ] &&
   [ -s "$SAMPLE_DEST" ]; then
  echo "模型已经在 $DEST，跳过下载。"
  echo "  $MODEL_FILE  $(wc -c <"$DEST/$MODEL_FILE") 字节"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "正在下载 $ARCHIVE（约 74 MB）…"
curl -fL --retry 4 --retry-delay 2 -o "$TMP/$ARCHIVE" "$BASE_URL/$ARCHIVE"

echo "解包…"
tar -xjf "$TMP/$ARCHIVE" -C "$TMP" \
  "$MODEL_NAME/$MODEL_FILE" "$MODEL_NAME/$TOKENS_FILE" "$MODEL_NAME/$SAMPLE_FILE"

mkdir -p "$DEST" "$(dirname "$SAMPLE_DEST")"
mv "$TMP/$MODEL_NAME/$MODEL_FILE" "$DEST/$MODEL_FILE"
mv "$TMP/$MODEL_NAME/$TOKENS_FILE" "$DEST/$TOKENS_FILE"
mv "$TMP/$MODEL_NAME/$SAMPLE_FILE" "$SAMPLE_DEST"

actual_model=$(wc -c <"$DEST/$MODEL_FILE")
actual_tokens=$(wc -c <"$DEST/$TOKENS_FILE")

if [ "$actual_model" -ne "$EXPECT_MODEL_BYTES" ] ||
   [ "$actual_tokens" -ne "$EXPECT_TOKENS_BYTES" ]; then
  echo "警告：文件大小和预期不一样。" >&2
  echo "  $MODEL_FILE  预期 $EXPECT_MODEL_BYTES，实际 $actual_model" >&2
  echo "  $TOKENS_FILE 预期 $EXPECT_TOKENS_BYTES，实际 $actual_tokens" >&2
  echo "上游可能换了模型。确认没问题就把脚本里的预期值改掉。" >&2
  exit 1
fi

echo "好了：$DEST"
echo "  $MODEL_FILE  $actual_model 字节"
echo "  $TOKENS_FILE $actual_tokens 字节"
echo "  测试音频     $SAMPLE_DEST"
