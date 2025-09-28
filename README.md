# flow-transit

该仓库提供一个脚本，用于在标准 Linux 发行版上自动化部署可供 Shadowsocks 客户端中转流量的代理服务器。脚本会安装 shadowsocks-libev、生成配置、开启 IP 转发并配置防火墙，使得来自客户端的加密流量可以通过服务器转发访问公网。

## 快速开始

1. 准备一台具备 root 权限的 Linux 服务器（Debian/Ubuntu 或 RHEL/CentOS/Fedora）。
2. 将仓库克隆到服务器上并进入目录：
   ```bash
   git clone <repo-url>
   cd flow-transit
   ```
3. 以 root 身份执行安装脚本：
   ```bash
   sudo bash scripts/setup_shadowsocks_forwarder.sh
   ```

脚本执行后会：

- 安装 shadowsocks-libev 及防火墙持久化工具。
- 创建 `shadowsocks` 系统用户并写入 `/etc/shadowsocks-libev/config.json` 配置。
- 启用并启动 systemd 服务，监听默认 8388 端口。
- 开启 IPv4 转发并放通对应的 TCP/UDP 流量。

## 自定义参数

脚本可通过环境变量定制参数：

| 变量名 | 说明 | 默认值 |
| --- | --- | --- |
| `SS_SERVER_PORT` | Shadowsocks 监听端口 | 8388 |
| `SS_PASSWORD` | 连接密码。未设置时会复用已有配置或自动生成随机密码 | 自动生成 |
| `SS_METHOD` | 加密算法 | aes-256-gcm |
| `SS_TIMEOUT` | 超时时间（秒） | 300 |
| `SS_USER` | 运行服务的系统用户 | shadowsocks |
| `SS_CONFIG_PATH` | 生成配置文件路径 | /etc/shadowsocks-libev/config.json |
| `SS_SERVICE_NAME` | systemd 服务名称 | shadowsocks-libev |

示例：

```bash
sudo SS_SERVER_PORT=443 SS_PASSWORD="very-strong-password" bash scripts/setup_shadowsocks_forwarder.sh
```

## 验证服务

1. 在服务器上查看服务状态：
   ```bash
   sudo systemctl status shadowsocks-libev
   ```
2. 客户端填入服务器公网 IP、端口、密码和加密方式后即可建立连接，所有流量将通过该服务器中转。

## 手动配置文件

`config/shadowsocks-server.json` 提供了一个最小化模板，可根据需要修改后放置到 `/etc/shadowsocks-libev/config.json`。

## 安全建议

- 请务必修改默认密码，使用高熵随机密码，并避免与他人共享。
- 建议在服务器上启用防火墙，仅放通 Shadowsocks 端口以及必须的管理端口。
- 定期更新操作系统和 shadowsocks-libev 软件包，确保获得安全补丁。
