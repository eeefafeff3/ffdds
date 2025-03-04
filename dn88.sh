#!/bin/bash

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请以root权限运行此脚本（使用sudo）"
  exit 1
fi

echo "正在使用NetworkManager将DNS设置为1.1.1.1..."

# 检查并安装NetworkManager（如果未安装）
if ! command -v nmcli > /dev/null; then
  echo "NetworkManager未安装，正在安装..."
  apt-get update -y
  apt-get install network-manager -y
fi

# 获取当前网络连接名称（通常是System eth0或类似）
CONNECTION=$(nmcli -t -f NAME con show --active | head -n 1)
if [ -z "$CONNECTION" ]; then
  echo "未找到活跃网络连接，请检查网络状态"
  exit 1
fi
echo "检测到的网络连接: $CONNECTION"

# 设置DNS为1.1.1.1，不禁用自动DNS
echo "配置DNS..."
nmcli con mod "$CONNECTION" ipv4.dns "1.1.1.1"

# 应用更改
echo "应用网络配置..."
nmcli con up "$CONNECTION"

# 重启NetworkManager服务以确保生效
echo "重启NetworkManager服务..."
systemctl restart NetworkManager

# 验证DNS设置
echo "验证DNS配置..."
nmcli con show "$CONNECTION" | grep -i dns
dig google.com | grep "SERVER"

echo "DNS已设置为1.1.1.18完成！"
echo "若需恢复默认，可运行：nmcli con mod '$CONNECTION' ipv4.dns ''"
