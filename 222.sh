#!/bin/bash

# 定义变量
SERVICE_NAME="ore-pool.service"
USER_NAME="root"
WORKING_DIR="/home"  # 请替换为ore-pool-cli的实际目录
EXEC_START="$WORKING_DIR/ore-pool-cli-v1.1.0 mine --address 61k1qonXeoxfMf89a9e2qHLjLgwrvrwse4f9JqJScH8Y --server ws://103.148.58.194:8989/"
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"

# 创建服务文件
echo "Creating systemd service file at $SERVICE_PATH..."
sudo bash -c "cat > $SERVICE_PATH" <<EOL
[Unit]
Description=Ore Pool CLI Miner
After=network.target

[Service]
# 设置用户和工作目录
User=$USER_NAME
WorkingDirectory=$WORKING_DIR

# 可执行命令
ExecStart=$EXEC_START

# 保证服务自动重启
Restart=always
RestartSec=5

# 日志配置
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOL

# 刷新 systemd 服务
echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

# 启用并启动服务
echo "Enabling and starting the $SERVICE_NAME service..."
sudo systemctl enable $SERVICE_NAME
sudo systemctl start $SERVICE_NAME

# 检查服务状态
echo "Checking service status..."
sudo systemctl status $SERVICE_NAME

echo "Service $SERVICE_NAME has been created, enabled, and started successfully."
