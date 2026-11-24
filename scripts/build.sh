#!/usr/bin/env bash
# ============================================================================
# build.sh —— 编译 OPPO Reno4 5G (SM7250 / lito) 内核 4.19.157
#
# 前置：scripts/prepare-tree.sh、scripts/fetch-toolchain.sh、scripts/prepare-kernelsu.sh
#
# 用法：
#   scripts/build.sh
#
# 可用环境变量覆盖：
#   KERNEL_DIR     内核树路径           (默认 <repo>/kernel/msm-4.19)
#   TOOLCHAIN_DIR  工具链路径           (默认 <repo>/toolchain)
#   DEFCONFIG      defconfig 相对路径    (默认 vendor/stock_lito_defconfig)
#   OUT_DIR        输出目录              (默认 <KERNEL_DIR>/out)
#   JOBS           并行度                (默认 nproc)
#   KCFLAGS        额外编译参数          (默认 -Wno-error=strict-prototypes)
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL_DIR="${KERNEL_DIR:-$ROOT/kernel/msm-4.19}"
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$ROOT/toolchain}"
DEFCONFIG="${DEFCONFIG:-vendor/stock_lito_defconfig}"
OUT_DIR="${OUT_DIR:-$KERNEL_DIR/out}"
JOBS="${JOBS:-$(nproc)}"
# OPPO vendor 代码里有大量旧式 foo() 定义，clang 的 -Werror 会报 strict-prototypes
KCFLAGS="${KCFLAGS:--Wno-error=strict-prototypes}"

CLANG_BIN="$TOOLCHAIN_DIR/clang-r399163b/bin"
GCC64_BIN="$TOOLCHAIN_DIR/aarch64-linux-android-4.9/bin"
GCC32_BIN="$TOOLCHAIN_DIR/arm-linux-androideabi-4.9/bin"

log() { printf '\033[1;34m>>>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[ -d "$KERNEL_DIR" ]                || die "找不到内核树：$KERNEL_DIR（先运行 scripts/prepare-tree.sh）"
[ -x "$CLANG_BIN/clang" ]           || die "找不到 clang：$CLANG_BIN/clang（先运行 scripts/fetch-toolchain.sh）"
[ -x "$GCC64_BIN/aarch64-linux-android-gcc" ] || die "找不到 aarch64 GCC：$GCC64_BIN"
[ -x "$GCC32_BIN/arm-linux-androideabi-gcc" ] || die "找不到 arm32 GCC：$GCC32_BIN"
[ -f "$KERNEL_DIR/arch/arm64/configs/$DEFCONFIG" ] || die "找不到 defconfig：$DEFCONFIG"
if [ ! -e "$KERNEL_DIR/drivers/kernelsu" ]; then
    die "缺少 drivers/kernelsu（先运行 scripts/prepare-kernelsu.sh）"
fi

export ARCH=arm64
export PATH="$CLANG_BIN:$GCC64_BIN:$GCC32_BIN:$PATH"

MAKE_CMD=(make -C "$KERNEL_DIR" O="$OUT_DIR" CC=clang
          CROSS_COMPILE=aarch64-linux-android-
          CROSS_COMPILE_ARM32=arm-linux-androideabi-
          CLANG_TRIPLE=aarch64-linux-gnu-
          KCFLAGS="$KCFLAGS")

log "defconfig: $DEFCONFIG"
"${MAKE_CMD[@]}" "$DEFCONFIG"

# noksu 变体：defconfig 里 CONFIG_KSU=y，这里显式关掉（含依赖的子项由 olddefconfig 收拾）
if [ "${KSU:-1}" = "0" ]; then
    log "noksu：关闭 CONFIG_KSU"
    ( cd "$KERNEL_DIR" && scripts/config --file "$OUT_DIR/.config" --disable KSU )
    "${MAKE_CMD[@]}" olddefconfig
    if grep -q '^CONFIG_KSU=y' "$OUT_DIR/.config"; then
        die "CONFIG_KSU 仍然是 y，noksu 构建中止"
    fi
    log "已确认 CONFIG_KSU 关闭"
fi

# docker 变体：按 DOCKER_SET 决定要额外打开哪些项（用于二分定位哪个开关影响网络）
#   min（默认）：SYSVIPC + PID_NS + IPC_NS + CGROUP_DEVICE
#   a / b / c / d：单独验证 SYSVIPC / CGROUP_DEVICE / PID_NS / IPC_NS
if [ "${DOCKER:-0}" = "1" ]; then
    case "${DOCKER_SET:-min}" in
        a) DOCKER_OPTS="SYSVIPC" ;;
        b) DOCKER_OPTS="CGROUP_DEVICE" ;;
        c) DOCKER_OPTS="PID_NS" ;;
        d) DOCKER_OPTS="SYSVIPC IPC_NS" ;;
        e) DOCKER_OPTS="PID_NS CGROUP_DEVICE" ;;
        min|*) DOCKER_OPTS="SYSVIPC PID_NS IPC_NS CGROUP_DEVICE" ;;
    esac
    log "docker 变体（set=${DOCKER_SET:-min}）：开启 $DOCKER_OPTS"
    set -- 
    for opt in $DOCKER_OPTS; do set -- "$@" "--enable" "$opt"; done
    ( cd "$KERNEL_DIR" && scripts/config --file "$OUT_DIR/.config" "$@" )
    "${MAKE_CMD[@]}" olddefconfig
    for opt in $DOCKER_OPTS; do
        if ! grep -q "^CONFIG_${opt}=y" "$OUT_DIR/.config"; then
            die "docker 变体：CONFIG_${opt} 未能开启"
        fi
    done
    for opt in USER_NS BRIDGE_NETFILTER VXLAN MACVLAN IPVLAN; do
        if grep -q "^CONFIG_${opt}=y" "$OUT_DIR/.config"; then
            die "docker 变体：不应开启 CONFIG_${opt}"
        fi
    done
    log "已确认：$DOCKER_OPTS 全部生效，且网络相关开关未被打开"
fi

log "编译（-j$JOBS，KCFLAGS=\"$KCFLAGS\"）"
"${MAKE_CMD[@]}" -j"$JOBS"

log "完成："
ls -lh "$OUT_DIR/arch/arm64/boot/Image" 2>/dev/null || die "没有生成 Image，请检查上面的日志"
echo
echo "  下一步：scripts/repack_bootimg.sh <你的原厂 boot.img> $OUT_DIR/arch/arm64/boot/Image new-boot.img"
