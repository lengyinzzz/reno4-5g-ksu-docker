#!/usr/bin/env python3
"""
fix-missing-refs.py —— 修补 OPPO 开源树里"被引用但没开源"的目录/文件

背景：OPPO 开源的内核树里，net/Kconfig 与 net/Makefile 引用了 net/oplus_modules/
等内部目录，但仓库里没有这些目录，导致 `make <defconfig>` 直接失败：

    net/Kconfig:483: can't open file "net/oplus_modules/Kconfig"

本脚本做两件事（都是幂等的）：

  1. 遍历所有 Kconfig*，把 source "X" 指向不存在的文件补成空文件（并在同目录补空
     Makefile），这样 Kconfig 解析不会中断；
  2. 遍历所有 Makefile，把 `obj-y += foo/` / `obj-m += foo/` / `obj- += foo/` 里
     不存在的目录补成空目录 + 空 Makefile，这样 kbuild 进目录时不会报
     "No rule to make target"。

只补"不存在的空壳"，不改任何已有文件内容，也不删任何引用。

用法：
    fix-missing-refs.py <内核树>          # 默认 kernel/msm-4.19
"""
import os
import re
import sys

root = sys.argv[1] if len(sys.argv) > 1 else "kernel/msm-4.19"
if not os.path.isdir(root):
    print(f"[fix-missing-refs] 找不到内核树：{root}", file=sys.stderr)
    sys.exit(1)

changes = []


def rel(path):
    return os.path.relpath(path, root)


def write_empty_file(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if not os.path.exists(path):
        with open(path, "w", encoding="utf-8"):
            pass
        changes.append(f"新建空文件  {rel(path)}")


def ensure_dir_with_makefile(path):
    if not os.path.isdir(path):
        os.makedirs(path, exist_ok=True)
        changes.append(f"新建空目录  {rel(path)}/")
    mk = os.path.join(path, "Makefile")
    if not os.path.exists(mk):
        write_empty_file(mk)


# ---------------------------------------------------------------- Kconfig source
source_re = re.compile(r'^(\s*)source\s+"([^"$]+)"\s*$')

for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d != ".git"]
    for name in filenames:
        if name != "Kconfig" and not name.startswith("Kconfig."):
            continue
        kconfig = os.path.join(dirpath, name)
        try:
            with open(kconfig, encoding="utf-8", errors="replace") as f:
                lines = f.readlines()
        except OSError:
            continue
        for line in lines:
            m = source_re.match(line.rstrip("\n"))
            if not m:
                continue
            target = os.path.normpath(os.path.join(root, m.group(2)))
            if os.path.isfile(target):
                continue
            write_empty_file(target)
            # 目录型 source（X/Kconfig）顺带补 Makefile，供 obj-y += X/ 使用
            if os.path.basename(target) == "Kconfig":
                ensure_dir_with_makefile(os.path.dirname(target))

# ------------------------------------------------------------- Makefile 子目录
objdir_re = re.compile(r"^\s*obj-(?:y|m|-)\s*\+?=\s*([A-Za-z0-9_.\-]+)/\s*$")

for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d != ".git"]
    for name in filenames:
        if name != "Makefile":
            continue
        mkfile = os.path.join(dirpath, name)
        try:
            with open(mkfile, encoding="utf-8", errors="replace") as f:
                lines = f.readlines()
        except OSError:
            continue
        for line in lines:
            if "$" in line:
                continue
            m = objdir_re.match(line.rstrip("\n"))
            if not m:
                continue
            ensure_dir_with_makefile(os.path.join(dirpath, m.group(1)))

if changes:
    print(f"[fix-missing-refs] 修补 {len(changes)} 处：")
    for c in changes:
        print("  " + c)
else:
    print("[fix-missing-refs] 无需修补")
