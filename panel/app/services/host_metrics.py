from __future__ import annotations

import logging
import os
import time
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy.orm import Session

from app.config import is_agent_panel
from app.database import SessionLocal
from app.models import Node

log = logging.getLogger("vless-host-metrics")


@dataclass
class HostMetrics:
    cpu_percent: float
    mem_percent: float
    disk_percent: float
    load_1: float = 0.0
    mem_used_mb: int = 0
    mem_total_mb: int = 0
    disk_used_gb: float = 0.0
    disk_total_gb: float = 0.0

    def as_payload(self) -> dict:
        return {
            "cpu_percent": round(self.cpu_percent, 1),
            "mem_percent": round(self.mem_percent, 1),
            "disk_percent": round(self.disk_percent, 1),
            "load_1": round(self.load_1, 2),
            "mem_used_mb": self.mem_used_mb,
            "mem_total_mb": self.mem_total_mb,
            "disk_used_gb": round(self.disk_used_gb, 1),
            "disk_total_gb": round(self.disk_total_gb, 1),
        }


def _clamp_pct(value: float | None) -> float | None:
    if value is None:
        return None
    try:
        v = float(value)
    except (TypeError, ValueError):
        return None
    if v != v:
        return None
    return max(0.0, min(100.0, v))


def _read_proc_stat() -> tuple[int, int]:
    with open("/proc/stat", encoding="utf-8") as f:
        line = f.readline()
    parts = line.split()
    if len(parts) < 5 or parts[0] != "cpu":
        return 0, 0
    nums = [int(x) for x in parts[1:8]]
    idle = nums[3] + nums[4]
    total = sum(nums)
    return idle, total


def _load_avg_1() -> float:
    try:
        with open("/proc/loadavg", encoding="utf-8") as f:
            return float(f.read().split()[0])
    except (OSError, ValueError, IndexError):
        return 0.0


def _cpu_percent_sample(interval: float = 0.08) -> float:
    idle1, total1 = _read_proc_stat()
    time.sleep(interval)
    idle2, total2 = _read_proc_stat()
    dt = total2 - total1
    if dt <= 0:
        return 0.0
    di = idle2 - idle1
    return max(0.0, min(100.0, (1.0 - di / dt) * 100.0))


def _mem_info() -> tuple[float, int, int]:
    mem_total = 0
    mem_available = 0
    with open("/proc/meminfo", encoding="utf-8") as f:
        for line in f:
            if line.startswith("MemTotal:"):
                mem_total = int(line.split()[1])
            elif line.startswith("MemAvailable:"):
                mem_available = int(line.split()[1])
    if mem_total <= 0:
        return 0.0, 0, 0
    used = mem_total - mem_available
    pct = max(0.0, min(100.0, used / mem_total * 100.0))
    return pct, used // 1024, mem_total // 1024


def _disk_info(path: str = "/") -> tuple[float, float, float]:
    try:
        st = os.statvfs(path)
    except OSError:
        return 0.0, 0.0, 0.0
    total = st.f_blocks * st.f_frsize
    free = st.f_bavail * st.f_frsize
    if total <= 0:
        return 0.0, 0.0, 0.0
    used = total - free
    pct = max(0.0, min(100.0, used / total * 100.0))
    gb = 1024**3
    return pct, used / gb, total / gb


def collect_host_metrics(disk_path: str = "/") -> HostMetrics:
    mem_pct, mem_used, mem_total = _mem_info()
    disk_pct, disk_used, disk_total = _disk_info(disk_path)
    return HostMetrics(
        cpu_percent=_cpu_percent_sample(),
        mem_percent=mem_pct,
        disk_percent=disk_pct,
        load_1=_load_avg_1(),
        mem_used_mb=mem_used,
        mem_total_mb=mem_total,
        disk_used_gb=disk_used,
        disk_total_gb=disk_total,
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


def refresh_local_node_metrics(db: Session) -> HostMetrics | None:
    node = db.query(Node).filter(Node.role == "local").first()
    if not node:
        return None
    m = collect_host_metrics()
    apply_node_metrics(
        node,
        {"cpu_percent": m.cpu_percent, "mem_percent": m.mem_percent, "disk_percent": m.disk_percent},
    )
    db.commit()
    return m


def persist_local_node_metrics() -> None:
    if is_agent_panel():
        return
    db = SessionLocal()
    try:
        refresh_local_node_metrics(db)
    except Exception as exc:
        db.rollback()
        log.warning("local metrics persist failed: %s", exc)
    finally:
        db.close()


def metrics_stale(node: Node, max_age_sec: int = 120) -> bool:
    if node.metrics_at is None:
        return False
    age = (datetime.utcnow() - node.metrics_at).total_seconds()
    return age > max_age_sec


def metrics_missing(node: Node) -> bool:
    return node.metrics_at is None or (
        node.metric_cpu is None and node.metric_mem is None and node.metric_disk is None
    )


def metric_level(pct: float | None) -> str:
    if pct is None:
        return "none"
    if pct >= 90:
        return "bad"
    if pct >= 75:
        return "warn"
    return "ok"


def node_metrics_detail(node: Node, live: HostMetrics | None = None) -> dict:
    """Подписи для UI (btop-style). live — только что снятые метрики master."""
    if live and node.role == "local":
        return {
            "load_1": live.load_1,
            "mem_label": f"{live.mem_used_mb / 1024:.1f} / {live.mem_total_mb / 1024:.1f} GiB",
            "disk_label": f"{live.disk_used_gb:.0f} / {live.disk_total_gb:.0f} GiB",
        }
    return {
        "load_1": None,
        "mem_label": None,
        "disk_label": None,
    }
