#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "请以 root 权限运行此脚本：sudo bash $0"
    exit 1
fi

# 定义变量（可根据需要修改）
SS_PORT="1080"              # Shadowsocks 服务端口
SS_METHOD="aes-256-gcm"     # 加密方法，可选：chacha20-ietf-poly1305 等

# 检查网络连接
echo "检查网络连接..."
if ! ping -c 3 8.8.8.8 > /dev/null 2>&1; then
    echo "网络不可达，请检查网络连接后重试。"
    exit 1
fi

# 更新系统并安装 Shadowsocks-libev
echo "更新系统并安装 Shadowsocks-libev..."
apt update -y || { echo "更新失败，请检查网络或源"; exit 1; }
apt install -y shadowsocks-libev || { echo "安装 Shadowsocks-libev 失败"; exit 1; }

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
    "fast_open": false,
    "noauth": true
}
EOF

# 设置文件权限
chmod 644 /etc/shadowsocks-libev/config.json

# 检查端口是否被占用
if netstat -tuln | grep ":$SS_PORT " > /dev/null; then
    echo "端口 $SS_PORT 已被占用，请修改 SS_PORT 变量后重试。"
    exit 1
fi

# 启动 Shadowsocks 服务
echo "启动 Shadowsocks 服务..."
systemctl restart shadowsocks-libev
systemctl enable shadowsocks-libev

# 检查服务状态
if systemctl is-active shadowsocks-libev >/dev/null; then
    echo "Shadowsocks 服务已成功启动。"
else
    echo "Shadowsocks 服务启动失败，请检查日志：journalctl -u shadowsocks-libev"
    exit 1
fi

# 安装 iptables-persistent（用于全局代理）
echo "安装 iptables-persistent 以保存规则..."
apt install -y iptables-persistent

# 配置 iptables 规则（全局代理 TCP）
echo "配置 iptables 规则以重定向 TCP 流量..."
iptables -t nat -N SHADOWSOCKS
iptables -t nat -A SHADOWSOCKS -d 0.0.0.0/8 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 10.0.0.0/8 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 127.0.0.0/8 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 172.16.0.0/12 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 192.168.0.0/16 -j RETURN
iptables -t nat -A SHADOWSOCKS -p tcp -j REDIRECT --to-ports $SS_PORT
iptables -t nat -A OUTPUT -p tcp -j SHADOWSOCKS
iptables -t nat -A PREROUTING -p tcp -j SHADOWSOCKS

# 保存 iptables 规则
iptables-save > /etc/iptables/rules.v4

# 测试代理是否生效
echo "测试代理是否正常工作..."
curl -x socks5://127.0.0.1:$SS_PORT ifconfig.me && echo "代理测试成功！" || echo "代理测试失败，请检查配置。"

echo "Shadowsocks 搭建完成！"
echo "SOCKS5 代理运行在 127.0.0.1:$SS_PORT"
echo "带隧道加密 ($SS_METHOD)，无需密码。"
echo "全局 TCP 流量已通过 Shadowsocks 代理，UDP 需要客户端手动配置。"
echo "如需远程访问，请确保防火墙允许 $SS_PORT 端口：sudo ufw allow $SS_PORT"
