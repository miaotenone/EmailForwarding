import os
import json
from dotenv import load_dotenv

load_dotenv()

ACCOUNTS_FILE = os.path.join(os.path.dirname(__file__), "accounts.json")


class Account:
    def __init__(self, data):
        self.name = data.get("name", data.get("email", "unknown"))
        self.imap_host = data["imap_host"]
        self.imap_port = int(data.get("imap_port", 993))
        self.email = data["email"]
        self.password = data["password"]
        self.spam_threshold = float(data.get("spam_threshold", 0.5))


class Config:
    FEISHU_WEBHOOK_URL = os.getenv("FEISHU_WEBHOOK_URL", "")
    FEISHU_SECRET = os.getenv("FEISHU_SECRET", "")
    POLL_INTERVAL = int(os.getenv("POLL_INTERVAL", "60"))

    BLACKLIST_SENDERS = [
        "spam@example.com",
        "noreply@advertisement.com",
    ]

    SPAM_KEYWORDS = [
        "退订", "取消订阅", "中奖", "免费领取", "贷款", "低息",
        "点击领取", "限时优惠", "恭喜您", "中签", "开户送",
        "viagra", "casino", "lottery", "winner", "congratulations",
        "free money", "act now", "limited time", "click here",
        "unsubscribe", "opt out", "earn money", "make money fast",
    ]

    @staticmethod
    def load_accounts():
        if not os.path.exists(ACCOUNTS_FILE):
            raise FileNotFoundError(
                f"账号配置文件不存在: {ACCOUNTS_FILE}\n"
                f"请复制 accounts.json.example 为 accounts.json 并填入配置"
            )
        with open(ACCOUNTS_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        return [Account(item) for item in data]
