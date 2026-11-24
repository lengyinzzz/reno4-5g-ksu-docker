#!/usr/bin/env bash
# ============================================================================
# wire-vendor-modules.sh —— 把 vendor/oplus 模块接回内核构建
#
# 背景：
#   1. OPPO 开源内核树里 drivers/soc/oplus/* 与 include/soc/oplus/* 大量是
#      **指向 ../../../../../vendor/oplus/kernel/ 的相对软链**，这些软链假设
#      <root>/kernel/msm-4.19 + <root>/vendor 的布局，所以先保证 kernel/vendor 存在。
#   2. drivers/soc/Makefile 里已经有：
#        obj-$(CONFIG_OPLUS_SYSTEM_KERNEL)  += oplus/system/
#        obj-$(CONFIG_OPLUS_WAKELOCK_PROFILER) += oplus/owakelock/
#      所以不要再往 drivers/soc/oplus/Makefile 里追加 obj-y，否则同一目录
#      会被编译两次（vmlinux 链接时 multiple definition）。
#      但 oplus/owakelock 这层软链是 OPPO 在 OplusKernelEnvConfig.mk 里现建的，
#      它算的路径在开源布局下是错的，所以这里自己建。
#   3. CONFIG_OPLUS_* 要有 Kconfig 定义，defconfig 里的值才会生效。
#
# 用法：wire-vendor-modules.sh <内核树> <vendor 目录>
# ============================================================================
set -euo pipefail

KERNEL_DIR="${1:?用法: wire-vendor-modules.sh <内核树> <vendor>}"
VENDOR_DIR="${2:?用法: wire-vendor-modules.sh <内核树> <vendor>}"

ROOT="$(cd "$KERNEL_DIR/.." && pwd)"   # <root>/kernel

log() { printf '[wire-vendor] %s\n' "$*"; }

[ -d "$VENDOR_DIR/oplus/kernel" ] || { echo "[x] 找不到 $VENDOR_DIR/oplus/kernel" >&2; exit 1; }

# 1) kernel/vendor —— 让内核树里所有 ../../../../../vendor/... 软链活过来
if [ ! -e "$ROOT/vendor" ]; then
    ln -sfn ../vendor "$ROOT/vendor"
    log "建立软链 $ROOT/vendor -> ../vendor"
else
    log "kernel/vendor 已存在"
fi

SOC="$KERNEL_DIR/drivers/soc/oplus"

# 2) owakelock —— drivers/soc/Makefile 里 obj-$(CONFIG_OPLUS_WAKELOCK_PROFILER) += oplus/owakelock/
if [ ! -e "$SOC/owakelock" ]; then
    ln -sfn ../../../../../vendor/oplus/kernel/wakelock_profiler "$SOC/owakelock"
    log "建立软链 drivers/soc/oplus/owakelock -> vendor wakelock_profiler"
fi

# 3) 清理旧版本追加过的 obj-y（会导致 system/ 被编译两次）
MK="$SOC/Makefile"
if grep -q 'oplus-vendor-wiring' "$MK" 2>/dev/null; then
    python3 - "$MK" <<'PY'
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
if "# oplus-vendor-wiring" in text:
    text = text.split("# oplus-vendor-wiring")[0].rstrip() + "\n"
    open(path, "w", encoding="utf-8").write(text)
    print("[wire-vendor] 已移除旧的 oplus-vendor-wiring 追加段")
PY
fi

# 4) Kconfig：让 defconfig 里的 CONFIG_OPLUS_* 有定义
KC="$SOC/Kconfig"
if ! grep -q 'oplus-vendor-wiring' "$KC" 2>/dev/null; then
    cat >> "$KC" <<'EOF'

# oplus-vendor-wiring: 让 defconfig 里的 CONFIG_OPLUS_* 真正生效
source "drivers/soc/oplus/system/Kconfig"
source "drivers/soc/oplus/owakelock/Kconfig"
EOF
    log "drivers/soc/oplus/Kconfig 追加 source"
else
    log "Kconfig 已接入过"
fi

log "完成"
