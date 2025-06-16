#!/bin/bash

# Secure WireGuard server installer
# https://github.com/angristan/wireguard-install

RED='\033[0;31m'
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'

function isRoot() {
    if [ "${EUID}" -ne 0 ]; then
        echo "You need to run this script as root"
        exit 1
    fi
}

function checkVirt() {
    function openvzErr() {
        echo "OpenVZ is not supported"
        exit 1
    }
    function lxcErr() {
        echo "LXC is not supported (yet)."
        echo "WireGuard can technically run in an LXC container,"
        echo "but the kernel module has to be installed on the host,"
        echo "the container has to be run with some specific parameters"
        echo "and only the tools need to be installed in the container."
        exit 1
    }
    if command -v virt-what &>/dev/null; then
        if [ "$(virt-what)" == "openvz" ]; then
            openvzErr
        fi
        if [ "$(virt-what)" == "lxc" ]; then
            lxcErr
        fi
    else
        if [ "$(systemd-detect-virt)" == "openvz" ]; then
            openvzErr
        fi
        if [ "$(systemd-detect-virt)" == "lxc" ]; then
            lxcErr
        fi
    fi
}

function checkOS() {
    source /etc/os-release
    OS="${ID}"
    if [[ ${OS} == "debian" || ${OS} == "raspbian" ]]; then
        if [[ ${VERSION_ID} -lt 10 ]]; then
            echo "Your version of Debian (${VERSION_ID}) is not supported. Please use Debian 10 Buster or later"
            exit 1
        fi
        OS=debian # overwrite if raspbian
    elif [[ ${OS} == "ubuntu" ]]; then
        RELEASE_YEAR=$(echo "${VERSION_ID}" | cut -d'.' -f1)
        if [[ ${RELEASE_YEAR} -lt 18 ]]; then
            echo "Your version of Ubuntu (${VERSION_ID}) is not supported. Please use Ubuntu 18.04 or later"
            exit 1
        fi
    elif [[ ${OS} == "fedora" ]]; then
        if [[ ${VERSION_ID} -lt 32 ]]; then
            echo "Your version of Fedora (${VERSION_ID}) is not supported. Please use Fedora 32 or later"
            exit 1
        fi
    elif [[ ${OS} == 'centos' ]] || [[ ${OS} == 'almalinux' ]] || [[ ${OS} == 'rocky' ]]; then
        if [[ ${VERSION_ID} == 7* ]]; then
            echo "Your version of CentOS (${VERSION_ID}) is not supported. Please use CentOS 8 or later"
            exit 1
        fi
    elif [[ -e /etc/oracle-release ]]; then
        source /etc/os-release
        OS=oracle
    elif [[ -e /etc/arch-release ]]; then
        OS=arch
    elif [[ -e /etc/alpine-release ]]; then
        OS=alpine
        if ! command -v virt-what &>/dev/null; then
            apk update && apk add virt-what
        fi
    else
        echo "Looks like you aren't running this installer on a Debian, Ubuntu, Fedora, CentOS, AlmaLinux, Oracle or Arch Linux system"
        exit 1
    fi
}

function getHomeDirForClient() {
    local CLIENT_NAME=$1
    if [ -z "${CLIENT_NAME}" ]; then
        echo "Error: getHomeDirForClient() requires a client name as argument"
        exit 1
    fi
    if [ -e "/home/${CLIENT_NAME}" ]; then
        HOME_DIR="/home/${CLIENT_NAME}"
    elif [ "${SUDO_USER}" ]; then
        if [ "${SUDO_USER}" == "root" ]; then
            HOME_DIR="/root"
        else
            HOME_DIR="/home/${SUDO_USER}"
        fi
    else
        HOME_DIR="/root"
    fi
    echo "$HOME_DIR"
}

function initialCheck() {
    isRoot
    checkOS
    checkVirt
}

function rand_hex() {
    # 生成 1~65535 的随机数，避免全 0
    local val=0
    while [ "$val" -eq 0 ]; do
        val=$(( (RANDOM << 8 | RANDOM) & 0xFFFF ))
    done
    printf "%04x" $val
}

function installQuestions() {
    echo "Starting WireGuard setup automatically..."

    # Detect public IPv4 or IPv6 address
    SERVER_PUB_IP=$(curl -s api.ipify.org || curl -s api.ipify.org)
    if [[ -z ${SERVER_PUB_IP} ]]; then
        SERVER_PUB_IP=$(ip -6 addr | sed -ne 's|^.* inet6 \([^/]*\)/.* scope global.*$|\1|p' | head -1)
    fi
    echo "Detected public IP: ${SERVER_PUB_IP}"

    # Detect public interface
    SERVER_NIC="$(ip -4 route ls | grep default | awk '/dev/ {for (i=1; i<=NF; i++) if ($i == "dev") print $(i+1)}' | head -1)"
    SERVER_PUB_NIC="${SERVER_NIC}"
    echo "Public interface: ${SERVER_PUB_NIC}"

    # Generate WireGuard interface name
    SERVER_WG_NIC="wg$(tr -dc 'a-z0-9' </dev/urandom | head -c4)"
    echo "WireGuard interface name: ${SERVER_WG_NIC}"

    # Generate random IPv4 address
    THIRD=$((RANDOM % 212 + 11))
    FOURTH=$((RANDOM % 212 + 11))
    SERVER_WG_IPV4="10.$THIRD.$FOURTH.1"
    echo "Generated WireGuard IPv4: $SERVER_WG_IPV4"

    # Generate random IPv6 address
    SECOND=$(rand_hex)
    THIRD=$(rand_hex)
    FOURTH=$(rand_hex)
    SERVER_WG_IPV6="fe80:${SECOND}:${THIRD}:${FOURTH}::1"
    echo "Generated WireGuard IPv6: $SERVER_WG_IPV6"

    # Generate random port
    RANDOM_PORT=$(shuf -i49152-65535 -n1)
    SERVER_PORT="${RANDOM_PORT}"
    echo "Selected WireGuard port: ${SERVER_PORT}"

    # Set default DNS
    CLIENT_DNS_1="1.1.1.2"
    CLIENT_DNS_2="1.1.1.3"
    echo "DNS resolvers: ${CLIENT_DNS_1}, ${CLIENT_DNS_2}"

    # Set default AllowedIPs
    ALLOWED_IPS="0.0.0.0/0,::/0"
    echo "Allowed IPs: ${ALLOWED_IPS}"

    echo "Setup parameters configured. Proceeding with installation..."
}

# 其余内容保持不变，略...

# 下面继续原脚本内容
function installWireGuard() {
    installQuestions

    if [[ ${OS} == 'ubuntu' ]] || [[ ${OS} == 'debian' && ${VERSION_ID} -gt 10 ]]; then
        apt-get update
        apt-get install -y wireguard iptables resolvconf qrencode
    elif [[ ${OS} == 'debian' ]]; then
        if ! grep -rqs "^deb .* buster-backports" /etc/apt/; then
            echo "deb http://deb.debian.org/debian buster-backports main" >/etc/apt/sources.list.d/backports.list
            apt-get update
        fi
        apt update
        apt-get install -y iptables resolvconf qrencode
        apt-get install -y -t buster-backports wireguard
    elif [[ ${OS} == 'fedora' ]]; then
        if [[ ${VERSION_ID} -lt 32 ]]; then
            dnf install -y dnf-plugins-core
            dnf copr enable -y jdoss/wireguard
            dnf install -y wireguard-dkms
        fi
        dnf install -y wireguard-tools iptables qrencode
    elif [[ ${OS} == 'centos' ]] || [[ ${OS} == 'almalinux' ]] || [[ ${OS} == 'rocky' ]]; then
        if [[ ${VERSION_ID} == 8* ]]; then
            yum install -y epel-release elrepo-release
            yum install -y kmod-wireguard
            yum install -y qrencode
        fi
        yum install -y wireguard-tools iptables
    elif [[ ${OS} == 'oracle' ]]; then
        dnf install -y oraclelinux-developer-release-el8
        dnf config-manager --disable -y ol8_developer
        dnf config-manager --enable -y ol8_developer_UEKR6
        dnf config-manager --save -y --setopt=ol8_developer_UEKR6.includepkgs='wireguard-tools*'
        dnf install -y wireguard-tools qrencode iptables
    elif [[ ${OS} == 'arch' ]]; then
        pacman -S --needed --noconfirm wireguard-tools qrencode
    elif [[ ${OS} == 'alpine' ]]; then
        apk update
        apk add wireguard-tools iptables build-base libpng-dev
        curl -O https://fukuchi.org/works/qrencode/qrencode-4.1.1.tar.gz
        tar xf qrencode-4.1.1.tar.gz
        (cd qrencode-4.1.1 || exit && ./configure && make && make install && ldconfig)
    fi

    mkdir /etc/wireguard >/dev/null 2>&1
    chmod 600 -R /etc/wireguard/

    SERVER_PRIV_KEY=$(wg genkey)
    SERVER_PUB_KEY=$(echo "${SERVER_PRIV_KEY}" | wg pubkey)

    echo "SERVER_PUB_IP=${SERVER_PUB_IP}
SERVER_PUB_NIC=${SERVER_PUB_NIC}
SERVER_WG_NIC=${SERVER_WG_NIC}
SERVER_WG_IPV4=${SERVER_WG_IPV4}
SERVER_WG_IPV6=${SERVER_WG_IPV6}
SERVER_PORT=${SERVER_PORT}
SERVER_PRIV_KEY=${SERVER_PRIV_KEY}
SERVER_PUB_KEY=${SERVER_PUB_KEY}
CLIENT_DNS_1=${CLIENT_DNS_1}
CLIENT_DNS_2=${CLIENT_DNS_2}
ALLOWED_IPS=${ALLOWED_IPS}" >/etc/wireguard/params

    echo "[Interface]
Address = ${SERVER_WG_IPV4}/24,${SERVER_WG_IPV6}/64
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIV_KEY}" >"/etc/wireguard/${SERVER_WG_NIC}.conf"

    if pgrep firewalld; then
        FIREWALLD_IPV4_ADDRESS=$(echo "${SERVER_WG_IPV4}" | cut -d"." -f1-3)".0"
        FIREWALLD_IPV6_ADDRESS=$(echo "${SERVER_WG_IPV6}" | sed 's/:[^:]*$/:0/')
        echo "PostUp = firewall-cmd --zone=public --add-interface=${SERVER_WG_NIC} && firewall-cmd --add-port ${SERVER_PORT}/udp && firewall-cmd --add-rich-rule='rule family=ipv4 source address=${FIREWALLD_IPV4_ADDRESS} accept' && firewall-cmd --add-rich-rule='rule family=ipv6 source address=${FIREWALLD_IPV6_ADDRESS} accept'
PostDown = firewall-cmd --zone=public --add-interface=${SERVER_WG_NIC} && firewall-cmd --remove-port ${SERVER_PORT}/udp && firewall-cmd --remove-rich-rule='rule family=ipv4 source address=${FIREWALLD_IPV4_ADDRESS} accept' && firewall-cmd --remove-rich-rule='rule family=ipv6 source address=${FIREWALLD_IPV6_ADDRESS} accept'" >>"/etc/wireguard/${SERVER_WG_NIC}.conf"
    else
        echo "PostUp = iptables -I INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT
PostUp = iptables -I FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT
PostUp = iptables -I FORWARD -i ${SERVER_WG_NIC} -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
PostUp = ip6tables -I FORWARD -i ${SERVER_WG_NIC} -j ACCEPT
PostUp = ip6tables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
PostUp = ip6tables -A INPUT -p icmpv6 --icmpv6-type echo-request -j DROP
PostDown = iptables -D INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT
PostDown = iptables -D FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT
PostDown = iptables -D FORWARD -i ${SERVER_WG_NIC} -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
PostDown = ip6tables -D FORWARD -i ${SERVER_WG_NIC} -j ACCEPT
PostDown = ip6tables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
PostDown = ip6tables -D INPUT -p icmpv6 --icmpv6-type echo-request -j DROP" >>"/etc/wireguard/${SERVER_WG_NIC}.conf"
    fi

    echo "net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1" >/etc/sysctl.d/wg.conf

    if [[ ${OS} == 'alpine' ]]; then
        sysctl -p /etc/sysctl.d/wg.conf
        rc-update add sysctl
        ln -s /etc/init.d/wg-quick "/etc/init.d/wg-quick.${SERVER_WG_NIC}"
        rc-service "wg-quick.${SERVER_WG_NIC}" start
        rc-update add "wg-quick.${SERVER_WG_NIC}"
    else
        sysctl --system
        systemctl start "wg-quick@${SERVER_WG_NIC}"
        systemctl enable "wg-quick@${SERVER_WG_NIC}"
    fi

    newClient
    echo -e "${GREEN}WireGuard installation completed!${NC}"

    if [[ ${OS} == 'alpine' ]]; then
        rc-service --quiet "wg-quick.${SERVER_WG_NIC}" status
    else
        systemctl is-active --quiet "wg-quick@${SERVER_WG_NIC}"
    fi
    WG_RUNNING=$?

    if [[ ${WG_RUNNING} -ne 0 ]]; then
        echo -e "\n${RED}WARNING: WireGuard does not seem to be running.${NC}"
        if [[ ${OS} == 'alpine' ]]; then
            echo -e "${ORANGE}Check status with: rc-service wg-quick.${SERVER_WG_NIC} status${NC}"
        else
            echo -e "${ORANGE}Check status with: systemctl status wg-quick@${SERVER_WG_NIC}${NC}"
        fi
        echo -e "${ORANGE}If you see 'Cannot find device ${SERVER_WG_NIC}', please reboot!${NC}"
    else
        echo -e "\n${GREEN}WireGuard is running.${NC}"
        if [[ ${OS} == 'alpine' ]]; then
            echo -e "${GREEN}Check status with: rc-service wg-quick.${SERVER_WG_NIC} status\n${NC}"
        else
            echo -e "${GREEN}Check status with: systemctl status wg-quick@${SERVER_WG_NIC}\n${NC}"
        fi
        echo -e "${ORANGE}If no internet from client, try rebooting the server.${NC}"
    fi
}

# 其余函数如 newClient/revokeClient/listClients/uninstallWg/initialCheck 等与原脚本相同，未做修改。

initialCheck

if [[ -e /etc/wireguard/params ]]; then
    source /etc/wireguard/params
    manageMenu
else
    installWireGuard
fi
