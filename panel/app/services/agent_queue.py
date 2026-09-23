from __future__ import annotations

import asyncio
import datetime as dt

from sqlalchemy.orm import Session

from app.models import AgentJob, Node


def remote_uses_job_queue(node: Node) -> bool:
    """Remote agents always pull jobs from master (works behind NAT)."""
    return node.role == "remote"


def create_provision_job(
    db: Session,
    *,
    node_id: int,
    username: str,
    wifi: bool,
    mobile: bool,
) -> AgentJob:
    job = AgentJob(
        node_id=node_id,
        job_type="provision",
        username=username,
        has_wifi=wifi,
        has_mobile=mobile,
        status="pending",
    )
    db.add(job)
    db.commit()
    db.refresh(job)
    return job


def create_delete_job(
    db: Session,
    *,
    node_id: int,
    username: str,
    wifi: bool,
    mobile: bool,
) -> AgentJob:
    job = AgentJob(
        node_id=node_id,
        job_type="delete",
        username=username,
        has_wifi=wifi,
        has_mobile=mobile,
        status="pending",
    )
    db.add(job)
    db.commit()
    db.refresh(job)
    return job


def reclaim_stale_jobs(db: Session, *, minutes: int = 10) -> None:
    cutoff = dt.datetime.utcnow() - dt.timedelta(minutes=minutes)
    stale = (
        db.query(AgentJob)
        .filter(AgentJob.status == "processing", AgentJob.updated_at < cutoff)
        .all()
    )
    for job in stale:
        job.status = "pending"
        job.updated_at = dt.datetime.utcnow()
    if stale:
        db.commit()


async def wait_for_job(
    job_id: int,
    *,
    timeout_sec: float = 120.0,
    poll_sec: float = 2.0,
) -> AgentJob:
    import time

    from app.database import SessionLocal

    deadline = time.monotonic() + timeout_sec
    while time.monotonic() < deadline:
        db = SessionLocal()
        try:
            job = db.get(AgentJob, job_id)
            if not job:
                raise RuntimeError("Задача не найдена")
            if job.status == "done":
                return job
            if job.status == "failed":
                return job
        finally:
            db.close()
        await asyncio.sleep(poll_sec)
    raise TimeoutError(
        "Агент не выполнил задачу вовремя. Проверьте vless-panel на ноде и доступ ноды к master (HTTPS)."
    )
