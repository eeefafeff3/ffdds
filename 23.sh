#!/bin/bash

# 提示用户输入自定义端口
read -p "请输入你想使用的HTTP代理端口（默认：3128）：" CUSTOM_PORT
CUSTOM_PORT=${CUSTOM_PORT:-6688}  # 如果用户未输入，则使用默认端口3128

# 更新系统包列表
sudo apt-get update

# 安装Squid
sudo apt-get install -y squid

# 备份原始配置文件
sudo cp /etc/squid/squid.conf /etc/squid/squid.conf.bak

# 配置Squid允许所有IP访问
sudo sed -i 's/http_access deny all/http_access allow all/' /etc/squid/squid.conf

# 修改Squid监听端口
sudo sed -i "s/http_port 3128/http_port $CUSTOM_PORT/" /etc/squid/squid.conf

# 重启Squid服务以应用配置
sudo systemctl restart squid

# 设置Squid开机自启
sudo systemctl enable squid

# 输出代理服务器信息
echo "HTTP代理服务器已搭建完成！"
echo "代理服务器地址：$(hostname -I | awk '{print $1}')"
echo "代理服务器端口：$CUSTOM_PORT"
