#!/bin/bash

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请以root权限运行此脚本（使用sudo）"
  exit 1
fi

echo "正在使用Netplan将DNS设置为8.8.8.8..."

# 获取当前网络接口名称（通常是eth0）
INTERFACE=$(ip link | grep -o '^[0-9]: [^:]*' | grep -v lo | awk '{print $2}' | head -n 1)
if [ -z "$INTERFACE" ]; then
  echo "未找到网络接口，请检查系统网络配置"
  exit 1
fi
echo "检测到的网络接口: $INTERFACE"

# 备份原始Netplan配置文件（如果存在）
NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"
if [ -f "$NETPLAN_FILE" ]; then
  cp "$NETPLAN_FILE" "$NETPLAN_FILE.bak"
  echo "已备份原始配置文件到 $NETPLAN_FILE.bak"
fi

# 写入新的Netplan配置
cat << EOF > "$NETPLAN_FILE"
network:
  version: 2
  ethernets:
    $INTERFACE:
      dhcp4: true
      nameservers:
        addresses: [8.8.8.8]
EOF

# 检查配置文件语法
echo "检查Netplan配置..."
sudo netplan try
if [ $? -ne 0 ]; then
  echo "Netplan配置有误，正在恢复备份..."
  mv "$NETPLAN_FILE.bak" "$NETPLAN_FILE"
  exit 1
fi

# 应用配置
echo "应用Netplan配置..."
sudo netplan apply

# 刷新网络（确保立即生效）
echo "刷新网络配置..."
sudo dhclient -r "$INTERFACE" && sudo dhclient "$INTERFACE"

# 验证DNS设置
echo "验证DNS配置..."
if command -v resolvectl > /dev/null; then
  resolvectl status | grep "DNS Servers"
else
  cat /etc/resolv.conf
fi
dig google.com | grep "SERVER"

echo "DNS已设置为8.8.8.8完成！"
echo "若需恢复默认，请手动编辑 $NETPLAN_FILE 或恢复备份。"
