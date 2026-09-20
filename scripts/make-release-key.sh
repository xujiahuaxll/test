#!/usr/bin/env bash
#
# 生成一个固定的 release 签名，并打印出配置 GitHub Secrets 需要的四个值。
#
# 为什么需要它：高德 Key 绑定「包名 + 签名 SHA1」。CI 默认用 debug 签名，
# 而 debug keystore 是构建机现场生成的，每轮 CI 都是新机器、新 SHA1，
# 于是每构建一次就要重新登记一次 Key。固定签名之后这个问题一劳永逸。
#
# 用法：bash scripts/make-release-key.sh
#
# 需要 keytool（随 JDK 附带）。做 Android 开发的机器上基本都已经有了，
# 只是不一定在 PATH 上——Android Studio 自带的那套 JBR 就带 keytool。
# 下面会挨个找过去，实在找不到再让你装。
# 也可以自己指定：KEYTOOL=/path/to/keytool bash scripts/make-release-key.sh
set -euo pipefail

KEYSTORE="${1:-release.jks}"
ALIAS="release"

# 找 keytool。Windows 上可执行文件带 .exe，两种都试。
find_keytool() {
  if [ -n "${KEYTOOL:-}" ]; then
    command -v "$KEYTOOL" >/dev/null 2>&1 && { echo "$KEYTOOL"; return 0; }
    echo "指定的 KEYTOOL=$KEYTOOL 用不了。" >&2
    return 1
  fi

  if command -v keytool >/dev/null 2>&1; then
    command -v keytool
    return 0
  fi

  local candidates=()
  [ -n "${JAVA_HOME:-}" ] && candidates+=("$JAVA_HOME/bin/keytool")
  candidates+=(
    # Android Studio 自带的 JBR / JRE，做 Android 开发的机器上都有
    "/c/Program Files/Android/Android Studio/jbr/bin/keytool.exe"
    "/c/Program Files/Android/Android Studio/jre/bin/keytool.exe"
    "$HOME/AppData/Local/Programs/Android Studio/jbr/bin/keytool.exe"
    "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"
    "/Applications/Android Studio.app/Contents/jre/Contents/Home/bin/keytool"
    "$HOME/android-studio/jbr/bin/keytool"
  )
  local path
  for path in "${candidates[@]}"; do
    [ -x "$path" ] && { echo "$path"; return 0; }
  done

  # 独立安装的 JDK，按目录名猜
  for path in \
    "/c/Program Files/Eclipse Adoptium"/jdk*/bin/keytool.exe \
    "/c/Program Files/Java"/jdk*/bin/keytool.exe \
    /usr/lib/jvm/*/bin/keytool
  do
    [ -x "$path" ] && { echo "$path"; return 0; }
  done

  return 1
}

KEYTOOL_BIN="$(find_keytool)" || {
  echo "找不到 keytool。" >&2
  echo >&2
  echo "它随 JDK 附带，你多半已经有了，只是不在 PATH 上：" >&2
  echo "  · 装过 Android Studio 的话，它在" >&2
  echo "    C:\\Program Files\\Android\\Android Studio\\jbr\\bin\\keytool.exe" >&2
  echo "  · 用 flutter doctor -v 也能看到 Java 的位置" >&2
  echo >&2
  echo "找到之后这样跑：" >&2
  echo "  KEYTOOL='/c/Program Files/Android/Android Studio/jbr/bin/keytool.exe' \\" >&2
  echo "    bash scripts/make-release-key.sh" >&2
  echo >&2
  echo "都没有就装一个 JDK（如 Temurin 17）。" >&2
  exit 1
}
echo "用 $KEYTOOL_BIN"

if [ -e "$KEYSTORE" ]; then
  echo "『$KEYSTORE』已存在。" >&2
  echo "不要覆盖它——覆盖等于换了新私钥，SHA1 会变，已登记的 Key 会失效。" >&2
  echo "想重新生成请先改名备份。" >&2
  exit 1
fi

# 口令随机生成，省得你自己想，也避免用弱口令。
# 注意别用 `tr </dev/urandom | head -c N`：head 提前关管道会让 tr 收到
# SIGPIPE 返回非零，配上 set -euo pipefail 会把整个脚本静默干掉。
random_hex() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
  else
    od -An -tx1 -N16 /dev/urandom | tr -d ' \n'
  fi
}
PASSWORD="$(random_hex)"

"$KEYTOOL_BIN" -genkeypair -v \
  -keystore "$KEYSTORE" \
  -alias "$ALIAS" \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "$PASSWORD" -keypass "$PASSWORD" \
  -dname "CN=location_marker, OU=, O=, L=, S=, C=CN" >/dev/null

# keytool 偶尔会失败但退出码为 0（比如口令策略拦下来）。
# 不检查的话下一步 base64 会报 "No such file"，看着像脚本坏了。
if [ ! -s "$KEYSTORE" ]; then
  echo "keytool 没有生成『$KEYSTORE』。上面它自己的报错才是真正的原因。" >&2
  exit 1
fi

SHA1="$("$KEYTOOL_BIN" -list -v -keystore "$KEYSTORE" -alias "$ALIAS" \
  -storepass "$PASSWORD" 2>/dev/null |
  grep -i 'SHA1:' | head -1 | sed 's/.*SHA1: *//')"

# base64 的换行会破坏 Secret，必须去掉
if base64 --help 2>&1 | grep -q -- '-w'; then
  B64="$(base64 -w0 "$KEYSTORE")"
else
  B64="$(base64 "$KEYSTORE" | tr -d '\n')"
fi

cat <<INFO

================= 生成完毕 =================

keystore 文件：$KEYSTORE
  这是私钥，丢了就再也无法给这个 App 发更新，请自己备份好。
  不要提交进仓库（.gitignore 已经挡了 *.jks）。

到高德开放平台登记这个 SHA1（配一次，以后不用再改）：

  包名   com.example.location_marker
  SHA1   $SHA1

到 GitHub → Settings → Secrets and variables → Actions
新建四个 Repository secret：

  ANDROID_KEY_ALIAS           $ALIAS
  ANDROID_KEYSTORE_PASSWORD   $PASSWORD
  ANDROID_KEY_PASSWORD        $PASSWORD

  ANDROID_KEYSTORE_BASE64     （下面这一长串，整行复制）

$B64

============================================

配好之后重新触发一次构建，日志里会显示
「签名来源：固定的 release keystore，每次构建一致」，
之后每次打包的 SHA1 都是上面那个，Key 一直有效。

INFO
