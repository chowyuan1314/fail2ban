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
# 逻辑：先从配置文件找，如果配置文件没写（默认 22），则通过网络监听确认
SSH_PORT=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')

if [ -z "$SSH_PORT" ]; then
    SSH_PORT=$(ss -tlnp | grep sshd | awk '{print $4}' | awk -F: '{print $NF}' | sort -u | tr '\n' ',' | sed 's/,$//')
fi

# 如果还是没找到，兜底设置为 22
if [ -z "$SSH_PORT" ]; then
    SSH_PORT="22"
fi

echo "检测到 SSH 端口为: $SSH_PORT"

# 4. 写入通用优化配置
# 使用 backend=systemd 以配合之前优化的日志限额
# 增加 bantime 至 24h 以应对高频攻击
cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
# 忽略回环地址
ignoreip = 127.0.0.1/8 ::1
# 封禁时间 24 小时
bantime  = 24h
# 统计周期 30 分钟
findtime = 30m
# 失败 3 次即封禁
maxretry = 3
# 封禁该 IP 的所有端口
banaction = iptables-allports

[sshd]
enabled = true
port    = $SSH_PORT
filter  = sshd
# 使用 systemd 后端，检索效率最高
backend = systemd
EOF

# 5. 启动并设置自启
systemctl daemon-reload
systemctl enable fail2ban
systemctl restart fail2ban

echo "------------------------------------------------"
echo "部署完成！"
echo "当前监控端口: $SSH_PORT"
echo "封禁策略: 10分钟内失败3次，封禁所有端口24小时"
echo "查看状态命令: fail2ban-client status sshd"
echo "------------------------------------------------"
