from __future__ import annotations

import os
import time
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy.orm import Session

from app.config import is_agent_panel
from app.database import SessionLocal
from app.models import Node


@dataclass
class HostMetrics:
    cpu_percent: float
    mem_percent: float
    disk_percent: float

    def as_payload(self) -> dict[str, float]:
        return {
            "cpu_percent": round(self.cpu_percent, 1),
            "mem_percent": round(self.mem_percent, 1),
            "disk_percent": round(self.disk_percent, 1),
        }


def _clamp_pct(value: float | None) -> float | None:
    if value is None:
        return None
    try:
        v = float(value)
    except (TypeError, ValueError):
        return None
    if v != v:  # NaN
        return None
    return max(0.0, min(100.0, v))


def _read_proc_stat() -> tuple[int, int]:
    with open("/proc/stat", encoding="utf-8") as f:
        line = f.readline()
    parts = line.split()
    if not parts.startswith("cpu"):
        return 0, 0
    nums = [int(x) for x in parts[1:8]]
    idle = nums[3] + nums[4]
    total = sum(nums)
    return idle, total


def _cpu_percent_sample(interval: float = 0.12) -> float:
    idle1, total1 = _read_proc_stat()
    time.sleep(interval)
    idle2, total2 = _read_proc_stat()
    dt = total2 - total1
    if dt <= 0:
        return 0.0
    di = idle2 - idle1
    return max(0.0, min(100.0, (1.0 - di / dt) * 100.0))


def _mem_percent() -> float:
    mem_total = 0
    mem_available = 0
    with open("/proc/meminfo", encoding="utf-8") as f:
        for line in f:
            if line.startswith("MemTotal:"):
                mem_total = int(line.split()[1])
            elif line.startswith("MemAvailable:"):
                mem_available = int(line.split()[1])
    if mem_total <= 0:
        return 0.0
    used = mem_total - mem_available
    return max(0.0, min(100.0, used / mem_total * 100.0))


def _disk_percent(path: str = "/") -> float:
    try:
        st = os.statvfs(path)
    except OSError:
        return 0.0
    total = st.f_blocks * st.f_frsize
    free = st.f_bavail * st.f_frsize
    if total <= 0:
        return 0.0
    used = total - free
    return max(0.0, min(100.0, used / total * 100.0))


def collect_host_metrics(disk_path: str = "/") -> HostMetrics:
    return HostMetrics(
        cpu_percent=_cpu_percent_sample(),
        mem_percent=_mem_percent(),
        disk_percent=_disk_percent(disk_path),
    )


def apply_node_metrics(node: Node, body: dict) -> None:
    cpu = _clamp_pct(body.get("cpu_percent"))
    mem = _clamp_pct(body.get("mem_percent"))
    disk = _clamp_pct(body.get("disk_percent"))
    if cpu is None and mem is None and disk is None:
        return
    if cpu is not None:
        node.metric_cpu = cpu
    if mem is not None:
        node.metric_mem = mem
    if disk is not None:
        node.metric_disk = disk
    node.metrics_at = datetime.utcnow()


def refresh_local_node_metrics(db: Session) -> None:
    node = db.query(Node).filter(Node.role == "local").first()
    if not node:
        return
    m = collect_host_metrics()
    apply_node_metrics(
        node,
        {"cpu_percent": m.cpu_percent, "mem_percent": m.mem_percent, "disk_percent": m.disk_percent},
    )
    db.commit()


def persist_local_node_metrics() -> None:
    if is_agent_panel():
        return
    db = SessionLocal()
    try:
        refresh_local_node_metrics(db)
    except Exception:
        db.rollback()
    finally:
        db.close()


def metrics_stale(node: Node, max_age_sec: int = 180) -> bool:
    if node.metrics_at is None:
        return True
    age = (datetime.utcnow() - node.metrics_at).total_seconds()
    return age > max_age_sec


def metric_level(pct: float | None) -> str:
    if pct is None:
        return "none"
    if pct >= 90:
        return "bad"
    if pct >= 75:
        return "warn"
    return "ok"
