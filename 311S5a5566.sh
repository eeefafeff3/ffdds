#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 权限运行此脚本（使用 sudo）"
  exit 1
fi

# 1. 更新系统并安装 Dante 和 iptables-persistent
echo "正在安装 Dante Server 和 iptables-persistent..."
apt update
# 非交互式安装 iptables-persistent
DEBIAN_FRONTEND=noninteractive apt install -y dante-server iptables-persistent

# 2. 配置 Dante Server（无密码认证）
echo "正在配置 Dante Server..."
INTERFACE=$(ip -o -4 route show to default | awk '{print $5}')  # 获取公网接口
cat << EOF > /etc/danted.conf
# 日志输出
logoutput: syslog

# 绑定地址和端口
internal: 0.0.0.0 port = 5566
external: $INTERFACE

# Socks5 方法：无认证
socksmethod: none

# 允许所有客户端连接
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

# 允许所有 Socks 请求
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: connect disconnect error
    protocol: tcp udp
    proxyprotocol: socks_v5
}
EOF

# 3. 临时启用 IP 转发
echo "临时启用 IP 转发..."
echo 1 > /proc/sys/net/ipv4/ip_forward
# 不修改 /etc/sysctl.conf，仅当前会话有效

# 4. 配置系统级 NAT
echo "配置系统级 NAT..."
iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE

# 保存 iptables 规则（确保 NAT 规则持久化）
iptables-save > /etc/iptables/rules.v4

# 5. 指定 DNS 为 8.8.8.8
echo "指定 DNS 为 8.8.8.8..."
cat << EOF > /etc/resolv.conf
nameserver 54.167.110.1
EOF
# 防止 resolv.conf 被覆盖（适用于 systemd-resolved）
if systemctl is-active systemd-resolved > /dev/null; then
    systemctl disable systemd-resolved
    systemctl stop systemd-resolved
fi

# 6. 重启 Dante 服务
echo "正在启动 Dante 服务..."
systemctl restart danted
systemctl enable danted

# 7. 获取 VPS 的公网 IP
VPS_IP=$(curl -s ifconfig.me)

echo "无密码的 Socks5 代理服务器已成功搭建并配置 NAT 和 DNS！"
echo "代理地址: $VPS_IP:1080"
echo "DNS: 8.8.8.8"
echo "IP 转发为临时设置，重启后将失效。"
echo "无需密码，直接在 Firefox 中配置即可。"