#!/usr/bin/env bash
# ============================================================================
# 容器入口：把参数交给 scripts/docker-build.sh
#
#   docker run --rm -v "$PWD:/work" reno4-5g-ksu-build:local boot
#   docker run --rm -it -v "$PWD:/work" reno4-5g-ksu-build:local shell
# ============================================================================
set -euo pipefail

ROOT="${REPO_ROOT:-/work}"

case "${1:-boot}" in
    shell|bash)
        shift || true
        if [ "$#" -gt 0 ]; then exec /bin/bash "$@"; fi
        exec /bin/bash
        ;;
esac

if [ ! -d "$ROOT/scripts" ]; then
    printf '[x] %s 里没有 scripts/ —— 挂载仓库目录了吗？\n' "$ROOT" >&2
    exit 1
fi

cd "$ROOT"
exec bash "$ROOT/scripts/docker-build.sh" "$@"
