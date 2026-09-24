from __future__ import annotations

import asyncio
import logging
import os
import subprocess
from pathlib import Path

import httpx

from app.services.provision import delete_local_client, provision_local
from app.services.public_ip import detect_egress_public_ip

log = logging.getLogger("vless-agent-worker")
PANEL_DATA = Path("/etc/vless-manager/panel")


def _agent_role() -> bool:
    return os.environ.get("VLESS_PANEL_ROLE", "master").strip().lower() == "agent"


def _read_master_url() -> str:
    url = os.environ.get("VLESS_PANEL_MASTER_URL", "").strip()
    if url:
        return url.rstrip("/")
    master_file = PANEL_DATA / "master.url"
    if master_file.is_file():
        return master_file.read_text().strip().rstrip("/")
    return ""


def _read_agent_token() -> str:
    token = os.environ.get("VLESS_PANEL_AGENT_TOKEN", "").strip()
    if token:
        return token
    env_file = PANEL_DATA / "agent.env"
    if not env_file.is_file():
        return ""
    for line in env_file.read_text().splitlines():
        if line.startswith("VLESS_PANEL_AGENT_TOKEN="):
            return line.split("=", 1)[1].strip()
    return ""


async def _apply_vpn_domain_from_master(master: str, token: str) -> None:
    headers = {"Authorization": f"Bearer {token}"}
    try:
        async with httpx.AsyncClient(timeout=30.0, verify=True) as client:
            resp = await client.get(f"{master}/api/v1/agent/node-config", headers=headers)
            if resp.status_code >= 400:
                return
            domain = (resp.json().get("vpn_domain") or "").strip()
            if not domain or domain.endswith(".local"):
                return
            mgr = os.environ.get("VLESS_MANAGER_SH", "/opt/vless-manager/vless_manager.sh")
            await asyncio.to_thread(
                subprocess.run,
                ["/bin/bash", mgr, "cli", "set-public-host", domain],
                capture_output=True,
                text=True,
                timeout=60,
                check=False,
            )
    except Exception as exc:
        log.warning("set-public-host from master: %s", exc)


async def _process_job(master: str, token: str, job: dict) -> dict:
    job_id = job["id"]
    job_type = job.get("job_type", "provision")
    username = job["username"]
    wifi = bool(job.get("has_wifi", True))
    mobile = bool(job.get("has_mobile", True))

    if job_type == "delete":
        result = await asyncio.to_thread(
            delete_local_client, username, wifi=wifi, mobile=mobile
        )
        return {
            "job_id": job_id,
            "ok": result.ok,
            "error_message": None if result.ok else result.message,
        }

    await _apply_vpn_domain_from_master(master, token)
    result = await asyncio.to_thread(
        provision_local, username, wifi=wifi, mobile=mobile
    )
    if not result.ok:
        return {"job_id": job_id, "ok": False, "error_message": result.message}
    return {
        "job_id": job_id,
        "ok": True,
        "wifi_vless_url": result.wifi_vless_url,
        "mobile_vless_url": result.mobile_vless_url,
        "hysteria_url": result.hysteria_url,
        "wifi_port": result.wifi_port,
        "uuid": result.uuid,
    }


async def agent_job_worker_loop() -> None:
    if not _agent_role():
        return
    master = _read_master_url()
    token = _read_agent_token()
    if not master or not token:
        log.warning("agent worker: нет master.url или agent token — опрос задач отключён")
        return
    headers = {"Authorization": f"Bearer {token}"}
    log.info("agent worker: polling %s for jobs", master)
    ticks = 0
    while True:
        try:
            async with httpx.AsyncClient(timeout=60.0, verify=True) as client:
                ticks += 1
                if ticks == 1 or ticks % 30 == 0:
                    pub = await asyncio.to_thread(detect_egress_public_ip)
                    if pub:
                        await client.post(
                            f"{master}/api/v1/agent/heartbeat",
                            headers=headers,
                            json={"public_ip": pub},
                        )
                resp = await client.get(f"{master}/api/v1/agent/next-job", headers=headers)
                if resp.status_code == 204:
                    await asyncio.sleep(2.0)
                    continue
                if resp.status_code >= 400:
                    log.warning("next-job HTTP %s: %s", resp.status_code, resp.text[:200])
                    await asyncio.sleep(5.0)
                    continue
                job = resp.json()
                payload = await _process_job(master, token, job)
                post = await client.post(
                    f"{master}/api/v1/agent/job-result",
                    headers=headers,
                    json=payload,
                )
                if post.status_code >= 400:
                    log.warning("job-result HTTP %s: %s", post.status_code, post.text[:200])
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            log.warning("agent worker error: %s", exc)
            await asyncio.sleep(5.0)


def start_agent_job_worker() -> None:
    if not _agent_role():
        return
    asyncio.create_task(agent_job_worker_loop())
