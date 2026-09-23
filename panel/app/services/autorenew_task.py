from __future__ import annotations

import asyncio
import logging

from app.database import SessionLocal
from app.services.cert_actions import maybe_auto_renew
from app.services.notify import notify_admin
from app.services.settings import get_settings

log = logging.getLogger("vless-panel")


async def cert_autorenew_worker() -> None:
    await asyncio.sleep(30)
    while True:
        try:
            db = SessionLocal()
            try:
                settings = get_settings(db)
                if settings.auto_renew_enabled:
                    result = await asyncio.to_thread(
                        maybe_auto_renew, settings.auto_renew_days
                    )
                    if "renew выполнен" in result.message or "failed" in result.message.lower():
                        await notify_admin(
                            db_settings=settings,
                            subject="VLESS Panel: сертификаты",
                            body=result.message,
                        )
                    log.info("autorenew: %s", result.message)
            finally:
                db.close()
        except Exception as e:
            log.exception("autorenew error: %s", e)
        await asyncio.sleep(3600)
