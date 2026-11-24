# OPPO Reno4 5G (PDPM00 / SM7250 "lito") — 4.19.157 kernel with KernelSU

面向 **OPPO Reno4 5G (PDPM00, Qualcomm SM7250 / lito)** 的内核源码发行版：基于 OPPO 官方
开源内核树，集成 [KernelSU](https://github.com/tiann/KernelSU)，并在 **SELinux enforcing**
状态下提供可用的 root。

本仓库是**设备专用发行版**（device-specific），不面向上游仓库合并。

## 特性

| 项目 | 说明 |
|---|---|
| 内核 | 4.19.157-perf（`4.19.157-perf+ ... clang 11.0.5`） |
| 平台 | Qualcomm SM7250 / lito（OPPO 内部名 Simba / Reno4 5G） |
| root | KernelSU，仅集成其 `kernel/` 目录（GPL-2.0-only），版本见下 |
| SELinux | **Enforcing** 下 root 可用；实现了完整的 4.19 非 GKI 策略注入，注入失败时才回退 permissive |
| 配置 | 原厂提取配置 + 必要开关（KSU/KPROBES），关闭 `CONFIG_MODULE_SIG`，禁用 `CONFIG_ARCH_LAGOON` |
| 工具链 | AOSP clang-r399163b (clang 11.0.5) + GCC 4.9 (aarch64/arm32) |

## 实测结果

| 检查项 | 结果 |
|---|---|
| `getenforce` | Enforcing |
| root shell 域 | `u:r:ksu:s0` |
| root 授权 | Manager `debug su` 成功，uid 0 |
| KernelSU 功能 | Feature 查询 / Module List / adb_root 安装均正常 |
| ksu 相关 AVC 拒绝 | 0 条 |

## 版本匹配（重要）

KernelSU 的版本号算法是 `KSU_VERSION = 30000 + git rev-list --count HEAD`，因此本仓库把
KernelSU 固定在一个确定的提交上，并用补丁方式引入改动：

- KernelSU 基线提交：`62e88ca9`（`rev-list --count` = 2584 → `KSU_VERSION = 32584`）
- 配套 Manager：`KernelSU_v3.2.5-59-g62e88ca9_32584`

> 若把 KernelSU 换成别的提交、或把它当普通目录拷进内核树（丢失 `.git`），版本号会变化并被
> Manager 拒绝（`manager too low` / `kernel too low`）。详见 `scripts/prepare-kernelsu.sh`。

## 仓库内容

```
patches/kernel/    内核改动补丁 + 新增文件（4.19 兼容回移、KernelSU 集成、defconfig）
patches/vendor/    vendor 树（devicetree / OPLUS 驱动）改动补丁
patches/kernelsu/  KernelSU 的 4.19 适配补丁（固定基线 62e88ca9）
scripts/           clone 官方树、下载工具链、构建、打包、提取 ksud
release/           AnyKernel3 的设备相关配置（anykernel.sh）与其 LICENSE
docs/              构建 / 刷机 / SELinux 4.19 实现说明 / 变更记录
base/              上游 base commit 与补丁应用顺序
Dockerfile         Docker 构建镜像（本地 / CI 通用）
docker-compose.yml 本地 compose 入口（build / image / shell）
docker/            容器 entrypoint
boot/              放原厂 boot.img 的位置（不入库）与说明
.github/workflows  build-boot.yml（编译+出 boot.img）、docker-image.yml（验证镜像）
tools/             运行时下载的 magiskboot（不入库）
```

本仓库**只包含补丁、脚本与文档**：官方内核树与 vendor 树（约 1.5 G）由 `scripts/prepare-tree.sh`
从 OPPO 官方仓库拉取后打补丁；1.8 G 的工具链由 `scripts/fetch-toolchain.sh` 下载（均不入库）。

## 快速开始

```bash
# 1) 拉取官方内核+vendor 树并打补丁
scripts/prepare-tree.sh

# 2) 下载工具链（clang + GCC 4.9，约 1.8 G）
scripts/fetch-toolchain.sh

# 3) 拉取 KernelSU 并应用 4.19 补丁
scripts/prepare-kernelsu.sh

# 4) 编译
scripts/build.sh

# 5) 用你自己设备的原厂 boot.img 重打包
scripts/repack_bootimg.sh <你的原厂boot.img> kernel/msm-4.19/out/arch/arm64/boot/Image new-boot.img

# 6) 或者打一个 AnyKernel3 刷机包（适合在 recovery 里刷）
scripts/make-ak3-zip.sh kernel/msm-4.19/out/arch/arm64/boot/Image v1.0.0
```

构建环境、依赖包与常见问题见 [`docs/BUILD.md`](docs/BUILD.md)；刷入与回退见 [`docs/FLASH.md`](docs/FLASH.md)。

## 构建变体（Actions 里选 variant）

同一个内核源码，Actions 可以按需产出四种 `boot.img`：

| variant | 产物文件名 | 内核内容 | 用途 |
|---|---|---|---|
| `enforcing` | `boot_Reno4_5G_KSU_<ver>_enforcing.img` | 4.19 + KernelSU，SELinux 严格 | 原厂 ColorOS 上首选 |
| `permissive` | `boot_Reno4_5G_KSU_<ver>_permissive.img` | 同上，编入 `KSU_FORCE_PERMISSIVE` | 策略注入失败时备用 |
| `noksu` | `boot_Reno4_5G_Magisk_<ver>.img` | 纯内核，`CONFIG_KSU` 关闭 | 用 Magisk 拿 root |
| `docker` | `boot_Reno4_5G_Magisk_Docker_<ver>.img` | 纯内核 + 容器所需选项 | Magisk + Docker 同时用 |

`docker` 变体在 `stock_lito_defconfig` 基础上只额外打开这四项：

```
CONFIG_SYSVIPC / CONFIG_PID_NS / CONFIG_IPC_NS / CONFIG_CGROUP_DEVICE
```

（`NAMESPACES`、`CGROUPS`、`MEMCG`、`OVERLAY_FS`、`VETH`、`BRIDGE`、`NETFILTER`、
`IP_NF_NAT`、`IP_NF_TARGET_MASQUERADE`、`SECCOMP` 原厂 defconfig 里已经是 y，
overlay2 / bridge / veth / NAT 直接可用。）

**故意不开启**：`USER_NS`、`BRIDGE_NETFILTER`、`VXLAN`、`MACVLAN`、`IPVLAN`、
`BRIDGE_VLAN_FILTERING`、`NETFILTER_XT_MATCH_ADDRTYPE`、`DM_THIN_PROVISIONING`。
前几项会改变 Android netd / netfilter 的行为，实测在 GSI 上会导致**直接没网**，
而它们对单机跑 Docker 不是必需；devicemapper 存储驱动用 overlay2 代替即可。

### 非 GKI 内核 + KernelSU 的已知限制

本内核是 **4.19 非 GKI**。官方 KernelSU Manager（1.x 之后）只支持 GKI，在非 GKI 内核上会
显示「只支持 GKI」，需要作者配套的 `32584` 版 Manager 才能用。

在 GSI（例如 TrebleDroid A13，指纹 `google/cheetah`）上，KSU 依赖的 init `second_stage`
钩子不一定会触发，实测常表现为 Manager 读不到 KSU 版本。这种情况下直接用 `noksu` 或
`docker` 变体 + Magisk 更省事。

### 用 Magisk 修补（noksu / docker 变体）

1. 下载对应 `boot_*.img` 到手机
2. Magisk → 安装 → **选择并修补一个文件** → 选该 img
3. 生成的 `magisk_patched-*.img` 用 `fastboot flash boot` 刷入
4. 验证：`adb shell su -c id` → `uid=0(root)`

### 手机上的 Docker

`docker` 变体只解决内核侧：namespace、cgroup、overlayfs、bridge、nat 都已可用。
userspace 侧还需要：

- 先用 Magisk 拿到 root
- 准备一份能跑的 dockerd / runc（chroot 或 Termux 方案）
- Android 用 cgroup v1，需要手动挂载（`/sys/fs/cgroup/{memory,cpu,cpuset,...}`）
- 建议 `dockerd --iptables=false` 或先确认 `iptables` 可用

自查内核侧是否就绪：

```bash
adb shell ls /proc/self/ns/        # 应包含 cgroup ipc mnt net pid user uts
adb shell "cat /proc/cgroups"      # 看 memory / devices / pids 是否 enabled
```

## 云端编译：GitHub Actions / Docker（只出 boot.img）

不想在本机装 4 GB 环境，就让 Actions 编。产物只有 `boot.img`，不打 AnyKernel3 zip。

```bash
# 1) 原厂 boot.img 放到 boot/stock_boot.img（或上传成本仓库 Release 的 asset：stock_boot.img）
# 2) Actions → build-boot → Run workflow
# 3) 下载 Artifact boot-img-<版本> → boot_Reno4_5G_KSU_<版本>.img
```

本地 Docker 同样一套流程：

```bash
docker compose run --rm build                  # 编译 + 重打包 → out/boot_Reno4_5G_KSU_<日期>.img
TARGET=image docker compose run --rm build     # 只编译 → out/Image
docker compose run --rm build shell            # 进容器排查
```

- 工作流：[`.github/workflows/build-boot.yml`](.github/workflows/build-boot.yml)
- 用法与 Secrets 说明：[`docs/DOCKER.md`](docs/DOCKER.md)
- 原厂 boot.img 从哪来：[`boot/README.md`](boot/README.md)

## 许可

- 内核与 vendor 树的改动落在 GPL-2.0-only 文件上，按 **GPL-2.0-only** 发布
- 本仓库新增的脚本与文档：**GPL-2.0-only**
- 第三方组件（KernelSU、AnyKernel3、工具链等）的许可与来源见 [`NOTICE.md`](NOTICE.md)

## 免责声明

本项目为**非官方**社区作品，与 OPPO、Qualcomm、KernelSU 官方均无隶属或背书关系。
解锁 bootloader 会清空数据并可能失去保修；刷写 boot 分区有变砖风险；root/KernelSU 会降低
设备安全模型（本内核还关闭了模块签名校验）。**请在自有设备上自行承担风险使用。**
