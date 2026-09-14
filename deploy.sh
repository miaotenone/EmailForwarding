#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$SCRIPT_DIR/venv"
SERVICE_NAME="email-forwarding"
ENV_FILE="$SCRIPT_DIR/.env"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
step()    { echo -e "\n${BOLD}━━━ 步骤 $1 ━━━${NC}"; }

divider() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║     邮件转发至飞书 - 交互式安装向导      ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""
}

# ─── 检测系统 ───
check_system() {
    step "1/6 检测系统环境"

    if ! command -v python3 &>/dev/null; then
        error "未找到 python3，请先安装"
        exit 1
    fi
    PYTHON_VER=$(python3 --version 2>&1)
    success "Python: $PYTHON_VER"

    if ! command -v pip3 &>/dev/null && ! python3 -m pip --version &>/dev/null 2>&1; then
        warn "pip3 未安装，尝试自动安装..."
        sudo apt-get update -qq && sudo apt-get install -y -qq python3-pip python3-venv
    fi
    success "pip: 可用"

    if ! command -v systemctl &>/dev/null; then
        warn "systemctl 不可用，将跳过服务注册（可手动运行）"
        NO_SYSTEMD=1
    else
        success "systemd: 可用"
        NO_SYSTEMD=0
    fi
}

# ─── 创建虚拟环境 ───
setup_venv() {
    step "2/6 配置Python环境"

    if [ -d "$VENV_DIR" ]; then
        warn "虚拟环境已存在: $VENV_DIR"
        read -r -p "是否重建? [y/N] " REBUILD
        if [[ "$REBUILD" =~ ^[Yy]$ ]]; then
            rm -rf "$VENV_DIR"
            python3 -m venv "$VENV_DIR"
            success "虚拟环境已重建"
        else
            success "使用已有虚拟环境"
        fi
    else
        python3 -m venv "$VENV_DIR"
        success "虚拟环境已创建"
    fi

    "$VENV_DIR/bin/pip" install -q -r "$SCRIPT_DIR/requirements.txt"
    success "依赖安装完成"
}

# ─── 收集邮箱配置 ───
configure_email() {
    step "3/6 邮箱配置"

    echo ""
    echo -e "  ${CYAN}支持的邮箱服务器:${NC}"
    echo "    1) QQ邮箱       (imap.qq.com:993)"
    echo "    2) 163邮箱      (imap.163.com:993)"
    echo "    3) 126邮箱      (imap.126.com:993)"
    echo "    4) Gmail        (imap.gmail.com:993)"
    echo "    5) Outlook      (outlook.office365.com:993)"
    echo "    6) 自定义"
    echo ""

    read -r -p "  选择邮箱类型 [1-6]: " EMAIL_TYPE
    case "$EMAIL_TYPE" in
        1) IMAP_HOST="imap.qq.com"; IMAP_PORT="993" ;;
        2) IMAP_HOST="imap.163.com"; IMAP_PORT="993" ;;
        3) IMAP_HOST="imap.126.com"; IMAP_PORT="993" ;;
        4) IMAP_HOST="imap.gmail.com"; IMAP_PORT="993" ;;
        5) IMAP_HOST="outlook.office365.com"; IMAP_PORT="993" ;;
        6)
            read -r -p "  IMAP服务器地址: " IMAP_HOST
            read -r -p "  IMAP端口 [993]: " IMAP_PORT
            IMAP_PORT="${IMAP_PORT:-993}"
            ;;
        *) error "无效选择"; exit 1 ;;
    esac

    read -r -p "  邮箱地址: " EMAIL_ADDR
    read -r -s -p "  邮箱授权码(输入不可见): " EMAIL_PASS
    echo ""

    if [ -z "$EMAIL_ADDR" ] || [ -z "$EMAIL_PASS" ]; then
        error "邮箱地址和授权码不能为空"
        exit 1
    fi

    success "邮箱配置完成"
}

# ─── 收集飞书配置 ───
configure_feishu() {
    step "4/6 飞书机器人配置"

    echo ""
    echo -e "  ${CYAN}获取方式: 飞书群 → 群设置 → 群机器人 → 添加机器人 → 自定义机器人${NC}"
    echo ""

    read -r -p "  Webhook地址: " FEISHU_URL
    if [[ ! "$FEISHU_URL" =~ ^https://open\.feishu\.cn/open-apis/bot/v2/hook/ ]]; then
        warn "Webhook地址格式不太对，继续使用可能导致推送失败"
    fi

    read -r -p "  签名密钥(无则直接回车): " FEISHU_SEC

    if [ -z "$FEISHU_URL" ]; then
        error "Webhook地址不能为空"
        exit 1
    fi

    success "飞书配置完成"
}

# ─── 收集运行参数 ───
configure_runtime() {
    step "5/6 运行参数"

    read -r -p "  轮询间隔(秒) [60]: " POLL_SEC
    POLL_SEC="${POLL_SEC:-60}"

    read -r -p "  垃圾邮件阈值 [0.5]: " SPAM_THR
    SPAM_THR="${SPAM_THR:-0.5}"

    success "运行参数配置完成"
}

# ─── 写入配置文件 ───
write_env() {
    step "6/6 写入配置并安装服务"

    if [ -f "$ENV_FILE" ]; then
        warn ".env 文件已存在"
        read -r -p "  是否覆盖? [y/N] " OVERWRITE
        if [[ ! "$OVERWRITE" =~ ^[Yy]$ ]]; then
            success "保留已有 .env"
            return
        fi
        cp "$ENV_FILE" "${ENV_FILE}.bak"
        info "已备份为 .env.bak"
    fi

    cat > "$ENV_FILE" <<ENVEOF
EMAIL_IMAP_HOST=$IMAP_HOST
EMAIL_IMAP_PORT=$IMAP_PORT
EMAIL_ADDRESS=$EMAIL_ADDR
EMAIL_PASSWORD=$EMAIL_PASS
FEISHU_WEBHOOK_URL=$FEISHU_URL
FEISHU_SECRET=$FEISHU_SEC
POLL_INTERVAL=$POLL_SEC
SPAM_THRESHOLD=$SPAM_THR
ENVEOF

    chmod 600 "$ENV_FILE"
    success ".env 配置文件已写入 (权限 600)"
}

# ─── 注册systemd服务 ───
install_service() {
    if [ "$NO_SYSTEMD" = "1" ]; then
        warn "跳过systemd服务注册"
        return
    fi

    sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null <<SVCEOF
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
SVCEOF

    sudo systemctl daemon-reload
    sudo systemctl enable ${SERVICE_NAME} -q
    success "systemd 服务已注册"
}

# ─── 测试连接 ───
test_connection() {
    echo ""
    read -r -p "  是否现在测试邮箱连接? [Y/n] " DO_TEST
    if [[ "$DO_TEST" =~ ^[Nn]$ ]]; then
        return
    fi

    info "正在测试IMAP连接..."
    TEST_OUTPUT=$("$VENV_DIR/bin/python" -c "
import imaplib
try:
    m = imaplib.IMAP4_SSL('$IMAP_HOST', int('$IMAP_PORT'))
    m.login('$EMAIL_ADDR', '$EMAIL_PASS')
    m.select('INBOX')
    _, data = m.search(None, 'UNSEEN')
    count = len(data[0].split()) if data[0] else 0
    m.close()
    m.logout()
    print(f'连接成功! 收件箱未读邮件: {count} 封')
except Exception as e:
    print(f'连接失败: {e}')
    exit(1)
" 2>&1) && {
        success "$TEST_OUTPUT"
    } || {
        warn "$TEST_OUTPUT"
        echo ""
        warn "连接失败不影响安装，可稍后排查"
    }
}

# ─── 最终提示 ───
print_summary() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║              安装完成!                    ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  配置文件:  ${CYAN}$ENV_FILE${NC}"
    echo -e "  虚拟环境:  ${CYAN}$VENV_DIR${NC}"
    echo ""
    echo -e "  ${BOLD}常用命令:${NC}"
    echo "    启动服务:  sudo systemctl start $SERVICE_NAME"
    echo "    停止服务:  sudo systemctl stop $SERVICE_NAME"
    echo "    查看状态:  sudo systemctl status $SERVICE_NAME"
    echo "    实时日志:  sudo journalctl -u $SERVICE_NAME -f"
    echo "    重启服务:  sudo systemctl restart $SERVICE_NAME"
    echo ""
    echo -e "  ${BOLD}手动运行(不安装服务):${NC}"
    echo "    $VENV_DIR/bin/python $SCRIPT_DIR/main.py"
    echo ""

    read -r -p "  是否现在启动服务? [Y/n] " DO_START
    if [[ ! "$DO_START" =~ ^[Nn]$ ]]; then
        sudo systemctl start "$SERVICE_NAME"
        sleep 2
        if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
            success "服务已启动并运行中"
        else
            warn "服务启动异常，请检查日志: sudo journalctl -u $SERVICE_NAME -n 20"
        fi
    fi
}

# ─── 主流程 ───
main() {
    divider
    check_system
    setup_venv
    configure_email
    configure_feishu
    configure_runtime
    write_env
    install_service
    test_connection
    print_summary
}

main "$@"
