from __future__ import annotations

import smtplib
import subprocess
from email.message import EmailMessage

import httpx


async def send_telegram(token: str, chat_id: str, text: str) -> bool:
    if not token or not chat_id:
        return False
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            r = await client.post(url, json={"chat_id": chat_id, "text": text[:4000]})
            return r.status_code == 200
    except Exception:
        return False


def send_email_simple(to_addr: str, subject: str, body: str) -> bool:
    if not to_addr:
        return False
    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = "vless-panel@localhost"
    msg["To"] = to_addr
    msg.set_content(body)
    try:
        with smtplib.SMTP("localhost", 25, timeout=15) as smtp:
            smtp.send_message(msg)
        return True
    except OSError:
        try:
            subprocess.run(
                ["sendmail", "-t", "-oi"],
                input=msg.as_bytes(),
                timeout=30,
                check=False,
            )
            return True
        except OSError:
            return False


async def notify_admin(db_settings, subject: str, body: str) -> None:
    if not db_settings.notify_on_cert:
        return
    if db_settings.telegram_bot_token and db_settings.telegram_chat_id:
        await send_telegram(
            db_settings.telegram_bot_token,
            db_settings.telegram_chat_id,
            f"{subject}\n\n{body}",
        )
    if db_settings.notify_email:
        send_email_simple(db_settings.notify_email, subject, body)
