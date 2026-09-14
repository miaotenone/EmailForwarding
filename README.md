# EmailForwarding

邮件转发服务：通过IMAP读取邮箱中的未读邮件，过滤垃圾邮件后推送至飞书群。

## 快速开始

```bash
# 部署
chmod +x deploy.sh
./deploy.sh

# 编辑配置
vim .env

# 启动
sudo systemctl start email-forwarding
```

## 配置说明

复制 `.env.example` 为 `.env` 并填写：

| 变量 | 说明 | 示例 |
|------|------|------|
| `EMAIL_IMAP_HOST` | IMAP服务器地址 | `imap.qq.com` |
| `EMAIL_IMAP_PORT` | IMAP端口 | `993` |
| `EMAIL_ADDRESS` | 邮箱地址 | `user@qq.com` |
| `EMAIL_PASSWORD` | 邮箱授权码（非登录密码） | `abcdefghijklmnop` |
| `FEISHU_WEBHOOK_URL` | 飞书机器人Webhook地址 | `https://open.feishu.cn/open-apis/bot/v2/hook/xxxx` |
| `FEISHU_SECRET` | 飞书签名密钥（可留空） | `your_secret` |
| `POLL_INTERVAL` | 轮询间隔（秒） | `60` |
| `SPAM_THRESHOLD` | 垃圾邮件判定阈值 | `0.5` |

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
3. **阈值判定** — 命中分数超过 `SPAM_THRESHOLD`（默认0.5）则判定为垃圾邮件

垃圾邮件和正常邮件都会推送至飞书，垃圾邮件标题前会标注 `[垃圾邮件 xx%]`。

## 项目结构

```
EmailForwarding/
├── config.py          # 配置管理
├── email_reader.py    # IMAP邮件读取
├── spam_filter.py     # 垃圾邮件过滤
├── feishu_bot.py      # 飞书Webhook推送
├── main.py            # 主程序入口
├── deploy.sh          # 一键部署脚本
├── requirements.txt   # Python依赖
├── .env.example       # 环境变量模板
└── .gitignore
```

## 手动运行

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
vim .env
python main.py
```
