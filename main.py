import signal
import sys
import time
import logging
from concurrent.futures import ThreadPoolExecutor, as_completed

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


def process_account(account):
    try:
        messages = fetch_unseen(
            account.imap_host,
            account.imap_port,
            account.email,
            account.password,
        )
    except Exception as e:
        log.error("[%s] 读取邮件失败: %s", account.name, e)
        return

    if not messages:
        log.debug("[%s] 无新邮件", account.name)
        return

    log.info("[%s] 发现 %d 封未读邮件", account.name, len(messages))

    for msg in messages:
        spam, score = is_spam(msg, account.spam_threshold)
        label = "垃圾邮件" if spam else "正常"
        log.info("[%s] [%s %.0f%%] %s <- %s",
                 account.name, label, score * 100, msg.subject, msg.sender)

        ok = send_to_feishu(
            Config.FEISHU_WEBHOOK_URL,
            Config.FEISHU_SECRET,
            msg,
            spam,
            score,
            account_name=account.name,
        )
        if ok:
            log.info("[%s] 已推送至飞书: %s", account.name, msg.subject)
        else:
            log.error("[%s] 推送飞书失败: %s", account.name, msg.subject)


def process_once(accounts):
    if not Config.FEISHU_WEBHOOK_URL:
        log.error("飞书Webhook未配置，请检查 .env 文件")
        return

    with ThreadPoolExecutor(max_workers=len(accounts)) as pool:
        futures = {pool.submit(process_account, acc): acc for acc in accounts}
        for future in as_completed(futures):
            acc = futures[future]
            try:
                future.result()
            except Exception as e:
                log.error("[%s] 处理异常: %s", acc.name, e)


def main():
    log.info("邮件转发服务启动")

    try:
        accounts = Config.load_accounts()
    except FileNotFoundError as e:
        log.error(str(e))
        sys.exit(1)

    log.info("已加载 %d 个邮箱账号:", len(accounts))
    for acc in accounts:
        log.info("  - %s (%s)", acc.name, acc.email)
    log.info("轮询间隔: %ds", Config.POLL_INTERVAL)

    while running:
        process_once(accounts)
        for _ in range(Config.POLL_INTERVAL):
            if not running:
                break
            time.sleep(1)

    log.info("服务已停止")


if __name__ == "__main__":
    main()
