#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "请以 root 权限运行此脚本：sudo bash $0"
    exit 1
fi

# 定义变量（可根据需要修改）
SS_PORT="1080"              # Shadowsocks 服务端口
SS_PASSWORD="wf156156" # 替换为你的密码
SS_METHOD="aes-256-gcm"     # 加密方法，可选：chacha20-ietf-poly1305 等
LOCAL_PORT="1080"           # 本地 SOCKS5 监听端口

# 更新系统并安装 Shadowsocks-libev
echo "正在更新系统并安装 Shadowsocks-libev..."
apt update && apt install -y shadowsocks-libev iptables

# 创建 Shadowsocks 配置文件
echo "生成 Shadowsocks 配置文件..."
cat > /etc/shadowsocks-libev/config.json <<EOF
{
    "server": "0.0.0.0",
    "server_port": $SS_PORT,
    "local_address": "127.0.0.1",
    "local_port": $LOCAL_PORT,
    "password": "$SS_PASSWORD",
    "method": "$SS_METHOD",
    "mode": "tcp_and_udp",
    "timeout": 30,
    "fast_open": true
}
EOF

# 设置文件权限
chmod 644 /etc/shadowsocks-libev/config.json

# 启动 Shadowsocks 服务
echo "启动 Shadowsocks 服务..."
systemctl restart shadowsocks-libev
systemctl enable shadowsocks-libev

# 配置 iptables 规则（仅 TCP）
echo "配置 iptables 规则以重定向 TCP 流量..."
iptables -t nat -N SHADOWSOCKS
iptables -t nat -A SHADOWSOCKS -d 0.0.0.0/8 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 10.0.0.0/8 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 127.0.0.0/8 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 172.16.0.0/12 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 192.168.0.0/16 -j RETURN
iptables -t nat -A SHADOWSOCKS -p tcp -j REDIRECT --to-ports $LOCAL_PORT
iptables -t nat -A OUTPUT -p tcp -j SHADOWSOCKS
iptables -t nat -A PREROUTING -p tcp -j SHADOWSOCKS

# 保存 iptables 规则
echo "保存 iptables 规则..."
apt install -y iptables-persistent
iptables-save > /etc/iptables/rules.v4

# 测试代理是否生效
echo "测试代理是否正常工作..."
curl -x socks5://127.0.0.1:$LOCAL_PORT ifconfig.me

echo "Shadowsocks 搭建完成！"
echo "SOCKS5 代理运行在 127.0.0.1:$LOCAL_PORT"
echo "密码: $SS_PASSWORD, 加密方法: $SS_METHOD"
echo "全局 TCP 流量已通过 Shadowsocks 代理，UDP 需要客户端手动配置。"
