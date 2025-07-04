#!/bin/bash

set -e  # 遇到错误退出

# 日志函数
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 修复主机名解析
HOSTNAME=$(hostname)
if ! grep -q "$HOSTNAME" /etc/hosts; then
  log "修复主机名解析，添加 $HOSTNAME 到 /etc/hosts"
  echo "127.0.0.1 $HOSTNAME" | tee -a /etc/hosts
fi

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  log "请以 root 权限运行此脚本"
  exit 1
fi

# 更新软件源并启用 contrib 和 non-free
log "更新软件源并启用 contrib 和 non-free"
apt update
sed -i 's/main$/main contrib non-free/' /etc/apt/sources.list
apt update

# 动态检测主网络接口
MAIN_IFACE=$(ip route get 8.8.8.8 | grep -o 'dev [[:alnum:]]\+' | awk '{print $2}')
if [ -z "$MAIN_IFACE" ]; then
  log "无法检测主网络接口"
  exit 1
fi
log "检测到主网络接口: $MAIN_IFACE"

# 生成随机命名空间名称（8字符）
NAMESPACE="ns$(cat /dev/urandom | tr -dc 'a-z0-9' | head -c 8)"
log "生成随机命名空间: $NAMESPACE"

# 生成随机虚拟网络接口名称
VETH0="veth$(cat /dev/urandom | tr -dc 'a-z0-9' | head -c 6)"
VETH1="veth$(cat /dev/urandom | tr -dc 'a-z0-9' | head -c 6)"
log "生成随机接口: $VETH0 和 $VETH1"

# 生成随机 IP 地址（在 10.0.0.0/8 私有范围内）
RANDOM_OCTET2=$((RANDOM % 256))  # 0-255
RANDOM_OCTET3=$((RANDOM % 256))  # 0-255
IP_VETH0="10.$RANDOM_OCTET2.$RANDOM_OCTET3.1"
IP_VETH1="10.$RANDOM_OCTET2.$RANDOM_OCTET3.2"
log "生成随机 IP: $VETH0 使用 $IP_VETH0, $VETH1 使用 $IP_VETH1"

# 检查并清理现有命名空间（如果存在）
if ip netns list | grep -q "$NAMESPACE"; then
  log "检测到现有 $NAMESPACE，正在删除..."
  ip netns del "$NAMESPACE" || { log "删除现有 $NAMESPACE 失败"; exit 1; }
fi

# 创建网络命名空间
log "创建网络命名空间 $NAMESPACE"
ip netns add "$NAMESPACE" || { log "创建网络命名空间失败"; exit 1; }

# 创建虚拟网络接口
log "创建虚拟接口 $VETH0 和 $VETH1"
ip link add "$VETH0" type veth peer name "$VETH1" || { log "创建虚拟接口失败"; exit 1; }
ip link set "$VETH1" netns "$NAMESPACE" || { log "移动 $VETH1 到命名空间失败"; exit 1; }

# 配置网络接口
log "为 $VETH0 和 $VETH1 配置 IP 地址"
ip addr add "$IP_VETH0/24" dev "$VETH0" || { log "为 $VETH0 分配 IP 失败"; exit 1; }
ip link set "$VETH0" up || { log "启用 $VETH0 失败"; exit 1; }
ip netns exec "$NAMESPACE" ip addr add "$IP_VETH1/24" dev "$VETH1" || { log "为 $VETH1 分配 IP 失败"; exit 1; }
ip netns exec "$NAMESPACE" ip link set "$VETH1" up || { log "启用 $VETH1 失败"; exit 1; }
ip netns exec "$NAMESPACE" ip route add default via "$IP_VETH0" || { log "设置默认路由失败"; exit 1; }

# 启用 IP 转发
log "启用 IP 转发"
echo 1 > /proc/sys/net/ipv4/ip_forward || { log "启用 IP 转发失败"; exit 1; }
sysctl -p >/dev/null 2>&1

# 预设 iptables-persistent 配置以避免交互提示
log "预设 iptables-persistent 配置"
echo "iptables-persistent iptables-persistent/autosave_v4 boolean false" | debconf-set-selections
echo "iptables-persistent iptables-persistent/autosave_v6 boolean false" | debconf-set-selections

# 安装 iptables-persistent
log "安装 iptables-persistent"
DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent || { log "安装 iptables-persistent 失败"; exit 1; }

# 配置 NAT
log "配置 NAT 规则"
ipt kamles -t nat -A POSTROUTING -s "10.$RANDOM_OCTET2.$RANDOM_OCTET3.0/24" -o "$MAIN_IFACE" -j MASQUERADE || { log "配置 NAT 失败"; exit 1; }

# 保存 iptables 规则
log "保存 iptables 规则"
iptables-save > /etc/iptables/rules.v4 || { log "保存 iptables 规则失败"; exit 1; }

# 安装 Dante 服务器
log "安装 Dante 服务器"
apt install -y dante-server || { log "安装 Dante 失败"; exit 1; }

# 备份 Dante 配置文件
log "备份 Dante 配置文件"
cp /etc/danted.conf /etc/danted.conf.bak || { log "无法备份 Dante 配置文件"; exit 1; }

# 在命名空间内配置 Dante
log "配置 Dante（无密码模式）"
ip netns exec "$NAMESPACE" bash -c "cat > /etc/danted.conf" <<EOF
logoutput: syslog
internal: $VETH1 port = 43888
external: $VETH1
method: none
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

# 确保配置文件权限
ip netns exec "$NAMESPACE" chmod 600 /etc/danted.conf

# 配置 systemd 服务
log "配置 systemd 服务"
cat > /etc/systemd/system/dante-proxy.service <<EOF
[Unit]
Description=Dante SOCKS5 代理在网络命名空间中运行
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/ip netns exec $NAMESPACE /usr/sbin/danted -f /etc/danted.conf
Restart=on-failure
ExecStop=/usr/bin/killall danted

[Install]
WantedBy=multi-user.target
EOF

# 启用并启动 systemd 服务
log "启用并启动 Dante 服务"
systemctl enable dante-proxy || { log "启用 Dante 服务失败"; exit 1; }
systemctl start dante-proxy || { log "启动 Dante 服务失败"; exit 1; }

# 检查服务状态并输出结果
if systemctl is-active dante-proxy >/dev/null; then
  IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "未检测到公网 IP，请检查实例配置")
  log "SOCKS5 代理安装完成！"
  echo "服务器 IP: $IP"
  echo "端口: 43888"
  echo "认证方式: 无（开放代理）"
  echo "请在 AWS 安全组中允许端口 43888 的 TCP 和 UDP 流量。"
else
  log "Dante 服务启动失败，请检查配置或日志（/var/log/syslog）。"
  exit 1
fi