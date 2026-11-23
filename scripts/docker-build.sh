#!/usr/bin/env bash
# ============================================================================
# docker-build.sh —— 一键流程（容器里跑，宿主机也能直接跑）
#
#   prepare-tree → fetch-toolchain → prepare-kernelsu → build → 重打包 boot.img
#
# 用法：
#   scripts/docker-build.sh            # 默认 boot：编译 + 出 boot.img
#   scripts/docker-build.sh image      # 只编译，出 out/Image
#
# 可用环境变量：
#   TARGET       image | boot（默认 boot）
#   VERSION      产物版本号（默认日期）
#   JOBS         并行度（默认 nproc，CI 里建议 3）
#   STOCK_BOOT_IMG  原厂 boot.img 路径
#   MAGISKBOOT   magiskboot 路径（不给则自动下载 Magisk APK 提取）
#
# 产物：out/Image、out/boot_Reno4_5G_KSU_<ver>.img、out/SHA256SUMS
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TARGET="${1:-${TARGET:-boot}}"
OUT="$ROOT/out"
KERNEL_DIR="${KERNEL_DIR:-$ROOT/kernel/msm-4.19}"
IMAGE="$KERNEL_DIR/out/arch/arm64/boot/Image"
VERSION="${VERSION:-$(date +%Y%m%d)}"

log() { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

case "$TARGET" in
    image|boot) ;;
    *) echo "用法: $0 [image|boot]" >&2; exit 2 ;;
esac

mkdir -p "$OUT"

log "1/5 准备官方源码树并打补丁"
bash scripts/prepare-tree.sh

log "2/5 下载工具链（clang-r399163b + GCC 4.9）"
bash scripts/fetch-toolchain.sh

log "3/5 拉取 KernelSU 并应用 4.19 适配补丁"
bash scripts/prepare-kernelsu.sh

log "4/5 编译内核（JOBS=${JOBS:-$(nproc)}）"
bash scripts/build.sh

[ -f "$IMAGE" ] || die "没有生成内核 Image：$IMAGE（看上面的编译日志）"
cp -f "$IMAGE" "$OUT/Image"
log "Image 就绪：$(ls -lh "$OUT/Image" | awk '{print $5}')  sha256=$(sha256sum "$OUT/Image" | awk '{print $1}')"

if [ "$TARGET" = "image" ]; then
    ( cd "$OUT" && sha256sum Image > SHA256SUMS )
    log "完成（只要 Image）：$OUT/Image"
    exit 0
fi

log "5/5 用原厂 boot.img 重打包"
STOCK="$(bash scripts/get-stock-boot.sh "$ROOT/boot/stock_boot.img" || true)"
if [ -z "${STOCK:-}" ] || [ ! -f "$STOCK" ]; then
    ( cd "$OUT" && sha256sum Image > SHA256SUMS )
    log "没有原厂 boot.img —— 本次只产出 Image。"
    log "给出原厂 boot.img 的任一方式后重跑即可得到 boot.img："
    log "  A) 放到 boot/stock_boot.img（推荐，已被 .gitignore 忽略）"
    log "  B) 上传成本仓库 Release 的 asset，文件名 stock_boot.img"
    log "  C) 设置 STOCK_BOOT_IMG / STOCK_BOOT_URL（可配 STOCK_BOOT_AUTH_HEADER）"
    exit 0
fi

MB="$(bash scripts/fetch-magiskboot.sh)"
BOOTIMG="$OUT/boot_Reno4_5G_KSU_${VERSION}.img"

MAGISKBOOT="$MB" bash scripts/repack_bootimg.sh "$STOCK" "$IMAGE" "$BOOTIMG"

( cd "$OUT" && sha256sum Image "$(basename "$BOOTIMG")" > SHA256SUMS )

log "完成"
ls -lh "$OUT"
cat "$OUT/SHA256SUMS"
echo
echo "刷入（确认机型后再执行）："
echo "  adb reboot bootloader"
echo "  fastboot flash boot '$BOOTIMG'"
echo "  fastboot reboot"
