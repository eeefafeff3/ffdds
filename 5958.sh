#!/bin/bash

# 直接设置HTTP代理端口为 
CUSTOM_PORT=5958

# 更新系统包列表
#sudo apt-get update -y

# 安装Squid
sudo apt-get install -y squid

# 备份原始配置文件
sudo cp /etc/squid/squid.conf /etc/squid/squid.conf.bak

# 创建新的配置文件
cat << EOF | sudo tee /etc/squid/squid.conf
# 基本配置
http_port $CUSTOM_PORT
http_access allow all

# 强制使用127.0.0.53作为DNS服务器
dns_nameservers 13.231.195.35

# 默认配置保持不变
cache_dir ufs /var/spool/squid 100 16 256
coredump_dir /var/spool/squid
EOF

# 重启Squid服务以应用配置
sudo systemctl restart squid

# 设置Squid开机自启
sudo systemctl enable squid

# 输出代理服务器信息
echo "HTTP代理服务器已搭建完成！"
echo "代理服务器地址：$(hostname -I | awk '{print $1}')"
echo "代理服务器端口：$CUSTOM_PORT"
echo "DNS服务器：8.8.8.8"
