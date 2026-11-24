#!/usr/bin/env bash
# ============================================================================
# docker-build.sh —— 一键流程（容器里跑，宿主机也能直接跑）
#
#   prepare-tree → fetch-toolchain → prepare-kernelsu → build → 重打包 boot.img
#
# 用法：
#   scripts/docker-build.sh                     # 默认 enforcing + boot.img
#   VARIANT=permissive scripts/docker-build.sh  # SELinux 宽容变体
#   scripts/docker-build.sh image               # 只编译，出 Image
#
# 可用环境变量：
#   TARGET       image | boot（默认 boot）
#   VARIANT      enforcing | permissive（默认 enforcing）
#   VERSION      产物版本号（默认日期）
#   JOBS         并行度（默认 nproc，CI 里建议 3）
#   STOCK_BOOT_IMG  原厂 boot.img 路径
#   MAGISKBOOT   magiskboot 路径（不给则自动下载 Magisk APK 提取）
#
# 产物：
#   out/Image_<variant>
#   out/boot_Reno4_5G_KSU_<ver>_<variant>.img
#   out/SHA256SUMS
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TARGET="${1:-${TARGET:-boot}}"
VARIANT="${VARIANT:-enforcing}"
OUT="$ROOT/out"
KERNEL_DIR="${KERNEL_DIR:-$ROOT/kernel/msm-4.19}"
VERSION="${VERSION:-$(date +%Y%m%d)}"

log() { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

case "$TARGET" in
    image|boot) ;;
    *) echo "用法: $0 [image|boot]" >&2; exit 2 ;;
esac

case "$VARIANT" in
    enforcing)
        ;;
    permissive)
        export KSU_FORCE_PERMISSIVE=1
        export KCFLAGS="${KCFLAGS:--Wno-error=strict-prototypes} -DKSU_FORCE_PERMISSIVE"
        export OUT_DIR="${OUT_DIR:-$KERNEL_DIR/out-permissive}"
        ;;
    noksu|magisk)
        # 不带 KernelSU：编出来的 boot.img 给 Magisk 修补用
        export KSU=0
        export OUT_DIR="${OUT_DIR:-$KERNEL_DIR/out-noksu}"
        ;;
    docker)
        # 不带 KernelSU + 开启容器所需内核选项（最小集）
        export KSU=0
        export DOCKER=1
        export DOCKER_SET=min
        export OUT_DIR="${OUT_DIR:-$KERNEL_DIR/out-docker}"
        ;;
    docker_a|docker_b|docker_c|docker_d)
        # 二分验证：单独开启某一项，用于定位哪个开关影响网络
        export KSU=0
        export DOCKER=1
        export DOCKER_SET="${VARIANT#docker_}"
        export OUT_DIR="${OUT_DIR:-$KERNEL_DIR/out-${VARIANT}}"
        ;;
    *)
        die "VARIANT 只能是 enforcing / permissive / noksu / docker / docker_a..d（当前：$VARIANT）"
        ;;
esac

OUT_DIR="${OUT_DIR:-$KERNEL_DIR/out}"
IMAGE="$OUT_DIR/arch/arm64/boot/Image"

mkdir -p "$OUT"

log "变体：$VARIANT"
log "1/5 准备官方源码树并打补丁"
bash scripts/prepare-tree.sh

log "2/5 下载工具链（clang-r399163b + GCC 4.9）"
bash scripts/fetch-toolchain.sh

log "3/5 拉取 KernelSU 并应用 4.19 适配补丁"
bash scripts/prepare-kernelsu.sh

log "4/5 编译内核（JOBS=${JOBS:-$(nproc)}，OUT_DIR=$OUT_DIR）"
bash scripts/build.sh

[ -f "$IMAGE" ] || die "没有生成内核 Image：$IMAGE（看上面的编译日志）"
cp -f "$IMAGE" "$OUT/Image_${VARIANT}"
log "Image 就绪：$(ls -lh "$OUT/Image_${VARIANT}" | awk '{print $5}')  sha256=$(sha256sum "$OUT/Image_${VARIANT}" | awk '{print $1}')"

if [ "$TARGET" = "image" ]; then
    ( cd "$OUT" && sha256sum "Image_${VARIANT}" > "SHA256SUMS_${VARIANT}" )
    log "完成（只要 Image）：$OUT/Image_${VARIANT}"
    exit 0
fi

log "5/5 用原厂 boot.img 重打包"
STOCK="$(bash scripts/get-stock-boot.sh "$ROOT/boot/stock_boot.img" || true)"
if [ -z "${STOCK:-}" ] || [ ! -f "$STOCK" ]; then
    ( cd "$OUT" && sha256sum "Image_${VARIANT}" > "SHA256SUMS_${VARIANT}" )
    log "没有原厂 boot.img —— 本次只产出 Image。"
    log "给出原厂 boot.img 的任一方式后重跑即可得到 boot.img："
    log "  A) 放到 boot/stock_boot.img（推荐，已被 .gitignore 忽略）"
    log "  B) 上传成本仓库 Release 的 asset，文件名 stock_boot.img"
    log "  C) 设置 STOCK_BOOT_IMG / STOCK_BOOT_URL（可配 STOCK_BOOT_AUTH_HEADER）"
    exit 0
fi

MB="$(bash scripts/fetch-magiskboot.sh)"
if [ "$VARIANT" = "noksu" ]; then
    BOOTIMG="$OUT/boot_Reno4_5G_Magisk_${VERSION}.img"
elif [ "$VARIANT" = "docker" ]; then
    BOOTIMG="$OUT/boot_Reno4_5G_Magisk_Docker_${VERSION}.img"
elif [ "$VARIANT" = "docker_a" ]; then
    BOOTIMG="$OUT/boot_Reno4_5G_DockerA_onlySYSVIPC_${VERSION}.img"
elif [ "$VARIANT" = "docker_b" ]; then
    BOOTIMG="$OUT/boot_Reno4_5G_DockerB_onlyCGROUPDEV_${VERSION}.img"
elif [ "$VARIANT" = "docker_c" ]; then
    BOOTIMG="$OUT/boot_Reno4_5G_DockerC_onlyPIDNS_${VERSION}.img"
elif [ "$VARIANT" = "docker_d" ]; then
    BOOTIMG="$OUT/boot_Reno4_5G_DockerD_SYSVIPC_IPCNS_${VERSION}.img"
else
    BOOTIMG="$OUT/boot_Reno4_5G_KSU_${VERSION}_${VARIANT}.img"
fi

MAGISKBOOT="$MB" bash scripts/repack_bootimg.sh "$STOCK" "$IMAGE" "$BOOTIMG"

( cd "$OUT" && sha256sum "Image_${VARIANT}" "$(basename "$BOOTIMG")" > "SHA256SUMS_${VARIANT}" )

log "完成（$VARIANT）"
ls -lh "$OUT"
cat "$OUT/SHA256SUMS_${VARIANT}"
echo
echo "刷入（确认机型后再执行）："
echo "  adb reboot bootloader"
echo "  fastboot flash boot '$BOOTIMG'"
echo "  fastboot reboot"
echo
echo "刷完检查 SELinux 状态：adb shell getenforce"
echo "  enforcing  版期望 Enforcing；permissive 版期望 Permissive"
