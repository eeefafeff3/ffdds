#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "请以 root 权限运行此脚本：sudo bash $0"
    exit 1
fi

# 定义变量（可根据需要修改）
SS_PORT="1599"              # Shadowsocks 服务端口
SS_METHOD="aes-256-gcm"     # 加密方法，可选：chacha20-ietf-poly1305 等

# 检查网络连接
echo "检查网络连接..."
if ! ping -c 3 8.8.8.8 > /dev/null 2>&1; then
    echo "网络不可达，请检查网络连接后重试。"
    exit 1
fi

# 更新系统并安装 Shadowsocks-libev 和依赖
echo "更新系统并安装 Shadowsocks-libev..."
apt update -y || { echo "更新失败，请检查网络或源"; exit 1; }
apt install -y shadowsocks-libev iproute2 || { echo "安装 Shadowsocks-libev 或 iproute2 失败"; exit 1; }

# 检查 Shadowsocks 是否安装成功
if ! command -v ss-server &> /dev/null; then
    echo "Shadowsocks-libev 未正确安装，请检查日志。"
    exit 1
fi

# 创建 Shadowsocks 配置文件（带加密，无密码）
echo "生成 Shadowsocks 配置文件..."
cat > /etc/shadowsocks-libev/config.json <<EOF
{
    "server": "0.0.0.0",
    "server_port": $SS_PORT,
    "method": "$SS_METHOD",
    "mode": "tcp_and_udp",
    "timeout": 300,
    "fast_open": false
}
EOF

# 设置文件权限
chmod 644 /etc/shadowsocks-libev/config.json

# 检查端口是否被占用（使用 ss）
if ss -tuln | grep ":$SS_PORT " > /dev/null; then
    echo "端口 $SS_PORT 已被占用，请修改 SS_PORT 变量后重试。"
    exit 1
fi

# 确保 systemd 服务使用配置文件
echo "配置 systemd 服务..."
systemctl stop shadowsocks-libev 2>/dev/null
cat > /lib/systemd/system/shadowsocks-libev
