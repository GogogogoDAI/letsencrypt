#!/bin/bash

# ========================================================
# Let's Encrypt + dns.he.net 一键交互式部署脚本 (终极修复版)
# ========================================================

# 确保以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 错误: 请使用 root 权限运行此脚本！(例如: sudo bash $0)"
    exit 1
fi

# 全局路径及参数配置
TARGET_SCRIPT="/usr/local/bin/auto_renew_he_cert.sh"
LOG_FILE="/var/log/cert_renew.log"
THRESHOLD_DAYS=7

# 0. 交互式读取用户配置输入
get_user_inputs() {
    echo "=========================================="
    echo " 证书自动续约配置 (首次运行引导)"
    echo "=========================================="

    while [ -z "$DOMAIN" ]; do
        read -r -p "👉 请输入域名 (例如 example.com): " DOMAIN
        DOMAIN=$(echo "$DOMAIN" | tr -d ' ')
    done

    while [ -z "$DDNS_KEY" ]; do
        read -r -p "👉 请输入 HE.net 的 DDNS Key: " DDNS_KEY
        DDNS_KEY=$(echo "$DDNS_KEY" | tr -d ' ')
    done

    while [ -z "$EMAIL" ]; do
        read -r -p "👉 请输入联系邮箱 (用于 Certbot 通知): " EMAIL
        EMAIL=$(echo "$EMAIL" | tr -d ' ')
    done

    echo "------------------------------------------"
    echo "配置确认："
    echo " - 目标域名 : ${DOMAIN}"
    echo " - DDNS Key : ${DDNS_KEY}"
    echo " - 账号邮箱 : ${EMAIL}"
    echo "=========================================="
    echo ""
}

# 1. 自动检测并安装缺失依赖
install_dependencies() {
    echo "[1/5] 检测并安装缺失的系统依赖库..."

    local REQUIRED_COMMANDS=("curl" "openssl" "certbot")
    local MISSING_DEPS=()

    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            MISSING_DEPS+=("$cmd")
        fi
    done

    if [ ${#MISSING_DEPS[@]} -eq 0 ]; then
        echo "✅ 基础依赖库已全部安装。"
    else
        echo "发现缺少依赖: ${MISSING_DEPS[*]}，正在自动安装..."
        if command -v apt-get &> /dev/null; then
            apt-get update -y
            apt-get install -y "${MISSING_DEPS[@]}" cron
            systemctl enable --now cron 2>/dev/null || service cron start
        elif command -v dnf &> /dev/null; then
            dnf install -y "${MISSING_DEPS[@]}" crontabs
            systemctl enable --now crond 2>/dev/null
        elif command -v yum &> /dev/null; then
            yum install -y "${MISSING_DEPS[@]}" crontabs
            systemctl enable --now crond 2>/dev/null
        else
            echo "❌ 未能识别系统包管理器，请手动安装: ${MISSING_DEPS[*]}"
            exit 1
        fi
        echo "✅ 依赖库安装成功！"
    fi
}

# 2. 生成主控制脚本
generate_target_script() {
    # 强制确保路径非空
    [ -z "$TARGET_SCRIPT" ] && TARGET_SCRIPT="/usr/local/bin/auto_renew_he_cert.sh"

    echo "[2/5] 正在写入主控制脚本至 ${TARGET_SCRIPT}..."

    cat << EOF > "$TARGET_SCRIPT"
#!/bin/bash

# ========================================================
# 证书检测与续约核心逻辑
# ========================================================

DOMAIN="${DOMAIN}"
DDNS_KEY="${DDNS_KEY}"
EMAIL="${EMAIL}"
THRESHOLD_DAYS=${THRESHOLD_DAYS}
CERT_PATH="/etc/letsencrypt/live/\${DOMAIN}/cert.pem"
LOG_FILE="${LOG_FILE}"

log() {
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$LOG_FILE"
}

# DNS Auth Hook 模式 (供 Certbot 调起)
if [ -n "\$CERTBOT_VALIDATION" ]; then
    HOOK_HOSTNAME="_acme-challenge.\${CERTBOT_DOMAIN}"
    log "[DNS Hook] 更新 dns.he.net TXT 记录: \${HOOK_HOSTNAME} -> \${CERTBOT_VALIDATION}"

    RESPONSE=\$(curl -s -X POST "https://dyn.dns.he.net/nic/update" \\
        -d "hostname=\${HOOK_HOSTNAME}" \\
        -d "password=\${DDNS_KEY}" \\
        -d "txt=\${CERTBOT_VALIDATION}")

    log "[DNS Hook] HE 响应: \${RESPONSE}"
    log "[DNS Hook] 等待 30 秒使 DNS 记录生效..."
    sleep 30
    exit 0
fi

# 证书天数检测与主控流程
if [ ! -f "\$CERT_PATH" ]; then
    log "警告: 未找到证书文件 \$CERT_PATH，启动首次证书申请流程..."
    DAYS_LEFT=0
else
    EXP_DATE=\$(openssl x509 -enddate -noout -in "\$CERT_PATH" | cut -d= -f2)
    EXP_EPOCH=\$(date -d "\$EXP_DATE" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "\$EXP_DATE" +%s)
    NOW_EPOCH=\$(date +%s)
    DAYS_LEFT=\$(( (EXP_EPOCH - NOW_EPOCH) / 86400 ))
    log "域名 [\${DOMAIN}] 证书当前剩余有效期: \${DAYS_LEFT} 天"
fi

if [ "\$DAYS_LEFT" -lt "\$THRESHOLD_DAYS" ]; then
    log "警告: 证书天数小于 \${THRESHOLD_DAYS} 天，开始执行续约..."

    certbot certonly --manual \\
        --preferred-challenges dns \\
        --manual-auth-hook "\$0" \\
        -d "\$DOMAIN" -d "*.\$DOMAIN" \\
        --non-interactive \\
        --agree-tos \\
        -m "\$EMAIL" \\
        --manual-public-ip-logging-ok

    if [ \$? -eq 0 ]; then
        log "✅ 续约成功！重载 Web 服务..."
        if systemctl is-active --quiet nginx; then
            systemctl reload nginx && log "Nginx 已重载。"
        elif systemctl is-active --quiet httpd; then
            systemctl reload httpd && log "Apache 已重载。"
        fi
    else
        log "❌ 错误: Certbot 续约失败，请检查配置或日志。"
    fi
else
    log "信息: 证书有效期充足（>= \${THRESHOLD_DAYS} 天），无需处理。"
fi
EOF

    echo "✅ 主控制脚本写入完成。"
}

# 3. 设置权限
set_permissions() {
    echo "[3/5] 配置脚本执行权限与日志文件..."
    chmod +x "$TARGET_SCRIPT"
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    echo "✅ 权限设置完成。"
}

# 4. 配置 Crontab 定时任务
setup_crontab() {
    echo "[4/5] 配置每天凌晨 3:00 的 Cron 定时任务..."
    CRON_JOB="0 3 * * * /bin/bash ${TARGET_SCRIPT} >> ${LOG_FILE} 2>&1"

    # 清理之前残留的无效空配置
    crontab -l 2>/dev/null | grep -v ' >> /var/log/cert_renew.log' | crontab -

    if crontab -l 2>/dev/null | grep -q "$TARGET_SCRIPT"; then
        echo "ℹ️ 定时任务已存在，自动更新配置..."
        (crontab -l 2>/dev/null | grep -v "$TARGET_SCRIPT"; echo "$CRON_JOB") | crontab -
    else
        (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    fi
    echo "✅ Crontab 定时任务配置完成。"
}

# 5. 初始测试运行
run_initial_test() {
    echo "[5/5] 执行初始安装运行测试..."
    bash "$TARGET_SCRIPT"
}

# 顺序执行
get_user_inputs
install_dependencies
generate_target_script
set_permissions
setup_crontab
run_initial_test

echo "=========================================="
echo "🎉 部署完成！"
echo "主控制脚本: ${TARGET_SCRIPT}"
echo "续约日志路径: ${LOG_FILE}"
echo "=========================================="
