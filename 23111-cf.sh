#!/bin/bash

# 设置HTTP代理端口为2311
CUSTOM_PORT=23111
# 设置代理用户名和密码
PROXY_USER="haohao888"    # 可自定义用户名
PROXY_PASS="haohao888" # 可自定义密码

# 更新系统包列表
#sudo apt-get update -y

# 安装Squid和认证工具
sudo apt-get install -y squid apache2-utils

# 备份原始配置文件
sudo cp /etc/squid/squid.conf /etc/squid/squid.conf.bak

# 创建密码文件并设置权限
sudo touch /etc/squid/passwd
sudo chown proxy:proxy /etc/squid/passwd
sudo chmod 640 /etc/squid/passwd

# 使用htpasswd创建用户名和密码（-b参数允许非交互式设置密码）
sudo htpasswd -b /etc/squid/passwd $PROXY_USER $PROXY_PASS

# 创建新的配置文件
cat << EOF | sudo tee /etc/squid/squid.conf
# 认证配置
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm Squid proxy-caching web server
auth_param basic children 5
acl authenticated proxy_auth REQUIRED

# 基本配置
http_port $CUSTOM_PORT
http_access allow authenticated
http_access deny all

# 强制使用1.1.1.1作为DNS服务器
dns_nameservers 1.1.1.1

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
echo "用户名：$PROXY_USER"
echo "密码：$PROXY_PASS"
echo "DNS服务器：1.1.1.1"
