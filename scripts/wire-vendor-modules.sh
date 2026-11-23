#!/usr/bin/env bash
# ============================================================================
# wire-vendor-modules.sh —— 把 vendor/oplus 模块接回内核构建
#
# 背景：OPPO 开源的内核树里，drivers/soc/oplus/* 和 include/soc/oplus/*
# 大量是**指向 vendor/ 的相对软链**（如 ../../../../../vendor/oplus/kernel/system/）。
# 这些软链假设的布局是 <root>/kernel/msm-4.19 + <root>/vendor/，
# 而 prepare-tree.sh 正好是这个布局，所以只要保证 kernel/vendor 能被解析即可。
#
# 本脚本负责三件事（全部幂等）：
#   1. kernel/vendor -> ../vendor 软链（关键：让所有 OPPO 相对软链活过来）
#   2. 内核树漏接的两个 vendor 模块：wakelock_profiler 软链 + Makefile obj-y
#   3. drivers/soc/oplus/Kconfig 里补 source，让 defconfig 里的
#      CONFIG_OPLUS_FEATURE_* / CONFIG_OPLUS_WAKELOCK_PROFILER 真正生效
#
# 用法：wire-vendor-modules.sh <内核树> <vendor 目录>
# ============================================================================
set -euo pipefail

KERNEL_DIR="${1:?用法: wire-vendor-modules.sh <内核树> <vendor>}"
VENDOR_DIR="${2:?用法: wire-vendor-modules.sh <内核树> <vendor>}"

ROOT="$(cd "$KERNEL_DIR/.." && pwd)"          # <root>/kernel
PROJECT="$(cd "$ROOT/.." && pwd)"             # <root>

log() { printf '[wire-vendor] %s\n' "$*"; }

[ -d "$VENDOR_DIR/oplus/kernel" ] || { echo "[x] 找不到 $VENDOR_DIR/oplus/kernel" >&2; exit 1; }

# 1) kernel/vendor
if [ ! -e "$ROOT/vendor" ]; then
    ln -sfn ../vendor "$ROOT/vendor"
    log "建立软链 $ROOT/vendor -> ../vendor"
else
    log "kernel/vendor 已存在"
fi

SOC="$KERNEL_DIR/drivers/soc/oplus"
VK="$VENDOR_DIR/oplus/kernel"

# 2) wakelock_profiler 软链（开源树漏了这个目录，模块实现只在 vendor 里）
if [ ! -e "$SOC/wakelock_profiler" ]; then
    ln -sfn ../../../../../vendor/oplus/kernel/wakelock_profiler "$SOC/wakelock_profiler"
    log "建立软链 drivers/soc/oplus/wakelock_profiler"
fi

# 3) Makefile 追加 obj-y
MK="$SOC/Makefile"
if ! grep -q 'oplus-vendor-wiring' "$MK" 2>/dev/null; then
    cat >> "$MK" <<'EOF'

# oplus-vendor-wiring: 开源树漏接的 vendor 模块（实现在 vendor/oplus/kernel）
obj-y += system/
obj-y += wakelock_profiler/
EOF
    log "drivers/soc/oplus/Makefile 追加 system/ wakelock_profiler/"
else
    log "Makefile 已接入过"
fi

# 4) Kconfig 追加 source
KC="$SOC/Kconfig"
if ! grep -q 'oplus-vendor-wiring' "$KC" 2>/dev/null; then
    cat >> "$KC" <<'EOF'

# oplus-vendor-wiring: 让 defconfig 里的 CONFIG_OPLUS_* 真正生效
source "drivers/soc/oplus/system/Kconfig"
source "drivers/soc/oplus/wakelock_profiler/Kconfig"
EOF
    log "drivers/soc/oplus/Kconfig 追加 source"
else
    log "Kconfig 已接入过"
fi

log "完成"
