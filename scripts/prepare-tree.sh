#!/usr/bin/env bash
# ============================================================================
# prepare-tree.sh —— 拉取 OPPO 官方源码树并打上本项目的补丁
#
# 产出目录结构（与 OPPO 构建系统的期望一致）：
#   kernel/msm-4.19/   官方内核 + techpack/{camera,display,video} + 本项目内核补丁
#   vendor/            官方 modules 仓库的 vendor/ + 本项目 vendor 补丁
#
# 用法：
#   scripts/prepare-tree.sh            # 首次执行 / 已就绪则跳过
#   scripts/prepare-tree.sh --force    # 删除已拉取的树后重新来一遍
#
# 说明：官方内核与 vendor 树合计约 1.5 G，均不入库；补丁见 patches/。
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KERNEL_REPO="${KERNEL_REPO:-https://github.com/oppo-source/android_kernel_oppo_sm7250.git}"
MODULES_REPO="${MODULES_REPO:-https://github.com/oppo-source/android_kernel_modules_and_devicetree_oppo_sm7250.git}"
BRANCH="${BRANCH:-oppo/sm7250_s_12.1_reno4_5g}"
KERNEL_DIR="$ROOT/kernel/msm-4.19"
MODULES_SRC="$ROOT/.modules-src"

log()  { printf '\033[1;34m>>>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# apply_patch <工作目录> <补丁> [<相对仓库根的目录前缀>]
#
# 说明：若 <工作目录> 本身不是 git 仓库根，而它又位于某个 git 仓库内部，
# `git apply` 会把补丁路径解析为"仓库根相对"，从而把 <工作目录> 之外的文件
# 全部忽略（表现为"什么都不做却退出 0"）。因此对 vendor 这种"子目录 + 无独立
# .git"的情况，必须用 `git -C <repo> apply --directory=<prefix>` 显式指定前缀。
apply_patch() {
    local dir="$1" patch="$2" prefix="${3:-}"
    [ -f "$patch" ] || { warn "补丁不存在：$patch"; return 0; }

    git_apply() {   # 传 --check / --check --reverse / 空
        if [ -n "$prefix" ]; then
            git -C "$ROOT" apply --directory="$prefix" "$@" "$patch"
        else
            ( cd "$dir" && git apply "$@" "$patch" )
        fi
    }
    patch_tool() {  # 传 --dry-run 或 空
        ( cd "$dir" && patch -p1 -s -i "$patch" "$@" )
    }

    if git_apply --check --reverse >/dev/null 2>&1; then
        log "补丁已应用过，跳过：$(basename "$patch")"
        return 0
    fi
    if git_apply --check >/dev/null 2>&1; then
        git_apply && log "已应用 $(basename "$patch")"
        return 0
    fi
    if patch_tool --dry-run >/dev/null 2>&1; then
        patch_tool && log "已应用（patch）$(basename "$patch")"
        return 0
    fi
    warn "补丁无法应用：$(basename "$patch")"
    return 1
}

# require_marker <文件> <grep 模式> <说明>
# 补丁"应用成功"之后的内容校验：防止上面提到的 no-op 情况静默通过。
require_marker() {
    if grep -q "$2" "$1" 2>/dev/null; then
        log "校验通过：$3"
    else
        die "校验失败：$3（$1 中找不到 $2）"
    fi
}

if [ "${1:-}" = "--force" ]; then
    log "--force：删除已拉取的源码树"
    rm -rf "$KERNEL_DIR" "$ROOT/vendor" "$MODULES_SRC"
fi

# 1) 官方内核
if [ -d "$KERNEL_DIR/.git" ]; then
    log "内核树已存在，跳过 clone：kernel/msm-4.19"
else
    log "clone 官方内核（$BRANCH，浅克隆）..."
    mkdir -p "$ROOT/kernel"
    git clone --depth 1 -b "$BRANCH" "$KERNEL_REPO" "$KERNEL_DIR"
fi

# 2) modules + devicetree 仓库
if [ -d "$MODULES_SRC/.git" ]; then
    log "modules 仓库已存在，跳过 clone：.modules-src"
else
    log "clone modules/devicetree 仓库（$BRANCH，浅克隆）..."
    git clone --depth 1 -b "$BRANCH" "$MODULES_REPO" "$MODULES_SRC"
fi

# 3) 并入 techpack/{camera,display,video}
for d in camera display video; do
    src="$MODULES_SRC/kernel/msm-4.19/techpack/$d"
    dst="$KERNEL_DIR/techpack/$d"
    if [ -d "$src" ] && [ ! -d "$dst" ]; then
        log "并入 techpack/$d"
        mkdir -p "$KERNEL_DIR/techpack"
        cp -a "$src" "$dst"
    fi
done

# 3.5) 补全 S 分支没有开源的 net/oplus_modules（同仓库 T.13 分支里有，内核同为 4.19.157）
OPLUS_MODULES_BRANCH="${OPLUS_MODULES_BRANCH:-oppo/sm7250_t_13.0.0_reno5_5g}"
if [ ! -f "$KERNEL_DIR/net/oplus_modules/Kconfig" ]; then
    log "补全 net/oplus_modules（来源：$OPLUS_MODULES_BRANCH）"
    git -C "$KERNEL_DIR" fetch --depth 1 origin "$OPLUS_MODULES_BRANCH" \
        || die "fetch $OPLUS_MODULES_BRANCH 失败"
    # 只检出这一个目录；reset 让它们回到未跟踪状态，不干扰后续 git apply
    git -C "$KERNEL_DIR" checkout FETCH_HEAD -- net/oplus_modules \
        || die "检出 net/oplus_modules 失败"
    git -C "$KERNEL_DIR" reset -q -- net/oplus_modules 2>/dev/null || true
    log "已补全 net/oplus_modules（$(ls "$KERNEL_DIR/net/oplus_modules" | wc -l) 个条目）"
else
    log "net/oplus_modules 已存在，跳过"
fi

# 4) .gitignore 调整（让 techpack 子目录被跟踪）
apply_patch "$KERNEL_DIR" "$ROOT/patches/kernel/0000-techpack-gitignore.patch" \
    || die "techpack .gitignore 补丁应用失败"
require_marker "$KERNEL_DIR/.gitignore" 'techpack/\*' "techpack 子目录已取消忽略"

# 5) vendor 树（拷出子目录，不带 .git）
if [ -d "$ROOT/vendor/qcom" ]; then
    log "vendor 已存在，跳过复制：vendor/"
else
    log "复制 vendor/（来自 modules 仓库）"
    mkdir -p "$ROOT/vendor"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --exclude '.git' "$MODULES_SRC/vendor/" "$ROOT/vendor/"
    else
        cp -a "$MODULES_SRC/vendor/." "$ROOT/vendor/"
        rm -rf "$ROOT/vendor/.git"
    fi
fi

# 5.5) devicetree: 项目目录的 camera/ 补到 qcom/ 下
#      （qcom/lito.dtsi 里 #include "camera/lito-camera.dtsi"，而 camera 只在
#       项目目录 19065/ 里，OPPO 原厂构建会把它并进 qcom/）
DT_DIR="$ROOT/vendor/qcom/proprietary/devicetree-4.19"
if [ -d "$DT_DIR/19065/camera" ] && [ ! -e "$DT_DIR/qcom/camera" ]; then
    ln -sfn ../19065/camera "$DT_DIR/qcom/camera"
    log "补链 devicetree qcom/camera -> ../19065/camera"
fi
for sub in display; do
    if [ -d "$DT_DIR/19065/$sub" ] && [ ! -e "$DT_DIR/qcom/$sub" ]; then
        ln -sfn "../19065/$sub" "$DT_DIR/qcom/$sub"
        log "补链 devicetree qcom/$sub -> ../19065/$sub"
    fi
done

# 6) 本项目补丁
apply_patch "$KERNEL_DIR" "$ROOT/patches/kernel/0001-reno4-5g-kernel-4.19-kernelsu.patch" \
    || die "内核补丁应用失败"
require_marker "$KERNEL_DIR/fs/namespace.c" 'int path_mount(' "内核 4.19 回移（fs/namespace.c 的 path_mount）"
apply_patch "$ROOT/vendor" "$ROOT/patches/vendor/0001-lito-devicetree-and-oplus-fixes.patch" "vendor" \
    || die "vendor 补丁应用失败"
require_marker "$ROOT/vendor/qcom/proprietary/devicetree-4.19/19065/Makefile" 'CONFIG_ARCH_KONA' "vendor devicetree Makefile 改动"

# 6.5) 接入 vendor/oplus 模块（软链 + Makefile/Kconfig）
log "接入 vendor/oplus 模块"
bash "$ROOT/scripts/wire-vendor-modules.sh" "$KERNEL_DIR" "$ROOT/vendor" \
    || die "wire-vendor-modules.sh 执行失败"

# 7) 修补被引用但没开源的目录（net/oplus_modules 等）
log "补软链 vendor 私有头文件（soc/oplus/*）"
python3 "$ROOT/scripts/link-oplus-headers.py" "$KERNEL_DIR" "$ROOT/vendor" || true

log "修补缺失的 Kconfig source / Makefile 子目录"
python3 "$ROOT/scripts/fix-missing-refs.py" "$KERNEL_DIR" || die "fix-missing-refs.py 执行失败"

# 8) 补丁新增的文件（defconfig 与头文件）
if [ -d "$ROOT/patches/kernel/new-files" ]; then
    log "拷入补丁新增文件（stock_lito_defconfig 等）"
    cp -a "$ROOT/patches/kernel/new-files/." "$KERNEL_DIR/"
fi

log "完成。"
echo
echo "  内核树 : $KERNEL_DIR   ($(git -C "$KERNEL_DIR" rev-parse --short HEAD 2>/dev/null || echo '?'))"
echo "  vendor : $ROOT/vendor"
echo "  下一步 : scripts/fetch-toolchain.sh 与 scripts/prepare-kernelsu.sh"
