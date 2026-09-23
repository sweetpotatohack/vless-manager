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


def send_email_local(to_addr: str, subject: str, body: str) -> bool:
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


def send_email_smtp(
    *,
    host: str,
    port: int,
    user: str,
    password: str,
    security: str,
    from_addr: str,
    to_addr: str,
    subject: str,
    body: str,
) -> bool:
    if not host or not to_addr:
        return False
    port = port or (465 if security == "ssl" else 587)
    from_hdr = (from_addr or user or f"noreply@{host.split('@')[-1]}").strip()
    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = from_hdr
    msg["To"] = to_addr
    msg.set_content(body)
    sec = (security or "starttls").lower()
    try:
        if sec == "ssl":
            with smtplib.SMTP_SSL(host, port, timeout=30) as smtp:
                if user:
                    smtp.login(user, password)
                smtp.send_message(msg)
        else:
            with smtplib.SMTP(host, port, timeout=30) as smtp:
                if sec == "starttls":
                    smtp.starttls()
                if user:
                    smtp.login(user, password)
                smtp.send_message(msg)
        return True
    except (OSError, smtplib.SMTPException):
        return False


def send_email_for_settings(db_settings, to_addr: str, subject: str, body: str) -> bool:
    host = (getattr(db_settings, "smtp_host", None) or "").strip()
    if host:
        return send_email_smtp(
            host=host,
            port=int(getattr(db_settings, "smtp_port", None) or 587),
            user=(getattr(db_settings, "smtp_user", None) or "").strip(),
            password=getattr(db_settings, "smtp_password", None) or "",
            security=(getattr(db_settings, "smtp_security", None) or "starttls").strip(),
            from_addr=(getattr(db_settings, "smtp_from_email", None) or "").strip(),
            to_addr=to_addr,
            subject=subject,
            body=body,
        )
    return send_email_local(to_addr, subject, body)


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
        send_email_for_settings(db_settings, db_settings.notify_email, subject, body)
