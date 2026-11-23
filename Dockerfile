# ============================================================================
# reno4-5g-ksu 构建镜像
#
# 只装编译内核 + 重打包 boot.img 需要的东西（clang-r399163b / GCC 4.9 由
# scripts/fetch-toolchain.sh 在运行时下载，约 1.8 G，不烤进镜像）。
#
#   docker build -t reno4-5g-ksu-build:local .
#   docker run --rm -v "$PWD:/work" reno4-5g-ksu-build:local boot
#
# 产物：out/Image 与 out/boot_Reno4_5G_KSU_<ver>.img（需要原厂 boot.img）
# ============================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    ARCH=arm64

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential bc bison flex libssl-dev libncurses-dev libelf-dev \
      cpio perl python3 kmod lz4 xz-utils zstd device-tree-compiler \
      git git-lfs curl ca-certificates unzip zip rsync file xxd \
    && rm -rf /var/lib/apt/lists/* \
    && git lfs install --skip-repo --system

WORKDIR /work

COPY docker/entrypoint.sh /usr/local/bin/ksu-build
RUN chmod 0755 /usr/local/bin/ksu-build

ENTRYPOINT ["/usr/local/bin/ksu-build"]
CMD ["boot"]
