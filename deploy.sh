#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$SCRIPT_DIR/venv"
SERVICE_NAME="email-forwarding"
ENV_FILE="$SCRIPT_DIR/.env"
ACCOUNTS_FILE="$SCRIPT_DIR/accounts.json"

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
    echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║   邮件转发至飞书 - 多账号交互式安装向导      ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
    echo ""
}

# ─── JSON 辅助（纯 bash，无 jq 依赖）───
json_array_start() { ACC_JSON="["; }
json_array_end()   { ACC_JSON="${ACC_JSON%,}]"; }
json_add_item() {
    local name="$1" host="$2" port="$3" email="$4" pass="$5" threshold="$6"
    ACC_JSON="${ACC_JSON}{\"name\":\"$name\",\"imap_host\":\"$host\",\"imap_port\":$port,\"email\":\"$email\",\"password\":\"$pass\",\"spam_threshold\":$threshold},"
}

# ─── 检测系统 ───
check_system() {
    step "1/7 检测系统环境"

    if ! command -v python3 &>/dev/null; then
        error "未找到 python3，请先安装"
        exit 1
    fi
    success "Python: $(python3 --version 2>&1)"

    # 获取Python主版本号用于安装对应venv包
    PY_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")

    # 确保 python3-venv 已安装
    if ! python3 -m venv --help &>/dev/null 2>&1; then
        warn "python3-venv 未安装，尝试自动安装..."
        sudo apt-get update -qq
        sudo apt-get install -y -qq "python${PY_VER}-venv" python3-venv python3-pip
    fi
    success "python3-venv: 可用"

    if ! command -v pip3 &>/dev/null && ! python3 -m pip --version &>/dev/null 2>&1; then
        warn "pip3 未安装，尝试自动安装..."
        sudo apt-get update -qq && sudo apt-get install -y -qq python3-pip
    fi
    success "pip: 可用"

    NO_SYSTEMD=0
    if ! command -v systemctl &>/dev/null; then
        warn "systemctl 不可用，将跳过服务注册"
        NO_SYSTEMD=1
    else
        success "systemd: 可用"
    fi
}

# ─── 安装系统依赖 ───
install_system_deps() {
    step "2/7 安装系统依赖"

    PY_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")

    # 检测是否为root
    SUDO=""
    if [ "$(id -u)" -ne 0 ]; then
        SUDO="sudo"
    fi

    info "检测到 Python $PY_VER，正在安装依赖..."

    # 尝试多种包名（兼容不同发行版）
    $SUDO apt-get update -qq 2>/dev/null || true

    INSTALLED=0
    for pkg in "python${PY_VER}-venv" "python3-venv" "python${PY_VER}-full"; do
        if apt-cache show "$pkg" &>/dev/null 2>&1; then
            $SUDO apt-get install -y -qq "$pkg" 2>/dev/null && INSTALLED=1 && break
        fi
    done

    # 安装pip（备用）
    $SUDO apt-get install -y -qq python3-pip 2>/dev/null || true

    # 验证venv可用
    if ! python3 -m venv --help &>/dev/null 2>&1; then
        error "python3-venv 安装失败，请手动执行:"
        error "  sudo apt install python${PY_VER}-venv"
        exit 1
    fi

    success "系统依赖安装完成"
}

# ─── 创建虚拟环境 ───
setup_venv() {
    step "3/7 配置Python环境"

    if [ -d "$VENV_DIR" ]; then
        if [ -f "$VENV_DIR/bin/python3" ]; then
            warn "虚拟环境已存在"
            read -r -p "  是否重建? [y/N] " REBUILD
            if [[ ! "$REBUILD" =~ ^[Yy]$ ]]; then
                if [ -f "$VENV_DIR/bin/pip" ]; then
                    "$VENV_DIR/bin/pip" install -q -r "$SCRIPT_DIR/requirements.txt"
                else
                    warn "pip 不可用，尝试修复虚拟环境..."
                    "$VENV_DIR/bin/python3" -m ensurepip --upgrade 2>/dev/null || {
                        warn "ensurepip 失败，使用 get-pip.py 安装..."
                        curl -sS https://bootstrap.pypa.io/get-pip.py | "$VENV_DIR/bin/python3"
                    }
                    "$VENV_DIR/bin/pip" install -q -r "$SCRIPT_DIR/requirements.txt"
                fi
                success "依赖安装完成"
                return
            fi
        fi
        rm -rf "$VENV_DIR"
    fi

    python3 -m venv "$VENV_DIR" || {
        warn "虚拟环境创建时 ensurepip 失败，尝试继续..."
    }
    success "虚拟环境已创建"

    if [ ! -f "$VENV_DIR/bin/pip" ]; then
        warn "pip 未随虚拟环境安装，尝试修复..."
        "$VENV_DIR/bin/python3" -m ensurepip --upgrade 2>/dev/null || {
            warn "ensurepip 失败，使用 get-pip.py 安装..."
            curl -sS https://bootstrap.pypa.io/get-pip.py | "$VENV_DIR/bin/python3"
        }
    fi

    "$VENV_DIR/bin/pip" install -q -r "$SCRIPT_DIR/requirements.txt"
    success "依赖安装完成"
}

# ─── 添加邮箱账号 ───
add_account() {
    local index="$1"
    echo ""
    echo -e "${BOLD}── 账号 $index ──${NC}"
    echo -e "  ${CYAN}邮箱类型:${NC}"
    echo "    1) QQ邮箱       (imap.qq.com:993)"
    echo "    2) 163邮箱      (imap.163.com:993)"
    echo "    3) 126邮箱      (imap.126.com:993)"
    echo "    4) Gmail        (imap.gmail.com:993)"
    echo "    5) Outlook      (outlook.office365.com:993)"
    echo "    6) 自定义"
    echo ""

    read -r -p "  选择 [1-6]: " TYPE
    case "$TYPE" in
        1) HOST="imap.qq.com"; PORT="993" ;;
        2) HOST="imap.163.com"; PORT="993" ;;
        3) HOST="imap.126.com"; PORT="993" ;;
        4) HOST="imap.gmail.com"; PORT="993" ;;
        5) HOST="outlook.office365.com"; PORT="993" ;;
        6)
            read -r -p "  IMAP服务器: " HOST
            read -r -p "  端口 [993]: " PORT
            PORT="${PORT:-993}"
            ;;
        *) error "无效选择"; return 1 ;;
    esac

    read -r -p "  账号名称(如'工作邮箱') [邮箱地址]: " NAME
    read -r -p "  邮箱地址: " EMAIL
    read -r -s -p "  授权码(输入不可见): " PASS
    echo ""
    read -r -p "  垃圾邮件阈值 [0.5]: " THRESHOLD
    THRESHOLD="${THRESHOLD:-0.5}"
    NAME="${NAME:-$EMAIL}"

    if [ -z "$EMAIL" ] || [ -z "$PASS" ]; then
        error "邮箱地址和授权码不能为空"
        return 1
    fi

    json_add_item "$NAME" "$HOST" "$PORT" "$EMAIL" "$PASS" "$THRESHOLD"
    success "账号 [$NAME] 已添加"
    return 0
}

# ─── 多账号配置 ───
configure_accounts() {
    step "4/8 邮箱账号配置"
    echo ""
    echo -e "  ${CYAN}支持同时监控多个邮箱账号，每个账号都会独立读取并推送。${NC}"
    echo ""

    json_array_start

    local count=0
    while true; do
        count=$((count + 1))
        add_account "$count" || { count=$((count - 1)); continue; }

        echo ""
        read -r -p "  继续添加账号? [y/N] " MORE
        if [[ ! "$MORE" =~ ^[Yy]$ ]]; then
            break
        fi
    done

    json_array_end

    if [ "$count" -eq 0 ]; then
        error "至少需要添加一个邮箱账号"
        exit 1
    fi

    success "共配置 $count 个邮箱账号"
}

# ─── 飞书配置 ───
configure_feishu() {
    step "5/8 飞书机器人配置"

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

# ─── 运行参数 ───
configure_runtime() {
    step "6/8 运行参数"

    read -r -p "  轮询间隔(秒) [60]: " POLL_SEC
    POLL_SEC="${POLL_SEC:-60}"

    success "运行参数配置完成"
}

# ─── 写入文件 ───
write_files() {
    step "7/8 写入配置文件"

    # .env
    if [ -f "$ENV_FILE" ]; then
        warn ".env 已存在"
        read -r -p "  是否覆盖? [y/N] " OW
        if [[ "$OW" =~ ^[Yy]$ ]]; then
            cp "$ENV_FILE" "${ENV_FILE}.bak"
            info "已备份为 .env.bak"
        else
            info "保留已有 .env"
            # 更新 FEISHU 配置
            sed -i "s|^FEISHU_WEBHOOK_URL=.*|FEISHU_WEBHOOK_URL=$FEISHU_URL|" "$ENV_FILE"
            sed -i "s|^FEISHU_SECRET=.*|FEISHU_SECRET=$FEISHU_SEC|" "$ENV_FILE"
            sed -i "s|^POLL_INTERVAL=.*|POLL_INTERVAL=$POLL_SEC|" "$ENV_FILE"
            success ".env 已更新"
            return
        fi
    fi

    cat > "$ENV_FILE" <<ENVEOF
FEISHU_WEBHOOK_URL=$FEISHU_URL
FEISHU_SECRET=$FEISHU_SEC
POLL_INTERVAL=$POLL_SEC
ENVEOF

    chmod 600 "$ENV_FILE"
    success ".env 已写入 (权限 600)"

    # accounts.json
    echo "$ACC_JSON" > "$ACCOUNTS_FILE"
    chmod 600 "$ACCOUNTS_FILE"
    success "accounts.json 已写入 (权限 600)"
}

# ─── 注册 systemd ───
install_service() {
    if [ "$NO_SYSTEMD" = "1" ]; then
        return
    fi

    step "8/8 注册系统服务"

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
    read -r -p "  是否测试所有邮箱连接? [Y/n] " DO_TEST
    if [[ "$DO_TEST" =~ ^[Nn]$ ]]; then
        return
    fi

    info "正在逐个测试IMAP连接..."
    "$VENV_DIR/bin/python" -c "
import json, imaplib
with open('$ACCOUNTS_FILE') as f:
    accounts = json.load(f)
ok = 0
for acc in accounts:
    name = acc.get('name', acc['email'])
    try:
        m = imaplib.IMAP4_SSL(acc['imap_host'], int(acc.get('imap_port', 993)))
        m.login(acc['email'], acc['password'])
        m.select('INBOX')
        _, data = m.search(None, 'UNSEEN')
        count = len(data[0].split()) if data[0] else 0
        m.close()
        m.logout()
        print(f'  ✓ {name} ({acc[\"email\"]})  未读: {count} 封')
        ok += 1
    except Exception as e:
        print(f'  ✗ {name} ({acc[\"email\"]})  失败: {e}')
print(f'\n测试完成: {ok}/{len(accounts)} 个账号连接成功')
" 2>&1 || warn "测试脚本执行异常"
}

# ─── 最终提示 ───
print_summary() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║               安装完成!                       ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  配置文件:"
    echo -e "    ${CYAN}$ENV_FILE${NC}        (飞书/轮询配置)"
    echo -e "    ${CYAN}$ACCOUNTS_FILE${NC}   (邮箱账号列表)"
    echo ""
    echo -e "  ${BOLD}常用命令:${NC}"
    echo "    启动:  sudo systemctl start $SERVICE_NAME"
    echo "    停止:  sudo systemctl stop $SERVICE_NAME"
    echo "    状态:  sudo systemctl status $SERVICE_NAME"
    echo "    日志:  sudo journalctl -u $SERVICE_NAME -f"
    echo "    重启:  sudo systemctl restart $SERVICE_NAME"
    echo ""
    echo -e "  ${BOLD}手动运行:${NC}"
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
    install_system_deps
    setup_venv
    configure_accounts
    configure_feishu
    configure_runtime
    write_files
    install_service
    test_connection
    print_summary
}

main "$@"
