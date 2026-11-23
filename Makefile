# 便捷入口：等价于 docs/DOCKER.md 里的命令
DOCKER ?= docker compose run --rm build

.PHONY: docker-boot docker-image docker-shell docker-build-image
.PHONY: host-image host-boot docker-verify

## Docker：编译 + 重打包 boot.img（需先放 boot/stock_boot.img）
docker-boot:
	$(DOCKER)

## Docker：只编译内核 Image
docker-image:
	TARGET=image $(DOCKER)

## Docker：进容器
docker-shell:
	docker compose run --rm build shell

## 只构建构建镜像
docker-build-image:
	docker build -t reno4-5g-ksu-build:local .

## 本机（无 Docker）：只编译
host-image:
	bash scripts/build.sh

## 本机（无 Docker）：编译 + boot.img
host-boot:
	bash scripts/docker-build.sh boot
