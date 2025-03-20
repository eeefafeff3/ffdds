#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 权限运行此脚本（使用 sudo）"
  exit 1
fi

# 更新系统并安装依赖
echo "正在更新系统和安装依赖..."
apt update && apt upgrade -y
apt install -y dante-server

# 设置 SOCKS5 配置参数
SOCKS_PORT=19888
SOCKS_USER="wfwf"  # 自定义用户名
SOCKS_PASS="wfwf"  # 自定义密码（请修改为强密码）

# 创建 Dante 配置文件
echo "正在配置 Dante SOCKS5 服务器..."
cat > /etc/danted.conf <<EOF
# 日志输出
logoutput: /var/log/danted.log

# 绑定地址和端口
internal: 0.0.0.0 port = $SOCKS_PORT
external: 0.0.0.0

# SOCKS5 方法：用户名/密码认证
socksmethod: username

# 客户端连接规则
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error connect disconnect
}

# SOCKS5 流量规则
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: error connect disconnect
    socksmethod: username
}
EOF

# 创建用户认证文件
echo "正在设置用户认证..."
echo "$SOCKS_USER:$SOCKS_PASS" > /etc/danted.passwd
chmod 600 /etc/danted.passwd
chown nobody:nogroup /etc/danted.passwd

# 启动并启用 Dante 服务
echo "正在启动 SOCKS5 服务..."
systemctl restart danted
systemctl enable danted

# 检查服务状态
if systemctl is-active danted >/dev/null; then
  echo "SOCKS5 代理已成功启动！"
  echo "代理地址: $(curl -s ifconfig.me):$SOCKS_PORT"
  echo "用户名: $SOCKS_USER"
  echo "密码: $SOCKS_PASS"
else
  echo "启动失败，请检查 /var/log/danted.log 获取错误信息"
  exit 1
fi

# 防火墙配置（如果使用 ufw）
if command -v ufw >/dev/null; then
  echo "配置防火墙，开放 $SOCKS_PORT 端口..."
  ufw allow $SOCKS_PORT/tcp
  ufw allow $SOCKS_PORT/udp
  ufw status
fi

# 提示客户端配置建议
echo "-----------------------------------"
echo "客户端配置建议："
echo "1. 在 Firefox 中设置 SOCKS5 代理："
echo "   - 地址: $(curl -s ifconfig.me)"
echo "   - 端口: $SOCKS_PORT"
echo "   - 勾选 '通过代理进行 DNS 查询'"
echo "2. 使用强密码并定期更换。"
echo "3. 测试代理：访问 https://httpbin.org/headers 检查头信息。"
echo "-----------------------------------"
