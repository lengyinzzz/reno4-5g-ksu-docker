#!/usr/bin/env python3
"""
link-oplus-headers.py —— 把 vendor/oplus 的私有头文件软链进内核 include/soc/oplus

背景：OPPO 开源的内核树里，大量核心文件用

    #include <soc/oplus/system/oppo_project.h>
    #include <soc/oplus/oplus_wakelock_profiler.h>

但内核树里没有 include/soc/oplus/ 这些头（OPPO 把实现放在 vendor/oplus/kernel/ 下，
原厂构建系统在 OplusKernelEnvConfig.mk 里现建软链，且它假设 vendor 在 kernel/vendor）。
开源树缺这层布局，编译时就会 #include 失败。

本脚本：扫描内核树里所有 <soc/oplus/...> 引用，在 vendor/ 下按文件名找到对应头，
在 kernel/include/<引用路径> 建软链。幂等，找不到的会列出来。

用法：
    link-oplus-headers.py <内核树> <vendor 目录>
"""
import os
import re
import sys

kernel = sys.argv[1] if len(sys.argv) > 1 else "kernel/msm-4.19"
vendor = sys.argv[2] if len(sys.argv) > 2 else "vendor"

if not os.path.isdir(kernel) or not os.path.isdir(vendor):
    print(f"[link-oplus] 缺目录：kernel={kernel} vendor={vendor}", file=sys.stderr)
    sys.exit(1)

inc_re = re.compile(r'#\s*include\s*[<"](soc/oplus/[^">\s]+)[">]')

refs = set()
for dirpath, dirnames, filenames in os.walk(kernel):
    dirnames[:] = [d for d in dirnames if d not in (".git",)]
    for name in filenames:
        if not name.endswith((".c", ".h")):
            continue
        path = os.path.join(dirpath, name)
        # 跳过落在 vendor 软链里的内容
        if "/vendor/" in path:
            continue
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                text = f.read()
        except OSError:
            continue
        refs.update(inc_re.findall(text))

# vendor 头文件索引
index = {}
for dirpath, dirnames, filenames in os.walk(vendor):
    dirnames[:] = [d for d in dirnames if d != ".git"]
    for name in filenames:
        if name.endswith(".h"):
            index.setdefault(name, []).append(os.path.join(dirpath, name))

def has_symlink_ancestor(path, base):
    """dest 的某个祖先目录是软链（如 include/soc/oplus/system -> vendor）时，
    不应再往里写文件，交给软链本身解析。"""
    cur = os.path.dirname(path)
    base = os.path.abspath(base)
    while os.path.abspath(cur) != base and len(cur) > len(base):
        if os.path.islink(cur):
            return True
        cur = os.path.dirname(cur)
    return False


linked, missing, skipped = [], [], []

for ref in sorted(refs):
    dest = os.path.join(kernel, "include", ref)
    if os.path.exists(dest):
        continue
    if has_symlink_ancestor(dest, os.path.join(kernel, "include")):
        skipped.append(ref)
        continue
    base = os.path.basename(ref)
    cands = index.get(base, [])
    if not cands:
        missing.append(ref)
        continue

    # 优先 vendor/oplus/kernel/system/include/<file>（对应 soc/oplus/system/*）
    preferred = os.path.join(vendor, "oplus", "kernel", "system", "include", base)
    pick = preferred if os.path.isfile(preferred) else cands[0]
    if len(cands) > 1 and os.path.isfile(preferred):
        pick = preferred

    os.makedirs(os.path.dirname(dest), exist_ok=True)
    rel = os.path.relpath(pick, os.path.dirname(dest))
    if os.path.islink(dest) or os.path.exists(dest):
        os.unlink(dest)
    os.symlink(rel, dest)
    linked.append(f"{ref} -> {pick}")

print(f"[link-oplus] 引用 {len(refs)} 个头，已软链 {len(linked)} 个，由目录软链覆盖 {len(skipped)} 个")
for item in linked:
    print("  " + item)
if missing:
    print(f"[link-oplus] 在 vendor/ 里找不到（{len(missing)} 个）：")
    for item in missing:
        print("  " + item)
