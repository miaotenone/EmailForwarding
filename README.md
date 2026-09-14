# EmailForwarding

邮件转发服务：通过IMAP读取多个邮箱的未读邮件，过滤垃圾邮件后推送至飞书群。

## 快速开始

```bash
chmod +x deploy.sh
./deploy.sh
```

交互式向导会引导你完成：系统检测 → 依赖安装 → 多账号配置 → 飞书配置 → 服务注册。

## 配置说明

### `.env` — 全局配置

| 变量 | 说明 | 示例 |
|------|------|------|
| `FEISHU_WEBHOOK_URL` | 飞书机器人Webhook地址 | `https://open.feishu.cn/open-apis/bot/v2/hook/xxxx` |
| `FEISHU_SECRET` | 飞书签名密钥（可留空） | `your_secret` |
| `POLL_INTERVAL` | 轮询间隔（秒） | `60` |

### `accounts.json` — 邮箱账号列表

支持同时监控多个邮箱，每个账号可独立设置垃圾邮件阈值：

```json
[
  {
    "name": "QQ工作邮箱",
    "imap_host": "imap.qq.com",
    "imap_port": 993,
    "email": "your_email@qq.com",
    "password": "your_app_password",
    "spam_threshold": 0.5
  },
  {
    "name": "163私人邮箱",
    "imap_host": "imap.163.com",
    "imap_port": 993,
    "email": "your_email@163.com",
    "password": "your_app_password",
    "spam_threshold": 0.5
  }
]
```

### 获取邮箱授权码

- **QQ邮箱**: 设置 → 账户 → POP3/SMTP服务 → 开启 → 生成授权码
- **163邮箱**: 设置 → POP3/SMTP → 开启 → 生成授权码
- **Gmail**: Google账户 → 安全性 → 两步验证 → 应用专用密码

### 获取飞书Webhook

1. 飞书创建群组 → 群设置 → 群机器人 → 添加机器人
2. 选择「自定义机器人」→ 复制Webhook地址
3. （可选）开启签名校验 → 复制密钥

## 服务管理

```bash
sudo systemctl start email-forwarding     # 启动
sudo systemctl stop email-forwarding      # 停止
sudo systemctl restart email-forwarding   # 重启
sudo systemctl status email-forwarding    # 状态
sudo journalctl -u email-forwarding -f    # 实时日志
```

## 垃圾邮件过滤

采用多层过滤策略：

1. **发件人黑名单** — 在 `config.py` 的 `BLACKLIST_SENDERS` 中配置
2. **关键词匹配** — 匹配中英文广告关键词，按命中数累计分数
3. **阈值判定** — 命中分数超过阈值（默认0.5）则判定为垃圾邮件

每个账号可独立设置阈值（`spam_threshold`），垃圾邮件推送至飞书时标题前会标注 `[垃圾邮件 xx%]`。

## 项目结构

```
EmailForwarding/
├── config.py              # 配置管理（多账号加载）
├── email_reader.py        # IMAP邮件读取
├── spam_filter.py         # 垃圾邮件过滤
├── feishu_bot.py          # 飞书Webhook推送
├── main.py                # 主程序入口（并发处理多账号）
├── deploy.sh              # 交互式部署脚本
├── requirements.txt       # Python依赖
├── accounts.json.example  # 邮箱账号模板
├── .env.example           # 全局配置模板
└── .gitignore
```

## 手动运行

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
cp accounts.json.example accounts.json
# 编辑 .env 和 accounts.json
python main.py
```
