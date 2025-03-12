#!/bin/bash

set -e  # 遇到错误退出

# 修复主机名解析问题
HOSTNAME=$(hostname)
if ! grep -q "$HOSTNAME" /etc/hosts; then
    echo "127.0.0.1 $HOSTNAME" | sudo tee -a /etc/hosts
fi

# 更新软件源并启用 contrib 和 non-free
sudo apt update
sudo sed -i 's/main$/main contrib non-free/' /etc/apt/sources.list
sudo apt update

# 安装 Dante 服务器
sudo apt install -y dante-server

# 备份原配置文件
sudo cp /etc/danted.conf /etc/danted.conf.bak

# 获取主网卡名称
NET_IF=$(ip route get 8.8.8.8 | awk '{print $5; exit}')

# 写入新的配置
cat <<EOF | sudo tee /etc/danted.conf
logoutput: syslog
internal: $NET_IF port = 15115
external: $NET_IF
method: username none
user.privileged: root
user.notprivileged: nobody
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect
}
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect
}
EOF

# 重启 Dante 服务
sudo systemctl restart danted
sudo systemctl enable danted

# 检查服务状态并输出结果
if systemctl is-active danted >/dev/null; then
    IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
    if [ -z "$IP" ]; then
        IP="未检测到公网 IP，请检查实例配置"
    fi
    echo "Socks5 代理安装完成!"
    echo "服务器 IP: $IP"
    echo "端口: 1080"
    echo "认证方式: 无（开放代理）"
    echo "请在 AWS 安全组中配置入站规则（如允许 1080 端口）。"
else
    echo "Dante 服务启动失败，请检查配置或日志（/var/log/syslog）。"
    exit 1
fi