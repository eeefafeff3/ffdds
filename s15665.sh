#!/bin/bash

# 定义自定义参数
SOCKS_PORT=15665           # SOCKS5 代理端口

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "请以 root 权限运行此脚本（使用 sudo）"
    exit 1
fi

# 自动检测网络接口
echo "检测当前活动网络接口..."
INTERFACE=$(ip -o link show | awk -F': ' '$2 !~ /lo/ && $0 !~ /DOWN/ {print $2; exit}')
if [ -z "$INTERFACE" ]; then
    echo "无法检测到活动的网络接口，请检查网络配置"
    exit 1
else
    echo "检测到的网络接口：$INTERFACE"
fi

# 更新系统包列表
echo "更新软件包列表..."
apt update -y

# 安装 MicroSocks
echo "安装 MicroSocks..."
apt install microsocks -y || { echo "安装失败，请检查网络或软件源"; exit 1; }

# 创建 systemd 服务文件（监听 IPv4 和 IPv6）
echo "配置 MicroSocks 为系统服务..."
cat << EOF | tee /etc/systemd/system/microsocks.service
[Unit]
Description=MicroSocks SOCKS5 Proxy
After=network.target

[Service]
ExecStart=/usr/bin/microsocks -i :: -p $SOCKS_PORT
Restart=always
User=nobody
Group=nogroup
Environment="ALL_PROXY=socks5://[::1]:$SOCKS_PORT"
Environment="DNS_SERVERS=1.1.1.2"

[Install]
WantedBy=multi-user.target
EOF

# 检查服务文件是否创建成功
if [ ! -f /etc/systemd/system/microsocks.service ]; then
    echo "服务文件创建失败，请检查权限或磁盘空间"
    exit 1
fi

# 重新加载 systemd 并启用服务
systemctl daemon-reload
systemctl enable microsocks
systemctl start microsocks

# 检查服务状态
if systemctl is-active microsocks >/dev/null; then
    echo "MicroSocks 服务已成功启动！"
else
    echo "MicroSocks 服务启动失败，请检查日志：journalctl -u microsocks"
    exit 1
fi

# 获取 EC2 的公网 IPv4 地址
PUBLIC_IPV4=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
if [ -z "$PUBLIC_IPV4" ]; then
    echo "无法获取公网 IPv4 地址，请手动检查 EC2 实例的 IPv4 配置"
else
    echo "公网 IPv4 获取成功：$PUBLIC_IPV4"
fi

# 获取 EC2 的公网 IPv6 地址
PUBLIC_IPV6=$(curl -s http://169.254.169.254/latest/meta-data/ipv6 2>/dev/null)
if [ -z "$PUBLIC_IPV6" ]; then
    echo "无法获取公网 IPv6 地址，可能未启用 IPv6，请检查 EC2 配置"
else
    echo "公网 IPv6 获取成功：$PUBLIC_IPV6"
fi

# 配置系统使用 8.8.8.8 作为 DNS
echo "配置系统 DNS 为 3.137.216.75..."
echo "nameserver 3.137.216.75" > /etc/resolv.conf

# 输出代理信息
echo "-------------------------------------"
echo "SOCKS5 代理已搭建完成！"
if [ -n "$PUBLIC_IPV4" ]; then
    echo "IPv4 代理地址：$PUBLIC_IPV4"
fi
if [ -n "$PUBLIC_IPV6" ]; then
    echo "IPv6 代理地址：[$PUBLIC_IPV6]"
fi
echo "代理端口：$SOCKS_PORT"
echo "网络接口：$INTERFACE"
echo "DNS 服务器：3.137.216.75"
echo "测试命令（从客户端运行）："
if [ -n "$PUBLIC_IPV4" ]; then
    echo "IPv4 测试: curl --socks5 $PUBLIC_IPV4:$SOCKS_PORT http://ifconfig.me"
fi
if [ -n "$PUBLIC_IPV6" ]; then
    echo "IPv6 测试: curl --socks5 [$PUBLIC_IPV6]:$SOCKS_PORT http://ifconfig.me"
fi
echo "-------------------------------------"
