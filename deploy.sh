#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$SCRIPT_DIR/venv"
SERVICE_NAME="email-forwarding"

echo "=== 邮件转发服务部署脚本 ==="

# 1. 创建虚拟环境
if [ ! -d "$VENV_DIR" ]; then
    echo "[1/4] 创建Python虚拟环境..."
    python3 -m venv "$VENV_DIR"
else
    echo "[1/4] 虚拟环境已存在，跳过"
fi

# 2. 安装依赖
echo "[2/4] 安装依赖..."
"$VENV_DIR/bin/pip" install -r "$SCRIPT_DIR/requirements.txt" -q

# 3. 配置.env
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo "[3/4] 创建 .env 配置文件..."
    cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
    echo "请编辑 $SCRIPT_DIR/.env 填入邮箱和飞书Webhook配置"
else
    echo "[3/4] .env 已存在，跳过"
fi

# 4. 安装systemd服务
echo "[4/4] 安装systemd服务..."
sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=Email Forwarding to Feishu
After=network.target

[Service]
Type=simple
WorkingDirectory=$SCRIPT_DIR
ExecStart=$VENV_DIR/bin/python main.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ${SERVICE_NAME}

echo ""
echo "=== 部署完成 ==="
echo "配置文件: $SCRIPT_DIR/.env"
echo ""
echo "启动服务:  sudo systemctl start ${SERVICE_NAME}"
echo "查看日志:  sudo journalctl -u ${SERVICE_NAME} -f"
echo "停止服务:  sudo systemctl stop ${SERVICE_NAME}"
echo ""
echo "请先编辑 .env 文件填入配置，然后运行: sudo systemctl start ${SERVICE_NAME}"
