from config import Config


def is_spam(email_msg):
    if email_msg.sender in Config.BLACKLIST_SENDERS:
        return True, 1.0

    text = (email_msg.subject + " " + email_msg.body).lower()
    matched = 0
    for kw in Config.SPAM_KEYWORDS:
        if kw.lower() in text:
            matched += 1

    if matched == 0:
        return False, 0.0

    score = min(matched * 0.15, 1.0)
    return score >= Config.SPAM_THRESHOLD, score
