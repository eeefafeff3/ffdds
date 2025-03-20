#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 权限运行此脚本（使用 sudo）"
  exit 1
fi

# 更新系统并安装依赖
echo "正在更新系统和安装依赖..."
apt update && apt upgrade -y
if ! apt install -y dante-server; then
  echo "安装 dante-server 失败，请检查网络或软件源"
  exit 1
fi

# 设置 SOCKS5 配置参数
SOCKS_PORT=28779

# 创建 Dante 配置文件（无密码模式）
echo "正在配置 Dante SOCKS5 服务器..."
cat > /etc/danted.conf <<EOF
# 日志输出
logoutput: /var/log/danted.log

# 绑定地址和端口
internal: 0.0.0.0 port = $SOCKS_PORT
external: 0.0.0.0

# SOCKS5 方法：无需认证
socksmethod: none

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
    socksmethod: none
}
EOF

# 确保日志文件存在并设置权限
echo "确保日志文件权限..."
touch /var/log/danted.log
chown nobody:nogroup /var/log/danted.log
chmod 644 /var/log/danted.log

# 启动并启用 Dante 服务
echo "正在启动 SOCKS5 服务..."
if ! systemctl restart danted; then
  echo "重启 danted 服务失败，查看详情："
  systemctl status danted
  exit 1
fi
if ! systemctl enable danted; then
  echo "启用 danted 服务失败，查看详情："
  systemctl status danted
  exit 1
fi

# 检查服务状态
if systemctl is-active danted >/dev/null; then
  # 获取 EC2 公网 IP
  PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
  if [ -z "$PUBLIC_IP" ]; then
    echo "无法获取公网 IP，请检查网络或手动指定"
    PUBLIC_IP="你的服务器IP"
  fi
  echo "SOCKS5 代理已成功启动！"
  echo "代理地址: $PUBLIC_IP:$SOCKS_PORT"
  echo "无需用户名和密码，直接连接即可"
else
  echo "启动失败，请检查 /var/log/danted.log 获取错误信息"
  cat /var/log/danted.log
  exit 1
fi

# 检查并提示 AWS 安全组配置
echo "-----------------------------------"
echo "AWS EC2 注意事项："
echo "请确保在 AWS 控制台的安全组中开放端口 $SOCKS_PORT："
echo "1. 进入 EC2 实例的安全组设置"
echo "2. 添加规则：类型 '自定义 TCP'，端口 $SOCKS_PORT，来源 '0.0.0.0/0'（或指定 IP）"
echo "-----------------------------------"

# 客户端配置建议
echo "客户端配置建议："
echo "1. 在 Firefox 中设置 SOCKS5 代理："
echo "   - 地址: $PUBLIC_IP"
echo "   - 端口: $SOCKS_PORT"
echo "   - 勾选 '通过代理进行 DNS 查询'"
echo "2. 测试代理：访问 https://httpbin.org/headers 检查头信息。"
echo "-----------------------------------"
