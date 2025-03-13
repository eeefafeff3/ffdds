#!/bin/bash

wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared-linux-amd64
mv cloudflared-linux-amd64 /usr/local/bin/cloudflared
mkdir /etc/cloudflared

dns=("https://1.1.1.1/dns-query" "https://1.0.0.1/dns-query" "https://dns.google/dns-query" "https://cloudflare-dns.com/dns-query" "https://dns.cloudflare.com/dns-query" "https://dns.quad9.net/dns-query" "https://dns9.quad9.net/dns-query" "https://doh.dns.sb/dns-query" "https://doh.sb/dns-query" "https://dns.sb/dns-query" "https://doh.opendns.com/dns-query" "https://dns.opendns.com/dns-query" "https://doh.umbrella.com/dns-query" "https://dns.umbrella.com/dns-query" "https://dns.sse.cisco.com/dns-query" "https://familyshield.opendns.com/dns-query" "https://doh.familyshield.opendns.com/dns-query" "https://familyshield.sse.cisco.com/dns-query" )
index1=$((RANDOM % 18))
index2=$((RANDOM % 18))

echo "
proxy-dns: true
proxy-dns-upstream:
  - ${dns[$index1]}
  - ${dns[$index2]}
"> /etc/cloudflared/config.yml

echo '
[Unit]
Description=cloudflared DNS over HTTPS 代理
After=syslog.target network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/cloudflared proxy-dns
Restart=on-failure
RestartSec=10
KillMode=process

[Install]
WantedBy=multi-user.target
' > /etc/systemd/system/cloudflared.service


systemctl restart cloudflared

systemctl enable cloudflared

echo 'nameserver 127.0.0.1' > /etc/resolv.conf 
chattr +i /etc/resolv.conf 
bash <(wget -qO- -o- https://git.io/v2ray.sh)
v2ray del

# 创建新的配置文件
cat << EOF | tee /etc/v2ray/conf/Socks-29999.json
{
  "inbounds": [
    {
      "tag": "Socks-29999.json",
      "port": 29999,
      "listen": "0.0.0.0",
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true,
        "ip": "0.0.0.0"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls"
        ]
      }
    }
  ]
}
EOF

v2ray restart 
