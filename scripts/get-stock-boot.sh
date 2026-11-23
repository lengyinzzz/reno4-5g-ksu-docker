#!/usr/bin/env bash
# ============================================================================
# get-stock-boot.sh —— 找一个可用的原厂 boot.img
#
# 成功：把 boot.img 的绝对路径打印到 stdout（日志走 stderr），退出码 0
# 失败：stdout 为空，退出码 3
#
# 查找顺序：
#   1. $STOCK_BOOT_IMG
#   2. boot/ 目录里的 stock_boot.img / boot.img / *.img
#   3. 本仓库 Release 里名为 stock_boot*.img 的 asset（需要 GITHUB_REPOSITORY + GITHUB_TOKEN）
#   4. $STOCK_BOOT_URL（可配 $STOCK_BOOT_AUTH_HEADER，形如 "Authorization: Bearer xxx"）
#   5. $STOCK_BOOT_IMG_B64（base64，只适合很小的镜像）
#
# 用法：
#   scripts/get-stock-boot.sh [目标路径]     # 默认 boot/stock_boot.img
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$ROOT/boot/stock_boot.img}"
mkdir -p "$(dirname "$DEST")"

log()  { printf '[stock-boot] %s\n' "$*" >&2; }
die()  { printf '[stock-boot][x] %s\n' "$*" >&2; exit 3; }
ok()   { log "使用 $1"; readlink -f "$1"; exit 0; }

is_bootimg() {
    [ -f "$1" ] || return 1
    python3 -c 'import sys;raise SystemExit(0 if open(sys.argv[1],"rb").read(8)==b"ANDROID!" else 1)' "$1"
}

# 0) 已经是 boot.img 就直接用
if is_bootimg "$DEST"; then ok "$DEST"; fi

# 1) 显式指定
if [ -n "${STOCK_BOOT_IMG:-}" ]; then
    if is_bootimg "$STOCK_BOOT_IMG"; then ok "$STOCK_BOOT_IMG"; fi
    log "$STOCK_BOOT_IMG 不是合法的 boot.img（magic 不是 ANDROID!），继续找"
fi

# 2) 仓库 boot/ 目录
for cand in "$ROOT/boot/stock_boot.img" "$ROOT/boot/boot.img" "$ROOT"/boot/*.img; do
    if is_bootimg "$cand"; then ok "$cand"; fi
done

# 3) Release asset
if [ -n "${GITHUB_REPOSITORY:-}" ] && [ -n "${GITHUB_TOKEN:-}" ]; then
    log "查找 $GITHUB_REPOSITORY 的 Release asset（stock_boot*.img）"
    python3 - "$DEST" <<'PY' || true
import json, os, sys, urllib.request

dest = sys.argv[1]
repo = os.environ["GITHUB_REPOSITORY"]
tok = os.environ["GITHUB_TOKEN"]

def req(url, accept="application/vnd.github+json"):
    return urllib.request.Request(url, headers={
        "Authorization": "Bearer " + tok,
        "Accept": accept,
        "User-Agent": "reno4-5g-ksu",
    })

try:
    with urllib.request.urlopen(req(f"https://api.github.com/repos/{repo}/releases?per_page=50"), timeout=60) as r:
        releases = json.load(r)
except Exception as e:  # noqa: BLE001
    print(f"[stock-boot] Release 列表读取失败：{e}", file=sys.stderr)
    raise SystemExit(0)

assets = [a for rel in releases for a in rel.get("assets", [])
          if a["name"].lower().startswith("stock_boot") and a["name"].lower().endswith(".img")]
if not assets:
    print("[stock-boot] Release 里没有 stock_boot*.img", file=sys.stderr)
    raise SystemExit(0)

a = assets[0]
os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
with urllib.request.urlopen(req(a["url"], "application/octet-stream"), timeout=600) as r, open(dest, "wb") as f:
    while True:
        chunk = r.read(1 << 20)
        if not chunk:
            break
        f.write(chunk)
print(f"[stock-boot] 已从 Release asset 下载 {a['name']} -> {dest}（{os.path.getsize(dest)} 字节）", file=sys.stderr)
PY
    if is_bootimg "$DEST"; then ok "$DEST"; fi
    rm -f "$DEST"
fi

# 4) 直链下载（也支持 zip 包，里面第一个 *.img 会被取出）
if [ -n "${STOCK_BOOT_URL:-}" ]; then
    log "下载 STOCK_BOOT_URL"
    python3 - "$DEST" "$STOCK_BOOT_URL" "${STOCK_BOOT_AUTH_HEADER:-}" <<'PY'
import sys, urllib.request

dest, url, auth = sys.argv[1], sys.argv[2], sys.argv[3]
headers = {"User-Agent": "reno4-5g-ksu"}
if auth:
    k, sep, v = auth.partition(":")
    if sep:
        headers[k.strip()] = v.strip()
with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=600) as r, open(dest, "wb") as f:
    while True:
        chunk = r.read(1 << 20)
        if not chunk:
            break
        f.write(chunk)
PY
    if [ -f "$DEST" ] && [ "$(head -c 2 "$DEST")" = "PK" ]; then
        log "下载的是 zip，取出里面的 boot img"
        python3 - "$DEST" <<'PY'
import sys, zipfile
src = sys.argv[1]
with zipfile.ZipFile(src) as z:
    names = [n for n in z.namelist() if n.lower().endswith(".img") and "boot" in n.lower()]
    if not names:
        sys.exit(0)
    with z.open(names[0]) as r, open(src, "wb") as f:
        f.write(r.read())
PY
    fi
    if is_bootimg "$DEST"; then ok "$DEST"; fi
    log "STOCK_BOOT_URL 下载的内容不是 boot.img，忽略"
    rm -f "$DEST"
fi

# 5) base64
if [ -n "${STOCK_BOOT_IMG_B64:-}" ]; then
    log "解码 STOCK_BOOT_IMG_B64"
    if printf '%s' "$STOCK_BOOT_IMG_B64" | base64 -d > "$DEST" 2>/dev/null; then
        if is_bootimg "$DEST"; then ok "$DEST"; fi
    fi
    log "STOCK_BOOT_IMG_B64 解码失败或不是 boot.img，忽略"
    rm -f "$DEST"
fi

log "没有找到原厂 boot.img"
log "  放一份到 boot/stock_boot.img，或上传成 Release asset（stock_boot.img），"
log "  或设置 STOCK_BOOT_IMG / STOCK_BOOT_URL / STOCK_BOOT_IMG_B64"
exit 3
