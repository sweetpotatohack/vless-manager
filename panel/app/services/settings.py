from __future__ import annotations

from sqlalchemy.orm import Session

from app.models import PanelSettings


def get_settings(db: Session) -> PanelSettings:
    row = db.get(PanelSettings, 1)
    if not row:
        row = PanelSettings(id=1)
        db.add(row)
        db.commit()
        db.refresh(row)
    return row
