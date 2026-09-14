import signal
import sys
import time
import logging

from config import Config
from email_reader import fetch_unseen
from spam_filter import is_spam
from feishu_bot import send_to_feishu

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler()],
)
log = logging.getLogger(__name__)

running = True


def _shutdown(sig, frame):
    global running
    log.info("收到退出信号，正在停止...")
    running = False


signal.signal(signal.SIGINT, _shutdown)
signal.signal(signal.SIGTERM, _shutdown)


def process_once():
    if not Config.EMAIL_ADDRESS or not Config.FEISHU_WEBHOOK_URL:
        log.error("邮箱或飞书Webhook未配置，请检查 .env 文件")
        return

    try:
        messages = fetch_unseen(
            Config.EMAIL_IMAP_HOST,
            Config.EMAIL_IMAP_PORT,
            Config.EMAIL_ADDRESS,
            Config.EMAIL_PASSWORD,
        )
    except Exception as e:
        log.error("读取邮件失败: %s", e)
        return

    if not messages:
        log.debug("无新邮件")
        return

    log.info("发现 %d 封未读邮件", len(messages))

    for msg in messages:
        spam, score = is_spam(msg)
        label = "垃圾邮件" if spam else "正常"
        log.info("[%s %.0f%%] %s <- %s", label, score * 100, msg.subject, msg.sender)

        ok = send_to_feishu(
            Config.FEISHU_WEBHOOK_URL,
            Config.FEISHU_SECRET,
            msg,
            spam,
            score,
        )
        if ok:
            log.info("已推送至飞书: %s", msg.subject)
        else:
            log.error("推送飞书失败: %s", msg.subject)


def main():
    log.info("邮件转发服务启动")
    log.info("邮箱: %s | 轮询间隔: %ds", Config.EMAIL_ADDRESS, Config.POLL_INTERVAL)

    while running:
        process_once()
        for _ in range(Config.POLL_INTERVAL):
            if not running:
                break
            time.sleep(1)

    log.info("服务已停止")


if __name__ == "__main__":
    main()
