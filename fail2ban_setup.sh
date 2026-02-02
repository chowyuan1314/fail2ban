#!/bin/bash

# 1. 权限检查
if [ "$EUID" -ne 0 ]; then 
  echo "请使用 root 权限运行此脚本。"
  exit 1
fi

echo "正在开始 Fail2Ban 自动化部署..."

# 2. 自动识别包管理器并安装
if command -v apt &> /dev/null; then
    apt update && apt install -y fail2ban
elif command -v dnf &> /dev/null; then
    dnf install -y epel-release && dnf install -y fail2ban
elif command -v yum &> /dev/null; then
    yum install -y epel-release && yum install -y fail2ban
else
    echo "未识别的操作系统，请手动安装 Fail2Ban。"
    exit 1
fi

# 3. 自动获取本机 SSH 端口
SSH_PORT=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')

if [ -z "$SSH_PORT" ]; then
    SSH_PORT=$(ss -tlnp | grep sshd | awk '{print $4}' | awk -F: '{print $NF}' | sort -u | tr '\n' ',' | sed 's/,$//')
fi

if [ -z "$SSH_PORT" ]; then
    SSH_PORT="22"
fi

echo "检测到 SSH 端口为: $SSH_PORT"

# 4. 写入通用优化配置
# 使用 backend=systemd 以兼容没有 /var/log/auth.log 的系统
cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
# 忽略回环地址
ignoreip = 127.0.0.1/8 ::1
# 封禁时间 24 小时
bantime  = 24h
# 统计周期 10 分钟
findtime = 10m
# 失败 3 次即封禁
maxretry = 3
# 封禁该 IP 的所有端口
banaction = iptables-allports

[sshd]
enabled = true
port    = $SSH_PORT
filter  = sshd
backend = systemd
EOF

# 5. 写入 sshd-session 兼容性补丁 (关键一步)
# 解决 OpenSSH 9.8+ 进程名变更导致的识别失效问题
echo "正在配置 sshd-session 兼容性补丁..."
echo -e "[Definition]\nprefregex = ^(<?[^ \\\\t\\\\n\\\\r\\\\f\\\\v]+>? )?(?:sshd(?:-session)?|sshd-session)\\\\[<PID>\\\\]: <CONTENT>$" > /etc/fail2ban/filter.d/sshd.local

# 6. 启动并设置自启
systemctl daemon-reload
systemctl enable fail2ban
systemctl restart fail2ban

echo "------------------------------------------------"
echo "部署完成！"
echo "当前监控端口: $SSH_PORT"
echo "适配模式: 兼容 sshd 及 sshd-session (OpenSSH 9.8+)"
echo "查看状态命令: fail2ban-client status sshd"
echo "------------------------------------------------"
