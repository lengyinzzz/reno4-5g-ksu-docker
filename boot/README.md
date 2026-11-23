# boot/ —— 原厂 boot.img 放这里（不入库）

重打包只会替换内核，ramdisk / dtb / header 全部来自**你自己设备的原厂 boot.img**。
本仓库不附带、也不分发任何原厂文件。

## 拿到原厂 boot.img

任选一种：

- 从与当前系统版本一致的官方固件包（`.ozip` / `.zip`）里提取 `boot.img`
- 已 root 的设备上导出：

  ```bash
  adb shell su -c 'dd if=/dev/block/by-name/boot of=/sdcard/boot.img'
  adb pull /sdcard/boot.img
  ```

## 三种喂给构建的方式

| 方式 | 用法 | 适合 |
|---|---|---|
| 本地文件 | 把文件放到 `boot/stock_boot.img` | 本地 `docker compose run --rm build` |
| Release asset | 上传到本仓库 Release，文件名 `stock_boot.img` | GitHub Actions（不污染 git 历史，大小不限） |
| Secrets | `STOCK_BOOT_URL`（可配 `STOCK_BOOT_AUTH_HEADER`）或 `KSU_STOCK_BOOT_B64` | 私有下载源 / 内网 |

`*.img` 已被 `.gitignore` 忽略，`boot/stock_boot.img` 不会被误提交。

## 校验

```bash
python3 -c 'import sys;print(open(sys.argv[1],"rb").read(8))' boot/stock_boot.img
# 期望：b'ANDROID!'
sha256sum boot/stock_boot.img
```

把 SHA256 记下来，和最终 `boot_Reno4_5G_KSU_*.img` 的来源一起留档。
