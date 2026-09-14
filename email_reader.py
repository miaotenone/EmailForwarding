import imaplib
import email
from email.header import decode_header
from email.utils import parseaddr
from dataclasses import dataclass


@dataclass
class EmailMessage:
    uid: str
    sender: str
    sender_name: str
    subject: str
    body: str
    date: str


def _decode_str(s):
    if s is None:
        return ""
    decoded_parts = decode_header(s)
    result = []
    for part, charset in decoded_parts:
        if isinstance(part, bytes):
            result.append(part.decode(charset or "utf-8", errors="ignore"))
        else:
            result.append(part)
    return "".join(result)


def _get_body(msg):
    if msg.is_multipart():
        for part in msg.walk():
            ctype = part.get_content_type()
            cdisp = str(part.get("Content-Disposition", ""))
            if ctype == "text/plain" and "attachment" not in cdisp:
                payload = part.get_payload(decode=True)
                charset = part.get_content_charset() or "utf-8"
                return payload.decode(charset, errors="ignore")
        for part in msg.walk():
            ctype = part.get_content_type()
            if ctype == "text/html":
                payload = part.get_payload(decode=True)
                charset = part.get_content_charset() or "utf-8"
                return payload.decode(charset, errors="ignore")
        return ""
    else:
        payload = msg.get_payload(decode=True)
        if payload is None:
            return ""
        charset = msg.get_content_charset() or "utf-8"
        return payload.decode(charset, errors="ignore")


def fetch_unseen(host, port, user, password):
    mail = imaplib.IMAP4_SSL(host, port)
    mail.login(user, password)
    mail.select("INBOX")

    _, data = mail.search(None, "UNSEEN")
    uid_list = data[0].split()

    messages = []
    for uid_bytes in uid_list:
        uid_str = uid_bytes.decode()
        _, msg_data = mail.fetch(uid_bytes, "(RFC822)")
        raw_email = msg_data[0][1]
        msg = email.message_from_bytes(raw_email)

        sender_email = parseaddr(msg.get("From", ""))[1]
        sender_name = parseaddr(msg.get("From", ""))[0]
        subject = _decode_str(msg.get("Subject"))
        body = _get_body(msg)
        date = msg.get("Date", "")

        # 标记为已读，避免重复推送
        mail.store(uid_bytes, "+FLAGS", "\\Seen")

        messages.append(EmailMessage(
            uid=uid_str,
            sender=sender_email,
            sender_name=sender_name,
            subject=subject,
            body=body,
            date=date,
        ))

    mail.close()
    mail.logout()
    return messages
