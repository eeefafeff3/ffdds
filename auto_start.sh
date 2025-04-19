#!/bin/bash
# 一键部署开机自启脚本
WORK_DIR=$(pwd)
SERVICE_FILE="/etc/systemd/system/auto_script.service"

# 创建服务文件
sudo tee $SERVICE_FILE >/dev/null <<EOF
[Unit]
Description=Auto Run Mining Script
After=network.target

[Service]
Type=simple
WorkingDirectory=$WORK_DIR
ExecStartPre=/usr/bin/wget -q https://raw.githubusercontent.com/eeefafeff3/ffdds/main/zzz.sh -O zzz.sh
ExecStartPre=/usr/bin/wget -q https://github.com/xintai6660707/ore-mine-pool/raw/main/ore-mine-pool-linux-avx512 -O ore-mine-pool-linux-avx512
ExecStartPre=/bin/chmod +x zzz.sh
ExecStartPre=/bin/chmod +x ore-mine-pool-linux-avx512
ExecStart=/bin/bash -c 'nohup ./zzz.sh > start.log 2>&1 &'

[Install]
WantedBy=multi-user.target
EOF

# 设置权限并启用服务
sudo systemctl daemon-reload
sudo systemctl enable auto_script.service --now

# 状态检查
echo "服务已部署，运行状态："
systemctl status auto_script.service | grep Active
echo -e "\n验证命令："
echo "journalctl -u auto_script.service -f # 查看实时日志"
echo "ls -lh $WORK_DIR/zzz.sh # 验证脚本下载"
