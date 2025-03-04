#!/bin/bash

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请以root权限运行此脚本（使用sudo）"
  exit 1
fi

echo "正在使用NetworkManager将DNS设置为8.8.8.8..."

# 检查并安装NetworkManager（如果未安装）
if ! command -v nmcli > /dev/null; then
  echo "NetworkManager未安装，正在安装..."
  apt-get update -y
  apt-get install network-manager -y
fi

# 获取当前网络接口名称（通常是ens5或eth0）
INTERFACE=$(ip link | grep -o '^[0-9]: [^:]*' | grep -v lo | awk '{print $2}' | head -n 1)
if [ -z "$INTERFACE" ]; then
  echo "未找到网络接口，请检查系统网络状态"
  exit 1
fi
echo "检测到的网络接口: $INTERFACE"

# 停止可能干扰的systemd-networkd服务
if systemctl is-active systemd-networkd > /dev/null; then
  echo "停止systemd-networkd以让NetworkManager接管..."
  systemctl stop systemd-networkd
  systemctl disable systemd-networkd
fi

# 停止systemd-resolved以避免DNS拦截
if systemctl is-active systemd-resolved > /dev/null; then
  echo "停止systemd-resolved以直接使用8.8.8.8..."
  systemctl stop systemd-resolved
  systemctl disable systemd-resolved
  # 删除默认的resolv.conf符号链接并手动设置
  rm -f /etc/resolv.conf
  echo "nameserver 8.8.8.8" > /etc/resolv.conf
fi

# 检查是否存在活跃连接，若无则创建
CONNECTION=$(nmcli -t -f NAME con show --active | head -n 1)
if [ -z "$CONNECTION" ]; then
  echo "未找到活跃连接，正在为 $INTERFACE 创建连接..."
  CONNECTION="Wired-$INTERFACE"
  nmcli con add type ethernet con-name "$CONNECTION" ifname "$INTERFACE"
fi
echo "使用的网络连接: $CONNECTION"

# 设置DNS为8.8.8.8
echo "配置DNS..."
nmcli con mod "$CONNECTION" ipv4.dns "8.8.8.8"

# 确保接口由NetworkManager管理
nmcli dev set "$INTERFACE" managed yes

# 应用更改
echo "应用网络配置..."
nmcli con up "$CONNECTION"

# 重启NetworkManager服务
echo "重启NetworkManager服务..."
systemctl restart NetworkManager

# 验证DNS设置
echo "验证DNS配置..."
nmcli con show "$CONNECTION" | grep -i dns
dig google.com | grep "SERVER"

echo "DNS已设置为8.8.8.8完成！"
echo "若需恢复默认，可运行：nmcli con mod '$CONNECTION' ipv4.dns '' 并启用systemd-resolved"
