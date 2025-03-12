#!/bin/bash

set -e  # 遇到错误退出

# 更新系统
#sudo apt update -y && sudo apt upgrade -y

# 安装 Dante 服务器
sudo apt install -y dante-server

# 备份原配置文件
sudo cp /etc/danted.conf /etc/danted.conf.bak

# 获取主网卡名称
NET_IF=$(ip route get 8.8.8.8 | awk -- '{print $5; exit}')

# 写入新的配置
cat <<EOF | sudo tee /etc/danted.conf
logoutput: syslog
internal: \$NET_IF port = 12888
external: \$NET_IF
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

# 启用并启动 Dante 服务
sudo systemctl enable danted
sudo systemctl restart danted

# 输出 Socks5 代理信息
IP=$(curl -s ifconfig.me)
echo "Socks5 代理安装完成!"
echo "服务器 IP: $IP"
echo "端口: 1080"
echo "认证方式: 无（开放代理）"
echo "请手动配置安全规则，如使用 AWS 安全组限制访问。"
