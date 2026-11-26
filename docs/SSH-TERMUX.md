# Termux SSH 连接说明（OPPO Reno4 5G）

用于从电脑 SSH 登录手机里的 Termux，方便操作 chroot / docker 等长命令。

---

## 1. 手机端准备（只需一次）

```bash
pkg install -y openssh
```

**设置登录密码**（用户名固定是 `whoami` 输出的那个，通常是 `u0_aXXX`）：

```bash
passwd
```

> 如果之前跑过 `/sdcard/Download/DSH-Go/setup-ssh.sh`，脚本会自动设一个 8 位随机密码并打印在终端上。忘了就用 `passwd` 重设。

**启动 sshd**（端口固定 **8022**，不是 22）：

```bash
sshd
```

**查看连接信息**：

```bash
whoami
pkg install -y net-tools
ifconfig | grep 'inet ' | grep -v 127.0.0.1
```

典型输出：

```
u0_a461                        ← 用户名
192.168.1.9                    ← 手机局域网 IP（会变）
```

---

## 2. 电脑连接

```bash
ssh -p 8022 u0_a461@192.168.1.9
```

| 项 | 值 |
|---|---|
| 端口 | `8022` |
| 用户名 | Termux 的 `whoami`（示例 `u0_a461`） |
| 密码 | `passwd` 设置的那个 |
| IP | 手机局域网 IP，需与电脑同一 Wi-Fi |

---

## 3. 没有局域网 IP 时：adb 端口转发（推荐）

手机用 USB 连电脑，然后：

```bash
adb forward tcp:8022 tcp:8022
ssh -p 8022 u0_a461@127.0.0.1
```

不依赖 Wi-Fi，也不关心 IP 变不变。

---

## 4. 配公钥免密（可选，强烈建议）

**电脑上生成密钥**（已有就跳过）：

```bash
ssh-keygen -t ed25519 -C "pc-to-termux"
```

**把公钥推到手机**：

```bash
adb push ~/.ssh/id_ed25519.pub /sdcard/
```

**手机 Termux 里安装公钥**：

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
cat /sdcard/id_ed25519.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

之后直接 `ssh -p 8022 u0_a461@IP` 免密登录。

---

## 5. 常用操作

```bash
# 进 chroot 的 Ubuntu
su -c 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; chroot /data/local/ubuntu /bin/bash'

# 起 dockerd（若内核支持）
su -c "chroot /data/local/ubuntu /usr/bin/env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin TMPDIR=/tmp /bin/bash -c 'dockerd --iptables=false --storage-driver=vfs --data-root=/var/lib/docker > /tmp/dockerd.log 2>&1 & sleep 10; tail -5 /tmp/dockerd.log'"

# 一键装 docker / 测容器（脚本在 /sdcard/Download/DSH-Go/）
bash /sdcard/Download/DSH-Go/docker-setup.sh
bash /sdcard/Download/DSH-Go/docker-final.sh
```

---

## 6. 常见问题

| 现象 | 原因 / 解决 |
|---|---|
| `Connection refused` | sshd 没运行（Android 重启或 Termux 被关后都会停）→ Termux 里再跑 `sshd` |
| `Permission denied` | 密码错、或用的是别的用户名；确认 `whoami` |
| 连不上但端口通 | 手机和电脑不在同一网段；改用 adb forward |
| 登录后命令找不到 | Termux 环境变量问题，`export PATH=$PREFIX/bin:$PATH` |
| 想开机自启 sshd | `pkg install -y termux-services && sv-enable sshd` |
| 会话断开后进程被杀 | 用 `tmux`：`pkg install -y tmux` → `tmux new -s work` |

---

## 7. 安全提示

- 端口 8022 只在 Termux 前台运行时开放，不要暴露到公网
- 建议只配公钥登录，并把 `passwd` 设的密码留作备用
- 使用完可 `pkill sshd` 关闭
