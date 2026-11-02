# Let's Encrypt + dns.he.net 域名证书自动续约工具

基于 Bash 与 Certbot 实现的 Let's Encrypt SSL/TLS 证书全自动检测与续约工具。专为使用 [dns.he.net](https://dns.he.net) DNS 解析服务的用户设计，利用 DNS-01 验证方式自动更新 TXT 记录，支持单域名及泛域名（Wildcard）证书续约，并自动重载 Web 服务器。

---

## 🌟 功能特性

* **一键交互式部署**：首次运行自动引导输入域名、HE DDNS Key 和邮箱，并自动配置环境。
* **依赖自动补齐**：自动检测系统并补齐缺失的依赖库（`curl`、`openssl`、`certbot`、`cron`）。
* **智能天数检测**：每天自动检查证书剩余有效期，仅在剩余天数少于 7 天时才触发续约，避免频繁请求 API。
* **HE DDNS TXT 自动验证**：通过 Certbot `--manual-auth-hook` 自动向 `dns.he.net` 发起 POST 请求配置 `_acme-challenge` TXT 验证记录。
* **定时自动运行**：一键添加 Crontab 调度任务（默认每天 03:00 执行）。
* **无缝服务重载**：证书续约成功后，自动检测并重载 Nginx 或 Apache 引擎使新证书生效。

---

## 🛠️ 环境要求

* **操作系统**：Linux (Ubuntu / Debian / CentOS / RHEL / Rocky Linux 等)
* **权限**：需要 `root` 权限
* **DNS 托管**：域名解析服务托管在 [dns.he.net](https://dns.he.net)

---

## 🚀 快速开始

### 1. 准备 HE.net DDNS Key

1. 登录 [dns.he.net](https://dns.he.net)，进入域名的解析管理页面。
2. 添加一条主机名为 `_acme-challenge` 的 **TXT** 记录（记录值可暂填任意字符）。
3. 勾选 **Enable Dynamic DNS** 开关并保存。
4. 点击该 TXT 记录右侧的刷新图标（DDNS 图标），生成并复制 **DDNS Key（密钥）**。

### 2. 下载并运行部署脚本

在服务器终端点击右上角**一键复制**下方任意一条单行命令并运行：

**方式一：使用 wget 一键下载并运行（推荐）**
```bash
wget -O deploy_cert_auto.sh [https://raw.githubusercontent.com/GogogogoDAI/letsencrypt/refs/heads/main/deploy_cert_auto.sh](https://raw.githubusercontent.com/GogogogoDAI/letsencrypt/refs/heads/main/deploy_cert_auto.sh) && chmod +x deploy_cert_auto.sh && bash deploy_cert_auto.sh
```

**方式二：使用 curl 一键下载并运行**
```bash
curl -sSL -o deploy_cert_auto.sh [https://raw.githubusercontent.com/GogogogoDAI/letsencrypt/refs/heads/main/deploy_cert_auto.sh](https://raw.githubusercontent.com/GogogogoDAI/letsencrypt/refs/heads/main/deploy_cert_auto.sh) && chmod +x deploy_cert_auto.sh && bash deploy_cert_auto.sh
```

### 3. 根据提示输入参数

脚本首次运行会提示输入以下配置：
* **目标域名**：例如 `example.com`（将自动同时申请 `example.com` 和 `*.example.com`）
* **HE DDNS Key**：步骤 1 中获取的密钥
* **联系邮箱**：用于注册 Certbot 账号及接收过期警告

---

## 📂 常用文件路径与配置

| 名称 | 路径 | 说明 |
| :--- | :--- | :--- |
| **一键部署脚本** | `/root/deploy_cert_auto.sh` | 负责依赖安装、脚本写入及 Cron 配置 |
| **主续约脚本** | `/usr/local/bin/auto_renew_he_cert.sh` | 包含证书检测与 HE DDNS Hook 的核心逻辑 |
| **运行日志** | `/var/log/cert_renew.log` | 记录每天的检测状态及续约输出 |
| **证书存放路径** | `/etc/letsencrypt/live/<YOUR_DOMAIN>/` | Certbot 生成的 SSL 证书存放目录 |

---

## 🔄 手动运行与测试

如需测试脚本运行状态或手动触发检测，可直接执行主控制脚本：

```bash
/usr/local/bin/auto_renew_he_cert.sh
```

查看实时日志输出：

```bash
tail -n 50 /var/log/cert_renew.log
```

查看 Crontab 定时任务状态：

```bash
crontab -l
```

---

## ❓ 常见问题排查 (FAQ)

1. **报错 `badauth`**：
   * **原因**：HE DDNS Key 填写错误或记录匹配失败。
   * **解决**：检查 `/usr/local/bin/auto_renew_he_cert.sh` 中的 `DDNS_KEY` 变量是否与 dns.he.net 上的 Key 一致。

2. **报错 `nohost`**：
   * **原因**：dns.he.net 上未创建 `_acme-challenge.example.com` 的 TXT 记录，或未开启 **Enable Dynamic DNS**。
   * **解决**：进入 dns.he.net 控制面板确认 TXT 记录已创建且启用 DDNS。

3. **脚本权限不足**：
   * **解决**：确保使用 `sudo` 或 `root` 用户运行。
