#!/usr/bin/env bash
# ============================================================================
# fetch-magiskboot.sh —— 准备 magiskboot（Linux x86_64，重打包 boot.img 用）
#
# 成功：把可执行文件绝对路径打印到 stdout，退出码 0
#
# 来源顺序：
#   1. $MAGISKBOOT
#   2. <repo>/tools/magiskboot（已下载过）
#   3. PATH 里的 magiskboot
#   4. 从 Magisk APK 里提取 lib/x86_64/libmagiskboot.so
#      （版本用 MAGISK_VERSION 覆盖，默认 27.0；或用 MAGISK_APK_URL 给直链）
#
# 用法：
#   scripts/fetch-magiskboot.sh [输出路径]
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/tools/magiskboot}"

log() { printf '[magiskboot] %s\n' "$*" >&2; }
die() { printf '[magiskboot][x] %s\n' "$*" >&2; exit 4; }

if [ -n "${MAGISKBOOT:-}" ] && [ -x "$MAGISKBOOT" ]; then
    log "使用 MAGISKBOOT=$MAGISKBOOT"
    readlink -f "$MAGISKBOOT"
    exit 0
fi

if [ -x "$OUT" ]; then
    log "已存在：$OUT"
    readlink -f "$OUT"
    exit 0
fi

if command -v magiskboot >/dev/null 2>&1; then
    log "使用 PATH 中的 magiskboot：$(command -v magiskboot)"
    readlink -f "$(command -v magiskboot)"
    exit 0
fi

arch="$(uname -m)"
if [ "$arch" != "x86_64" ]; then
    die "magiskboot 只有 x86_64 二进制，当前机器是 $arch。请在 x86_64 Linux（或 Docker / GitHub Actions）里重打包，"
fi

VER="${MAGISK_VERSION:-27.0}"
URL="${MAGISK_APK_URL:-https://github.com/topjohnwu/Magisk/releases/download/v${VER}/Magisk-v${VER}.apk}"

mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

log "下载 Magisk APK（$URL）"
python3 - "$tmp/magisk.apk" "$URL" <<'PY'
import sys, urllib.request

dest, url = sys.argv[1], sys.argv[2]
req = urllib.request.Request(url, headers={"User-Agent": "reno4-5g-ksu"})
with urllib.request.urlopen(req, timeout=600) as r, open(dest, "wb") as f:
    total = 0
    while True:
        chunk = r.read(1 << 20)
        if not chunk:
            break
        f.write(chunk)
        total += len(chunk)
print(f"[magiskboot] 已下载 {total} 字节", file=sys.stderr)
PY

ent="$(unzip -Z1 "$tmp/magisk.apk" | grep -E '^lib/x86_64/(libmagiskboot\.so|magiskboot)$' | head -n 1 || true)"
if [ -z "$ent" ]; then
    # 兜底：任何 x86_64 目录下的 magiskboot
    ent="$(unzip -Z1 "$tmp/magisk.apk" | grep -E '(^|/)x86_64/.*(libmagiskboot\.so|magiskboot)$' | head -n 1 || true)"
fi
[ -n "$ent" ] || die "APK 里找不到 magiskboot（换 MAGISK_VERSION 或设置 MAGISKBOOT）"
log "从 APK 提取 $ent"

unzip -p "$tmp/magisk.apk" "$ent" > "$OUT.tmp"
chmod 0755 "$OUT.tmp"

if command -v file >/dev/null 2>&1; then
    desc="$(file -b "$OUT.tmp")"
    case "$desc" in
        *"x86-64"*|*"x86_64"*) : ;;
        *) rm -f "$OUT.tmp"; die "提取到的 magiskboot 不是 x86_64 二进制：$desc" ;;
    esac
fi

mv -f "$OUT.tmp" "$OUT"
log "冒烟测试"
if ! "$OUT" 2>&1 | head -n 5; then
    die "magiskboot 无法执行（缺依赖？）"
fi

log "OK：$OUT"
readlink -f "$OUT"
