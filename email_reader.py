import re
import imaplib
import email
from email.header import decode_header
from email.utils import parseaddr
from dataclasses import dataclass, field


@dataclass
class Attachment:
    filename: str
    size: int
    content_type: str


@dataclass
class EmailMessage:
    uid: str
    sender: str
    sender_name: str
    subject: str
    body: str
    date: str
    attachments: list = field(default_factory=list)


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


def _strip_html(html):
    text = re.sub(r"<br\s*/?>", "\n", html, flags=re.IGNORECASE)
    text = re.sub(r"<p[^>]*>", "\n", text, flags=re.IGNORECASE)
    text = re.sub(r"</p>", "\n", text, flags=re.IGNORECASE)
    text = re.sub(r"<div[^>]*>", "\n", text, flags=re.IGNORECASE)
    text = re.sub(r"<li[^>]*>", "\n  - ", text, flags=re.IGNORECASE)
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"&nbsp;", " ", text)
    text = re.sub(r"&amp;", "&", text)
    text = re.sub(r"&lt;", "<", text)
    text = re.sub(r"&gt;", ">", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def _get_body(msg):
    plain_parts = []
    html_parts = []

    if msg.is_multipart():
        for part in msg.walk():
            ctype = part.get_content_type()
            cdisp = str(part.get("Content-Disposition", ""))
            if "attachment" in cdisp:
                continue
            if ctype == "text/plain":
                payload = part.get_payload(decode=True)
                if payload:
                    charset = part.get_content_charset() or "utf-8"
                    plain_parts.append(payload.decode(charset, errors="ignore"))
            elif ctype == "text/html":
                payload = part.get_payload(decode=True)
                if payload:
                    charset = part.get_content_charset() or "utf-8"
                    html_parts.append(payload.decode(charset, errors="ignore"))
    else:
        ctype = msg.get_content_type()
        payload = msg.get_payload(decode=True)
        if payload:
            charset = msg.get_content_charset() or "utf-8"
            content = payload.decode(charset, errors="ignore")
            if ctype == "text/plain":
                plain_parts.append(content)
            elif ctype == "text/html":
                html_parts.append(content)

    if plain_parts:
        return "\n".join(plain_parts)
    if html_parts:
        return _strip_html("\n".join(html_parts))
    return ""


def _get_attachments(msg):
    attachments = []
    if not msg.is_multipart():
        return attachments
    for part in msg.walk():
        cdisp = str(part.get("Content-Disposition", ""))
        if "attachment" not in cdisp:
            continue
        filename = part.get_filename()
        if filename:
            filename = _decode_str(filename)
        else:
            filename = "unnamed"
        payload = part.get_payload(decode=True)
        size = len(payload) if payload else 0
        attachments.append(Attachment(
            filename=filename,
            size=size,
            content_type=part.get_content_type(),
        ))
    return attachments


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
        attachments = _get_attachments(msg)

        mail.store(uid_bytes, "+FLAGS", "\\Seen")

        messages.append(EmailMessage(
            uid=uid_str,
            sender=sender_email,
            sender_name=sender_name,
            subject=subject,
            body=body,
            date=date,
            attachments=attachments,
        ))

    mail.close()
    mail.logout()
    return messages
