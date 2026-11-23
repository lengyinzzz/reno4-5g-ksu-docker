# Docker 与 GitHub Actions

两种云端/容器化构建方式，流程完全一致：
`prepare-tree → fetch-toolchain → prepare-kernelsu → build → repack boot.img`

**产物只有 `boot.img`**（不出 AnyKernel3 zip）。

---

## 1. GitHub Actions（推荐，不用本机环境）

`.github/workflows/build-boot.yml`

| 触发 | 说明 |
|---|---|
| 手动 `workflow_dispatch` | Actions → **build-boot** → Run workflow |
| 打 tag `v*` | push `v1.0.0` 之类的 tag 时自动构建 |

可填参数：

- `version`：产物版本号，留空 = `日期-短SHA`
- `upload_release`：勾上则构建完发布到 Release
- `release_tag`：Release 的 tag，留空用版本号

产物：Artifact **`boot-img-<版本>`**，里面是
`boot_Reno4_5G_KSU_<版本>.img` + `SHA256SUMS`。

### 原厂 boot.img 怎么给

见 [`boot/README.md`](../boot/README.md)。最省事：**把原厂 boot.img 上传成本仓库 Release 的 asset，文件名 `stock_boot.img`**，
workflow 会自动下载（用内置 `GITHUB_TOKEN`，私有仓库也行）。

也支持 Secrets：

| Secret | 用途 |
|---|---|
| `STOCK_BOOT_URL` | boot.img（或含 boot.img 的 zip）直链 |
| `STOCK_BOOT_AUTH_HEADER` | 直链需要的请求头，形如 `Authorization: Bearer xxx` |
| `STOCK_BOOT_IMG_B64` | base64 的 boot.img（Secret 单值上限 48 KB，只适合极小镜像） |

没有原厂 boot.img 时 workflow 会失败并给出提示，只留 `Image` 在日志里。

### 免费额度与耗时参考

公开仓库的 Actions 不消耗分钟数。整条流水线约 40–70 分钟，主要花在：
官方树 clone（~1.5 G）→ 工具链（~1.8 G，已缓存）→ 内核编译（`JOBS=3`）。

---

## 2. 本地 Docker

```bash
# 构建镜像（只装依赖，工具链运行时下载）
docker build -t reno4-5g-ksu-build:local .

# 编译 + 出 boot.img（先把 boot/stock_boot.img 放好）
docker compose run --rm build

# 只编译内核
TARGET=image docker compose run --rm build

# 进容器排查
docker compose run --rm build shell
```

直接用 `docker run` 也行：

```bash
docker run --rm -v "$PWD:/work" reno4-5g-ksu-build:local boot
docker run --rm -v "$PWD:/work" reno4-5g-ksu-build:local image
```

缓存说明：官方树、vendor、工具链、`out/` 都在仓库目录里（挂载进容器），
第二次构建直接复用，不会重新下载。

> 容器以 root 运行，产出的 `out/`、`toolchain/` 属主是 root；本机不便时可
> `sudo chown -R "$USER" out toolchain kernel vendor .modules-src tools`。

---

## 3. 不用 Docker / Actions 的纯本机流程

见 [`BUILD.md`](BUILD.md)：`scripts/prepare-tree.sh` → `fetch-toolchain.sh` →
`prepare-kernelsu.sh` → `build.sh` → `repack_bootimg.sh`。

---

## 4. 产物与校验

```
out/
├── Image                            # 编译出的内核
├── boot_Reno4_5G_KSU_<ver>.img      # 重打包好的 boot.img（唯一要刷的文件）
└── SHA256SUMS
```

```bash
sha256sum out/boot_Reno4_5G_KSU_*.img
# 上传/下载后对比 SHA256SUMS
```

刷入与回退见 [`FLASH.md`](FLASH.md)。刷前务必确认：机型 `PDPM00`、系统版本与
原厂 boot.img 同源、bootloader 已解锁。
