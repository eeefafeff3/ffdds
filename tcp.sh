#!/bin/bash
# ultra_random_fingerprint_distributed.sh
# 分布式 fingerprint 混淆脚本，去掉更换 MAC 部分
# 使用: curl -sSL https://raw.githubusercontent.com/xxx/yyy/main/ultra_random_fingerprint_distributed.sh | sudo bash

set -e

install_if_missing() {
    if ! dpkg -s "$1" >/dev/null 2>&1; then
        echo "安装缺少依赖 $1 ..."
        apt update -y
        apt install -y "$1"
    fi
}
install_if_missing iproute2
install_if_missing iptables

IFACE=$(ip route | grep '^default' | awk '{print $5}')
[ -z "$IFACE" ] && { echo "未检测到默认网卡"; exit 1; }

echo "ultra fingerprint 混淆 on $(hostname)"

# 随机种子：基于 hostname、ip、时间、/dev/urandom
HOST=$(hostname)
IP=$(hostname -I | awk '{print $1}')
SEED=$(echo -n "$HOST$IP$(date +%s)$(head -c8 /dev/urandom | base64)" | sha256sum | cut -c1-16)

rand_from_seed() {
    local mod=$1
    echo $(echo "$SEED$RANDOM$(date +%N)" | sha256sum | tr -dc '0-9' | head -c5 | awk -v m=$mod '{print ($1 % m)}')
}

# ========== 超随机循环多次 ==========
LOOP=$((2 + $(rand_from_seed 4)))  # 2~5 次
for ((i=0;i<$LOOP;i++)); do
    # 随机 sysctl
    [ $(( $(rand_from_seed 10) % 2)) -eq 0 ] && sysctl -w net.ipv4.tcp_timestamps=0 || sysctl -w net.ipv4.tcp_timestamps=1
    [ $(( $(rand_from_seed 20) % 2)) -eq 0 ] && sysctl -w net.ipv4.tcp_sack=0 || sysctl -w net.ipv4.tcp_sack=1
    [ $(( $(rand_from_seed 30) % 2)) -eq 0 ] && sysctl -w net.ipv4.tcp_window_scaling=0 || sysctl -w net.ipv4.tcp_window_scaling=1

    # 清理再设置 iptables
    iptables -t mangle -F

    TTL=$((50 + $(rand_from_seed 79)))    # 50~128
    MSS=$((1200 + $(rand_from_seed 260))) # 1200~1460
    TOS=$(rand_from_seed 256)

    echo "[$i] TTL=$TTL MSS=$MSS TOS=0x$(printf '%02x' $TOS)"
    iptables -t mangle -A POSTROUTING -j TTL --ttl-set $TTL
    iptables -t mangle -A PREROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSS
    iptables -t mangle -A OUTPUT -p tcp -j TOS --set-tos $TOS

    sleep_time=$(awk -v min=0.5 -v max=2 'BEGIN{srand(); print min+rand()*(max-min)}')
    sleep $sleep_time
done

echo " ultra fingerprint 已完成 on $(hostname)"
echo "查看: iptables -t mangle -L -v"
