import os
from dotenv import load_dotenv

load_dotenv()


class Config:
    EMAIL_IMAP_HOST = os.getenv("EMAIL_IMAP_HOST", "imap.qq.com")
    EMAIL_IMAP_PORT = int(os.getenv("EMAIL_IMAP_PORT", "993"))
    EMAIL_ADDRESS = os.getenv("EMAIL_ADDRESS", "")
    EMAIL_PASSWORD = os.getenv("EMAIL_PASSWORD", "")

    FEISHU_WEBHOOK_URL = os.getenv("FEISHU_WEBHOOK_URL", "")
    FEISHU_SECRET = os.getenv("FEISHU_SECRET", "")

    POLL_INTERVAL = int(os.getenv("POLL_INTERVAL", "60"))
    SPAM_THRESHOLD = float(os.getenv("SPAM_THRESHOLD", "0.5"))

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
