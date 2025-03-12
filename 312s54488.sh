#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 权限运行此脚本（使用 sudo）"
  exit 1
fi

# 固定配置
PORT=4488
USERNAME="wodeha"
PASSWORD="wodeha"

# 更新系统并安装必要工具
echo "正在更新系统并安装依赖..."
apt install build-essential wget -y

# 下载并安装 Dante
echo "正在下载并安装 Dante..."
wget https://www.inet.no/dante/files/dante-1.4.3.tar.gz
tar -xzf dante-1.4.3.tar.gz
cd dante-1.4.3
./configure
make
make install

# 检查 Dante 是否安装成功
if [ ! -f /usr/local/sbin/sockd ]; then
  echo "Dante 安装失败，请检查编译过程！"
  exit 1
fi
echo "Dante 安装成功！"

# 创建 Dante 配置文件
echo "正在创建 Dante 配置文件..."
mkdir -p /etc/dante
cat <<EOF > /etc/dante/sockd.conf
logoutput: syslog
internal: 0.0.0.0 port = $PORT
external: $(ip route get 1 | awk '{print $7;exit}')
clientmethod: none
socksmethod: username
user.privileged: root
user.unprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: error
    socksmethod: username
}
EOF

# 创建密码文件
echo "正在配置用户名和密码..."
echo "$USERNAME:$PASSWORD" > /etc/dante/passwd
chmod 600 /etc/dante/passwd

# 创建 systemd 服务
echo "正在配置 Dante 为系统服务..."
cat <<EOF > /etc/systemd/system/dante.service
[Unit]
Description=Dante SOCKS5 Server
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/sbin/sockd -f /etc/dante/sockd.conf
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 启用并启动服务
systemctl daemon-reload
systemctl enable dante
systemctl start dante

# 检查服务状态
if systemctl is-active dante | grep -q "active"; then
  echo "Dante 服务启动成功！"
else
  echo "Dante 服务启动失败，请检查日志：journalctl -u dante"
  exit 1
fi

# 检查防火墙（如果启用）
if command -v ufw > /dev/null && ufw status | grep -q "active"; then
  echo "正在配置防火墙..."
  ufw allow $PORT
fi

# 输出连接信息
PUBLIC_IP=$(curl -s ifconfig.me)
echo ""
echo "Socks5 代理搭建完成！连接信息如下："
echo "服务器地址: $PUBLIC_IP"
echo "端口: $PORT"
echo "用户名: $USERNAME"
echo "密码: $PASSWORD"
echo "协议: Socks5"
echo "请确保 AWS EC2 安全组已开放端口 $PORT！"
