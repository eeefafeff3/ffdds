#!/bin/bash

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请以root权限运行此脚本（使用sudo）"
  exit 1
fi

echo "正在将DNS设置为8.8.8.8并锁定配置..."

# 停止并禁用systemd-resolved（如果存在）
if systemctl is-active systemd-resolved > /dev/null; then
  echo "禁用systemd-resolved服务..."
  systemctl stop systemd-resolved
  systemctl disable systemd-resolved
fi

# 备份原始resolv.conf
if [ -f /etc/resolv.conf ]; then
  cp /etc/resolv.conf /etc/resolv.conf.bak
fi

# 设置resolv.conf为只使用8.8.8.8
cat << EOF > /etc/resolv.conf
nameserver 8.8.8.8
EOF

# 防止resolv.conf被覆盖
echo "锁定resolv.conf..."
chattr +i /etc/resolv.conf

# 禁用AWS可能的DHCP DNS覆盖
# 修改dhclient配置，拒绝自动DNS
if [ -f /etc/dhcp/dhclient.conf ]; then
  echo "supersede domain-name-servers 8.8.8.8;" >> /etc/dhcp/dhclient.conf
else
  echo "interface \"eth0\" { supersede domain-name-servers 8.8.8.8; }" > /etc/dhcp/dhclient.conf
fi

# 重启网络服务以应用更改
echo "重启网络服务..."
systemctl restart networking || systemctl restart NetworkManager

# 测试DNS是否生效
echo "测试DNS配置..."
nslookup google.com 8.8.8.8

echo "DNS已设置为8.8.8.8并锁定完成！"
echo "若需恢复默认配置，可运行：chattr -i /etc/resolv.conf"