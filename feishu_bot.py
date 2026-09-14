import time
import hashlib
import hmac
import base64
import requests


def _gen_sign(timestamp, secret):
    string_to_sign = f"{timestamp}\n{secret}"
    hmac_code = hmac.new(
        string_to_sign.encode("utf-8"), digestmod=hashlib.sha256
    ).digest()
    return base64.b64encode(hmac_code).decode("utf-8")


def _format_size(size):
    if size < 1024:
        return f"{size} B"
    elif size < 1024 * 1024:
        return f"{size / 1024:.1f} KB"
    else:
        return f"{size / (1024 * 1024):.1f} MB"


def send_to_feishu(webhook_url, secret, email_msg, is_spam, spam_score, account_name=""):
    status_label = f"[垃圾邮件 {spam_score:.0%}]" if is_spam else "[正常]"
    title = f"{status_label} {email_msg.subject or '(无主题)'}"

    lines = []
    if account_name:
        lines.append(f"📧 来源: {account_name}")
    lines.append(f"👤 发件人: {email_msg.sender_name} <{email_msg.sender}>")
    lines.append(f"🕐 时间: {email_msg.date}")
    lines.append(f"📋 主题: {email_msg.subject}")

    if email_msg.attachments:
        lines.append("")
        lines.append("📎 附件:")
        for att in email_msg.attachments:
            lines.append(f"  · {att.filename} ({_format_size(att.size)})")

    lines.append("")
    lines.append("─" * 30)
    lines.append("")

    body_text = email_msg.body[:3000] if email_msg.body else "(无正文)"
    lines.append(body_text)

    content_text = "\n".join(lines)

    body = {
        "msg_type": "post",
        "content": {
            "post": {
                "zh_cn": {
                    "title": title,
                    "content": [
                        [{"tag": "text", "text": content_text}]
                    ],
                }
            }
        },
    }

    if secret:
        timestamp = str(int(time.time()))
        sign = _gen_sign(timestamp, secret)
        body["timestamp"] = timestamp
        body["sign"] = sign

    for attempt in range(3):
        try:
            resp = requests.post(
                webhook_url, json=body,
                headers={"Content-Type": "application/json"}, timeout=10,
            )
            if resp.status_code == 200:
                result = resp.json()
                if result.get("code") == 0 or result.get("StatusCode") == 0:
                    return True
            if attempt < 2:
                time.sleep(2 ** attempt)
        except requests.RequestException:
            if attempt < 2:
                time.sleep(2 ** attempt)

    return False
