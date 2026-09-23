from __future__ import annotations

import asyncio
import io
import re
import secrets
import tarfile
from urllib.parse import quote
from datetime import datetime
from pathlib import Path

from typing import Annotated

from fastapi import Depends, FastAPI, Form, HTTPException, Request
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, RedirectResponse, Response
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from app.auth import hash_password, verify_login_password, verify_password
from app.bootstrap import ensure_default_admin, ensure_local_node
from app.config import (
    APP_TITLE,
    DATA_DIR,
    QR_DIR,
    SESSION_COOKIE,
    SESSION_MAX_AGE,
    VLESS_CONFIG_DIR,
)
from app.database import Base, engine, get_db
from app.deps import create_session_token, get_current_admin, get_optional_admin
from app.migrate import run_migrations
from app.models import AdminUser, AgentJob, Node, ProxyUser
from app.services.agent_queue import (
    create_delete_job,
    create_provision_job,
    reclaim_stale_jobs,
    remote_uses_job_queue,
    wait_for_job,
)
from app.services.agent_worker import start_agent_job_worker
from app.services.agent_script import render_agent_install_script
from app.services.autorenew_task import cert_autorenew_worker
from app.services.cert_actions import (
    reissue_new_domain,
    renew_certificates,
    sync_hysteria_from_le,
)
from app.services.certs import all_cert_status
from app.services.settings import get_settings
from app.services.master_url import get_master_public_url
from app.services.nodes_helpers import node_vpn_host
from app.services.ports import port_status
from app.services.provision import (
    ProvisionResult,
    delete_local_client,
    delete_remote_client,
    provision_local,
    provision_remote,
    qr_png_path,
    reconcile_wifi_servers,
)
from app.security import (
    apply_security_headers,
    attach_csrf_cookie,
    client_ip,
    ensure_csrf_request_state,
    login_rate_limiter,
    normalize_login_username,
    validate_password_length,
    verify_csrf,
)

APP_DIR = Path(__file__).resolve().parent
REPO_PANEL = APP_DIR.parent
REPO_ROOT = REPO_PANEL.parent
templates = Jinja2Templates(directory=str(APP_DIR / "templates"))
templates.env.autoescape = True
templates.env.globals["node_vpn_host"] = node_vpn_host

app = FastAPI(title=APP_TITLE)
app.mount("/static", StaticFiles(directory=str(APP_DIR / "static")), name="static")


async def require_form_csrf(
    request: Request,
    csrf_token: Annotated[str, Form()] = "",
) -> None:
    verify_csrf(request, csrf_token)


def _response_is_secure(request: Request) -> bool:
    if request.url.scheme == "https":
        return True
    forwarded = (request.headers.get("x-forwarded-proto") or "").split(",")[0].strip()
    return forwarded == "https"


@app.middleware("http")
async def panel_security_middleware(request: Request, call_next):
    ensure_csrf_request_state(request)
    response = await call_next(request)
    apply_security_headers(response)
    attach_csrf_cookie(response, request, secure=_response_is_secure(request))
    return response


@app.exception_handler(HTTPException)
async def panel_http_exception_handler(request: Request, exc: HTTPException):
    """Браузер → /login, API → JSON."""
    if exc.status_code in (401, 403) and not request.url.path.startswith("/api/"):
        if exc.status_code == 403 and "CSRF" in str(exc.detail):
            return RedirectResponse(url="/login?err=csrf", status_code=303)
        return RedirectResponse(url="/login", status_code=303)
    return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})


@app.on_event("startup")
async def on_startup():
    Base.metadata.create_all(bind=engine)
    run_migrations()
    from app.database import SessionLocal

    db = SessionLocal()
    try:
        ensure_default_admin(db)
        ensure_local_node(db)
        get_settings(db)
    finally:
        db.close()
    reconcile_wifi_servers()
    asyncio.create_task(cert_autorenew_worker())
    start_agent_job_worker()


@app.get("/login", response_class=HTMLResponse)
def login_page(
    request: Request,
    admin: AdminUser | None = Depends(get_optional_admin),
    err: str | None = None,
):
    if admin:
        return RedirectResponse("/dashboard", status_code=303)
    error = None
    if err == "csrf":
        error = "Сессия формы истекла. Обновите страницу и войдите снова."
    return templates.TemplateResponse(
        "login.html",
        {"request": request, "title": "Control Panel", "error": error},
    )


@app.post("/login")
def login_submit(
    request: Request,
    username: str = Form(...),
    password: str = Form(...),
    csrf_token: str = Form(""),
    db: Session = Depends(get_db),
):
    verify_csrf(request, csrf_token)
    ip = client_ip(request)
    if login_rate_limiter.is_blocked(ip):
        return templates.TemplateResponse(
            "login.html",
            {
                "request": request,
                "title": APP_TITLE,
                "error": "Слишком много попыток. Подождите 15 минут.",
            },
            status_code=429,
        )

    uname = normalize_login_username(username)
    if not uname or not validate_password_length(password):
        login_rate_limiter.record_failure(ip)
        return templates.TemplateResponse(
            "login.html",
            {
                "request": request,
                "title": APP_TITLE,
                "error": "Неверный логин или пароль",
            },
            status_code=401,
        )

    admin = db.query(AdminUser).filter(AdminUser.username == uname).first()
    if not verify_login_password(password, admin.password_hash if admin else None):
        login_rate_limiter.record_failure(ip)
        return templates.TemplateResponse(
            "login.html",
            {
                "request": request,
                "title": APP_TITLE,
                "error": "Неверный логин или пароль",
            },
            status_code=401,
        )

    login_rate_limiter.clear(ip)
    token = create_session_token(admin.id)
    resp = RedirectResponse("/dashboard", status_code=303)
    resp.set_cookie(
        SESSION_COOKIE,
        token,
        httponly=True,
        samesite="lax",
        max_age=SESSION_MAX_AGE,
        secure=_response_is_secure(request),
        path="/",
    )
    return resp


@app.post("/logout")
def logout(request: Request, csrf_token: str = Form("")):
    verify_csrf(request, csrf_token)
    resp = RedirectResponse("/login", status_code=303)
    resp.delete_cookie(SESSION_COOKIE, path="/")
    return resp


@app.get("/dashboard", response_class=HTMLResponse)
def dashboard(
    request: Request,
    admin: AdminUser = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    nodes = db.query(Node).filter(Node.is_active.is_(True)).order_by(Node.name).all()
    users_count = db.query(ProxyUser).count()
    cert_data = all_cert_status()
    min_days = None
    for c in cert_data["certificates"]:
        if c.days_left is not None:
            min_days = c.days_left if min_days is None else min(min_days, c.days_left)
    hy = cert_data.get("hysteria")
    if hy and hy.days_left is not None:
        min_days = hy.days_left if min_days is None else min(min_days, hy.days_left)

    return templates.TemplateResponse(
        "dashboard.html",
        {
            "request": request,
            "title": APP_TITLE,
            "admin": admin,
            "nodes": nodes,
            "users_count": users_count,
            "cert_min_days": min_days,
            "cert_checked": cert_data["checked_at"],
        },
    )


def _node_by_agent_token(db: Session, token: str) -> Node | None:
    return db.query(Node).filter(Node.api_token == token).first()


def _agent_node_from_request(request: Request, db: Session) -> Node | None:
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        return None
    token = auth.removeprefix("Bearer ").strip()
    if not token:
        return None
    return _node_by_agent_token(db, token)


@app.get("/nodes", response_class=HTMLResponse)
def nodes_page(
    request: Request,
    admin: AdminUser = Depends(get_current_admin),
    db: Session = Depends(get_db),
    created: int | None = None,
):
    nodes = db.query(Node).order_by(Node.country, Node.name).all()
    master_url = get_master_public_url(request)
    new_node = db.get(Node, created) if created else None
    local_country = None
    lf = DATA_DIR / "local-country.txt"
    if lf.is_file():
        local_country = lf.read_text().strip()
    if not local_country:
        loc = db.query(Node).filter(Node.role == "local").first()
        local_country = loc.country if loc else ""
    install_cmd = None
    if new_node and new_node.api_token:
        install_cmd = (
            f"curl -fsSL '{master_url}/api/v1/agent/install.sh?token={new_node.api_token}' | bash"
        )
    flash_ok = request.query_params.get("msg")
    flash_err = request.query_params.get("err")
    return templates.TemplateResponse(
        "nodes.html",
        {
            "request": request,
            "title": APP_TITLE,
            "admin": admin,
            "nodes": nodes,
            "master_url": master_url,
            "new_node": new_node,
            "install_cmd": install_cmd,
            "local_country": local_country,
            "flash_ok": flash_ok,
            "flash_err": flash_err,
        },
    )


@app.post("/nodes/local-country")
def nodes_set_local_country(
    admin: AdminUser = Depends(get_current_admin),
    db: Session = Depends(get_db),
    _: None = Depends(require_form_csrf),
    country: str = Form(...),
):
    country = country.strip()
    if country:
        (DATA_DIR / "local-country.txt").write_text(country + "\n")
    node = db.query(Node).filter(Node.role == "local").first()
    if node and country:
        node.country = country
        db.commit()
    return RedirectResponse("/nodes", status_code=303)


@app.post("/nodes/generate-agent")
def nodes_generate_agent(
    request: Request,
    admin: AdminUser = Depends(get_current_admin),
    db: Session = Depends(get_db),
    _: None = Depends(require_form_csrf),
    name: str = Form(...),
    country: str = Form(...),
    domain: str = Form(...),
):
    domain = domain.strip().lower()
    if not domain or domain.endswith(".local"):
        return RedirectResponse(
            "/nodes?err=" + quote("Укажите DNS домен VPN (A/AAAA на IP ноды)"),
            status_code=303,
        )
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")[:60] or secrets.token_hex(4)
    if db.query(Node).filter(Node.slug == slug).first():
        slug = f"{slug}-{secrets.token_hex(3)}"
    token = secrets.token_hex(24)
    node = Node(
        name=name.strip(),
        slug=slug,
        domain=domain,
        region=country.strip(),
        country=country.strip(),
        public_ip="",
        role="remote",
        api_base=None,
        api_token=token,
        agent_status="pending",
        is_active=False,
    )
    db.add(node)
    db.commit()
    db.refresh(node)
    return RedirectResponse(f"/nodes?created={node.id}", status_code=303)


@app.post("/nodes/{node_id}/domain")
def nodes_set_domain(
    node_id: int,
    admin: AdminUser = Depends(get_current_admin),
    db: Session = Depends(get_db),
    _: None = Depends(require_form_csrf),
    domain: str = Form(...),
):
    node = db.get(Node, node_id)
    if not node or node.role != "remote":
        return RedirectResponse("/nodes?err=" + quote("Нода не найдена"), status_code=303)
    domain = domain.strip().lower()
    if not domain or domain.endswith(".local"):
        return RedirectResponse(
            "/nodes?err=" + quote("Некорректный DNS домен"),
            status_code=303,
        )
    node.domain = domain
    db.commit()
    return RedirectResponse("/nodes?msg=" + quote(f"DNS ноды «{node.name}»: {domain}"), status_code=303)


@app.post("/nodes/{node_id}/delete")
async def nodes_delete(
    node_id: int,
    admin: AdminUser = Depends(get_current_admin),
    db: Session = Depends(get_db),
    _: None = Depends(require_form_csrf),
):
    node = db.get(Node, node_id)
    if not node:
        raise HTTPException(404)
    if node.role == "local":
        return RedirectResponse(
            "/nodes?err=" + quote("Нельзя удалить master-ноду"),
            status_code=303,
        )
    name = node.name
    remote_fail: list[str] = []
    users = db.query(ProxyUser).filter(ProxyUser.node_id == node_id).all()
    for pu in users:
        if node.api_base and node.api_token:
            result = await delete_remote_client(
                node.api_base,
                node.api_token,
                pu.username,
                wifi=pu.has_wifi,
                mobile=pu.has_mobile,
            )
            if not result.ok:
                remote_fail.append(pu.username)
        db.delete(pu)
    db.delete(node)
    db.commit()
    msg = f"Нода «{name}» удалена из панели"
    if remote_fail:
        msg += f" (на agent не сняты: {', '.join(remote_fail[:5])})"
    return RedirectResponse("/nodes?msg=" + quote(msg), status_code=303)


@app.get("/nodes/{node_id}/install.sh")
def download_agent_script(
    node_id: int,
    request: Request,
    admin: AdminUser = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    node = db.get(Node, node_id)
    if not node or not node.api_token:
        raise HTTPException(404)
    master = get_master_public_url(request)
    body = render_agent_install_script(
        master_url=master,
        node_token=node.api_token,
        node_name=node.name,
    )
    return Response(
        content=body,
        media_type="application/x-sh",
        headers={
            "Content-Disposition": f'attachment; filename="vless-agent-{node.slug}.sh"'
        },
    )


@app.get("/proxy", response_class=HTMLResponse)
def proxy_list(
    request: Request,
    admin: AdminUser = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    nodes = (
        db.query(Node)
        .filter(Node.is_active.is_(True), Node.agent_status == "online")
        .order_by(Node.country, Node.name)
        .all()
    )
    if not nodes:
        nodes = db.query(Node).filter(Node.is_active.is_(True)).order_by(Node.name).all()
    from sqlalchemy.orm import joinedload

    users = (
        db.query(ProxyUser)
        .options(joinedload(ProxyUser.node))
        .order_by(ProxyUser.created_at.desc())
        .limit(100)
        .all()
    )
    flash_ok = request.query_params.get("msg")
    flash_err = request.query_params.get("err")
    return templates.TemplateResponse(
        "proxy.html",
        {
            "request": request,
            "title": APP_TITLE,
            "admin": admin,
            "nodes": nodes,
            "users": users,
            "error": flash_err,
            "flash_ok": flash_ok,
        },
    )


@app.post("/proxy")
async def proxy_create(
    request: Request,
    admin: AdminUser = Depends(get_current_admin),
    db: Session = Depends(get_db),
    _: None = Depends(require_form_csrf),
    node_id: int = Form(...),
    username: str = Form(...),
    wifi: str | None = Form(None),
    mobile: str | None = Form(None),
):
    node = db.get(Node, node_id)
    if not node or not node.is_active:
        raise HTTPException(400, "Нода недоступна — дождитесь online или выберите master")
    do_wifi = wifi == "on"
    do_mobile = mobile == "on"
    if not do_wifi and not do_mobile:
        raise HTTPException(400, "Выберите Wi‑Fi и/или LTE профиль")

    uname = username.strip()
    dup = (
        db.query(ProxyUser)
        .filter(ProxyUser.node_id == node.id, ProxyUser.username == uname)
        .first()
    )
    if dup:
        nodes = db.query(Node).filter(Node.is_active.is_(True)).all()
        users = db.query(ProxyUser).order_by(ProxyUser.created_at.desc()).limit(100).all()
        return templates.TemplateResponse(
            "proxy.html",
            {
                "request": request,
                "title": APP_TITLE,
                "admin": admin,
                "nodes": nodes,
                "users": users,
                "error": f"Пользователь «{uname}» уже есть на этой ноде. Удалите старый конфиг.",
            },
            status_code=400,
        )

    api_base = node.api_base
    if node.role == "local":
        api_base = api_base or "http://127.0.0.1:8765"
        result = await asyncio.to_thread(
            provision_local,
            uname,
            wifi=do_wifi,
            mobile=do_mobile,
        )
    else:
        if not node.api_token:
            raise HTTPException(400, "Нода ещё не зарегистрирована агентом")
        if remote_uses_job_queue(node):
            job = create_provision_job(
                db,
                node_id=node.id,
                username=uname,
                wifi=do_wifi,
                mobile=do_mobile,
            )
            try:
                job = await wait_for_job(job.id)
            except TimeoutError as e:
                result = ProvisionResult(False, str(e))
            else:
                if job.status == "failed":
                    result = ProvisionResult(False, job.error_message or "Ошибка на agent")
                else:
                    result = ProvisionResult(
                        ok=True,
                        message="OK",
                        wifi_vless_url=job.wifi_vless_url,
                        mobile_vless_url=job.mobile_vless_url,
                        hysteria_url=job.hysteria_url,
                        wifi_port=job.wifi_port,
                        uuid=job.uuid,
                    )
        else:
            if not api_base:
                raise HTTPException(400, "Нода ещё не зарегистрирована агентом")
            result = await provision_remote(
                api_base,
                node.api_token,
                uname,
                wifi=do_wifi,
                mobile=do_mobile,
            )

    if not result.ok:
        nodes = db.query(Node).filter(Node.is_active.is_(True)).all()
        users = db.query(ProxyUser).order_by(ProxyUser.created_at.desc()).limit(100).all()
        return templates.TemplateResponse(
            "proxy.html",
            {
                "request": request,
                "title": APP_TITLE,
                "admin": admin,
                "nodes": nodes,
                "users": users,
                "error": result.message,
            },
            status_code=400,
        )

    pu = ProxyUser(
        node_id=node.id,
        username=uname,
        has_wifi=do_wifi,
        has_mobile=do_mobile,
        wifi_vless_url=result.wifi_vless_url,
        mobile_vless_url=result.mobile_vless_url,
        hysteria_url=result.hysteria_url,
        wifi_port=result.wifi_port,
        uuid=result.uuid,
        exit_country=node.country or node.region,
        exit_ip=node_vpn_host(node),
    )
    db.add(pu)
    db.commit()
    db.refresh(pu)
    return RedirectResponse(f"/proxy/{pu.id}", status_code=303)


@app.get("/proxy/{user_id}", response_class=HTMLResponse)
def proxy_detail(
    user_id: int,
    request: Request,
    admin: AdminUser = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    pu = db.get(ProxyUser, user_id)
    if not pu:
        raise HTTPException(404)
    node = db.get(Node, pu.node_id)
    mob_name = f"{pu.username}-mob" if pu.has_wifi and pu.has_mobile else pu.username
    qr_wifi = qr_png_path(pu.username, "wifi")
    qr_mobile = qr_png_path(mob_name, "mobile")
    flash_err = request.query_params.get("err")
    return templates.TemplateResponse(
        "proxy_detail.html",
        {
            "request": request,
            "title": APP_TITLE,
            "admin": admin,
            "user": pu,
            "node": node,
            "qr_wifi": qr_wifi.name if qr_wifi else None,
            "qr_mobile": qr_mobile.name if qr_mobile else None,
            "flash_err": flash_err,
        },
    )


@app.post("/proxy/{user_id}/delete")
async def proxy_delete(
    user_id: int,
    admin: AdminUser = Depends(get_current_admin),
    db: Session = Depends(get_db),
    _: None = Depends(require_form_csrf),
):
    pu = db.get(ProxyUser, user_id)
    if not pu:
        raise HTTPException(404)
    node = db.get(Node, pu.node_id)
    if not node:
        raise HTTPException(400, "Нода не найдена")

    if node.role == "local":
        result = await asyncio.to_thread(
            delete_local_client,
            pu.username,
            wifi=pu.has_wifi,
            mobile=pu.has_mobile,
        )
    else:
        if not node.api_token:
            raise HTTPException(400, "Удалённая нода недоступна")
        if remote_uses_job_queue(node):
            job = create_delete_job(
                db,
                node_id=node.id,
                username=pu.username,
                wifi=pu.has_wifi,
                mobile=pu.has_mobile,
            )
            try:
                job = await wait_for_job(job.id)
            except TimeoutError as e:
                result = ProvisionResult(False, str(e))
            else:
                if job.status == "failed":
                    result = ProvisionResult(False, job.error_message or "Ошибка на agent")
                else:
                    result = ProvisionResult(True, "Конфиг удалён на удалённой ноде")
        else:
            if not node.api_base:
                raise HTTPException(400, "Удалённая нода недоступна")
            result = await delete_remote_client(
                node.api_base,
                node.api_token,
                pu.username,
                wifi=pu.has_wifi,
                mobile=pu.has_mobile,
            )

    if not result.ok:
        return RedirectResponse(
            f"/proxy/{user_id}?err={quote(result.message[:180])}",
            status_code=303,
        )
    db.delete(pu)
    db.commit()
    return RedirectResponse("/proxy?msg=Клиент удалён", status_code=303)


@app.get("/qr/{filename}")
def serve_qr(filename: str, admin: AdminUser = Depends(get_current_admin)):
    if not re.match(r"^[a-zA-Z0-9._-]+\.png$", filename):
        raise HTTPException(400)
    path = QR_DIR / filename
    if not path.is_file():
        raise HTTPException(404)
    return FileResponse(path, media_type="image/png")


@app.get("/certs", response_class=HTMLResponse)
def certs_page(
    request: Request,
    admin: AdminUser = Depends(get_current_admin),
    db: Session = Depends(get_db),
    msg: str | None = None,
    err: str | None = None,
):
    data = all_cert_status()
    settings = get_settings(db)
    tls = {}
    tls_env = VLESS_CONFIG_DIR / "tls.env"
    if tls_env.is_file():
        for line in tls_env.read_text().splitlines():
            if line.startswith("PUBLIC_HOST="):
                tls["public_host"] = line.split("=", 1)[1].strip()
            if line.startswith("LE_EMAIL="):
                tls["email"] = line.split("=", 1)[1].strip()
    return templates.TemplateResponse(
        "certs.html",
        {
            "request": request,
            "title": APP_TITLE,
            "admin": admin,
            "data": data,
            "settings": settings,
            "tls": tls,
            "flash_ok": msg,
            "flash_err": err,
        },
    )


@app.post("/certs/renew")
async def certs_renew(
    admin: AdminUser = Depends(get_current_admin),
    db: Session = Depends(get_db),
    _: None = Depends(require_form_csrf),
    cert_name: str = Form(""),
):
    result = await asyncio.to_thread(renew_certificates, cert_name.strip() or None)
    from app.services.notify import notify_admin

    settings = get_settings(db)
    await notify_admin(settings, "Сертификат: renew", result.message)
    if result.ok:
        return RedirectResponse(f"/certs?msg={quote(result.message[:200])}", status_code=303)
    return RedirectResponse(f"/certs?err={quote(result.message[:200])}", status_code=303)


@app.post("/certs/reissue")
async def certs_reissue(
    admin: AdminUser = Depends(get_current_admin),
    db: Session = Depends(get_db),
    _: None = Depends(require_form_csrf),
    domain: str = Form(...),
    email: str = Form(""),
):
    result = await asyncio.to_thread(reissue_new_domain, domain, email.strip() or None)
    from app.services.notify import notify_admin

    settings = get_settings(db)
    await notify_admin(settings, "Сертификат: новый DNS", result.message)
    if result.ok:
        return RedirectResponse(f"/certs?msg={quote(result.message[:200])}", status_code=303)
    return RedirectResponse(f"/certs?err={quote(result.message[:200])}", status_code=303)


@app.post("/certs/sync-hysteria")
async def certs_sync_hysteria(
    admin: AdminUser = Depends(get_current_admin),
    _: None = Depends(require_form_csrf),
):
    result = await asyncio.to_thread(sync_hysteria_from_le)
    if result.ok:
        return RedirectResponse(f"/certs?msg={result.message}", status_code=303)
    return RedirectResponse(f"/certs?err={result.message[:200]}", status_code=303)


@app.post("/certs/settings")
def certs_settings(
    admin: AdminUser = Depends(get_current_admin),
    db: Session = Depends(get_db),
    _: None = Depends(require_form_csrf),
    auto_renew: str | None = Form(None),
    auto_renew_days: int = Form(3),
):
    settings = get_settings(db)
    settings.auto_renew_enabled = auto_renew == "on"
    settings.auto_renew_days = max(1, min(30, auto_renew_days))
    db.commit()
    return RedirectResponse("/certs?msg=Настройки автопродления сохранены", status_code=303)


@app.get("/profile", response_class=HTMLResponse)
def profile_page(
    request: Request,
    admin: AdminUser = Depends(get_current_admin),
    db: Session = Depends(get_db),
    msg: str | None = None,
    err: str | None = None,
):
    settings = get_settings(db)
    return templates.TemplateResponse(
        "profile.html",
        {
            "request": request,
            "title": APP_TITLE,
            "admin": admin,
            "settings": settings,
            "flash_ok": msg,
            "flash_err": err,
        },
    )


@app.post("/profile/password")
def profile_password(
    admin: AdminUser = Depends(get_current_admin),
    db: Session = Depends(get_db),
    _: None = Depends(require_form_csrf),
    current_password: str = Form(...),
    new_password: str = Form(...),
    new_password2: str = Form(...),
):
    if not verify_password(current_password, admin.password_hash):
        return RedirectResponse("/profile?err=Неверный текущий пароль", status_code=303)
    if len(new_password) < 6 or not validate_password_length(new_password):
        return RedirectResponse("/profile?err=Новый пароль ≥ 6 символов", status_code=303)
    if new_password != new_password2:
        return RedirectResponse("/profile?err=Пароли не совпадают", status_code=303)
    admin.password_hash = hash_password(new_password)
    db.commit()
    return RedirectResponse("/profile?msg=Пароль изменён", status_code=303)


@app.post("/profile/notifications")
def profile_notifications(
    admin: AdminUser = Depends(get_current_admin),
    db: Session = Depends(get_db),
    _: None = Depends(require_form_csrf),
    telegram_bot_token: str = Form(""),
    telegram_chat_id: str = Form(""),
    notify_email: str = Form(""),
    notify_on_cert: str | None = Form(None),
    smtp_host: str = Form(""),
    smtp_port: int = Form(587),
    smtp_user: str = Form(""),
    smtp_password: str = Form(""),
    smtp_security: str = Form("starttls"),
    smtp_from_email: str = Form(""),
):
    settings = get_settings(db)
    settings.telegram_bot_token = telegram_bot_token.strip()
    settings.telegram_chat_id = telegram_chat_id.strip()
    settings.notify_email = notify_email.strip()
    settings.notify_on_cert = notify_on_cert == "on"
    settings.smtp_host = smtp_host.strip()
    settings.smtp_port = max(1, min(65535, int(smtp_port or 587)))
    settings.smtp_user = smtp_user.strip()
    if smtp_password.strip():
        settings.smtp_password = smtp_password.strip()
    sec = smtp_security.strip().lower()
    settings.smtp_security = sec if sec in ("none", "starttls", "ssl") else "starttls"
    settings.smtp_from_email = smtp_from_email.strip()
    db.commit()
    return RedirectResponse("/profile?msg=Оповещения сохранены", status_code=303)


# --- Agent API ---


@app.get("/api/v1/health")
def api_health():
    return {"ok": True, "service": "vless-panel"}


def _authorize_agent_api(request: Request, db: Session) -> None:
    import os

    auth = request.headers.get("Authorization")
    token = ""
    if auth and auth.startswith("Bearer "):
        token = auth.removeprefix("Bearer ").strip()
    expected = os.environ.get("VLESS_PANEL_AGENT_TOKEN", "").strip()
    if expected and token and secrets.compare_digest(token, expected):
        return
    if token and _node_by_agent_token(db, token):
        return
    raise HTTPException(403, "Invalid agent token")


@app.get("/api/v1/ports")
def api_ports(request: Request, db: Session = Depends(get_db)):
    _authorize_agent_api(request, db)
    return port_status()


@app.get("/api/v1/username-available")
def api_username_available(
    request: Request,
    db: Session = Depends(get_db),
    username: str = "",
    wifi: str = "true",
    mobile: str = "true",
):
    _authorize_agent_api(request, db)
    from app.services.name_check import validate_new_username

    do_wifi = wifi.lower() in ("1", "true", "yes", "on")
    do_mobile = mobile.lower() in ("1", "true", "yes", "on")
    ok, reason = validate_new_username(username.strip(), wifi=do_wifi, mobile=do_mobile)
    if ok:
        return {"available": True}
    return {"available": False, "reason": reason}


@app.get("/api/v1/agent/install.sh")
def api_agent_install_sh(token: str, request: Request, db: Session = Depends(get_db)):
    node = _node_by_agent_token(db, token)
    if not node:
        raise HTTPException(404, "Invalid token")
    master = get_master_public_url(request)
    return Response(
        content=render_agent_install_script(
            master_url=master,
            node_token=token,
            node_name=node.name,
        ),
        media_type="text/plain; charset=utf-8",
    )


def _bundle_paths() -> list[tuple[str, Path]]:
    panel_src = REPO_PANEL
    if not (panel_src / "install_panel.sh").is_file():
        panel_src = Path("/opt/vless-manager/panel")
    mgr = REPO_ROOT / "vless_manager.sh"
    if not mgr.is_file():
        mgr = Path("/opt/vless-manager/vless_manager.sh")
    items: list[tuple[str, Path]] = []
    if panel_src.is_dir():
        for p in panel_src.rglob("*"):
            if p.is_file() and "venv" not in p.parts and "__pycache__" not in p.parts:
                items.append((f"panel/{p.relative_to(panel_src)}", p))
    if mgr.is_file():
        items.append(("vless_manager.sh", mgr))
    inst = REPO_ROOT / "install_vless_manager.sh"
    if not inst.is_file():
        inst = Path("/opt/vless-manager/install_vless_manager.sh")
    if inst.is_file():
        items.append(("install_vless_manager.sh", inst))
    vss = REPO_ROOT / "vless-servers-script.sh"
    if vss.is_file():
        items.append(("vless-servers-script.sh", vss))
    return items


@app.get("/api/v1/agent/next-job")
def api_agent_next_job(request: Request, db: Session = Depends(get_db)):
    node = _agent_node_from_request(request, db)
    if not node:
        raise HTTPException(403, "Invalid agent token")
    reclaim_stale_jobs(db)
    job = (
        db.query(AgentJob)
        .filter(AgentJob.node_id == node.id, AgentJob.status == "pending")
        .order_by(AgentJob.id.asc())
        .first()
    )
    if not job:
        return Response(status_code=204)
    job.status = "processing"
    job.updated_at = datetime.utcnow()
    node.last_seen = datetime.utcnow()
    if node.agent_status != "online":
        node.agent_status = "online"
    db.commit()
    return {
        "id": job.id,
        "job_type": job.job_type,
        "username": job.username,
        "has_wifi": job.has_wifi,
        "has_mobile": job.has_mobile,
    }


@app.post("/api/v1/agent/job-result")
async def api_agent_job_result(request: Request, db: Session = Depends(get_db)):
    node = _agent_node_from_request(request, db)
    if not node:
        raise HTTPException(403, "Invalid agent token")
    body = await request.json()
    job_id = body.get("job_id")
    job = db.get(AgentJob, job_id)
    if not job or job.node_id != node.id:
        raise HTTPException(404, "Job not found")
    if body.get("ok"):
        job.status = "done"
        job.error_message = None
        job.wifi_vless_url = body.get("wifi_vless_url")
        job.mobile_vless_url = body.get("mobile_vless_url")
        job.hysteria_url = body.get("hysteria_url")
        job.wifi_port = body.get("wifi_port")
        job.uuid = body.get("uuid")
    else:
        job.status = "failed"
        job.error_message = (body.get("error_message") or "failed")[:4000]
    job.updated_at = datetime.utcnow()
    node.last_seen = datetime.utcnow()
    db.commit()
    return {"ok": True}


@app.get("/api/v1/agent/admin-sync")
def api_agent_admin_sync(token: str, db: Session = Depends(get_db)):
    node = _node_by_agent_token(db, token)
    if not node:
        raise HTTPException(403, "Invalid token")
    admin = db.query(AdminUser).order_by(AdminUser.id.asc()).first()
    if not admin:
        raise HTTPException(503, "Admin user not configured on master")
    return {"username": admin.username, "password_hash": admin.password_hash}


@app.get("/api/v1/agent/bundle.tar.gz")
def api_agent_bundle(token: str, db: Session = Depends(get_db)):
    node = _node_by_agent_token(db, token)
    if not node:
        raise HTTPException(403, "Invalid token")
    items = _bundle_paths()
    if not items:
        raise HTTPException(500, "Bundle sources not found on master")
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        for arcname, path in items:
            tar.add(path, arcname=arcname)
    buf.seek(0)
    return Response(content=buf.getvalue(), media_type="application/gzip")


@app.post("/api/v1/nodes/register")
async def api_nodes_register(request: Request, db: Session = Depends(get_db)):
    body = await request.json()
    token = (body.get("token") or "").strip()
    node = _node_by_agent_token(db, token)
    if not node:
        raise HTTPException(404, "Unknown token")
    node.public_ip = (body.get("public_ip") or node.public_ip or "").strip()
    incoming_domain = (body.get("domain") or "").strip()
    if incoming_domain:
        placeholder = f"{node.slug}.local"
        if not node.domain or node.domain.endswith(".local") or node.domain == placeholder:
            node.domain = incoming_domain
    if body.get("country") and not node.country:
        node.country = body["country"].strip()
    api_base = (body.get("api_base") or "").strip()
    if api_base:
        node.api_base = api_base.rstrip("/")
    elif node.public_ip:
        node.api_base = f"http://{node.public_ip}:8765"
    node.agent_status = "online"
    node.is_active = True
    node.last_seen = datetime.utcnow()
    db.commit()
    return {
        "ok": True,
        "node_id": node.id,
        "name": node.name,
        "vpn_domain": node.domain,
    }


@app.get("/api/v1/agent/node-config")
def api_agent_node_config(request: Request, db: Session = Depends(get_db)):
    node = _agent_node_from_request(request, db)
    if not node:
        raise HTTPException(403, "Invalid agent token")
    return {
        "vpn_domain": node.domain,
        "country": node.country or node.region,
        "name": node.name,
    }


@app.post("/api/v1/nodes/install-failed")
async def api_nodes_install_failed(request: Request, db: Session = Depends(get_db)):
    body = await request.json()
    token = (body.get("token") or "").strip()
    node = _node_by_agent_token(db, token)
    if not node:
        raise HTTPException(404, "Unknown token")
    if node.agent_status == "online":
        return {"ok": True, "ignored": True, "reason": "already online"}
    node.agent_status = "error"
    node.is_active = False
    node.last_seen = datetime.utcnow()
    db.commit()
    return {"ok": True, "node_id": node.id, "agent_status": node.agent_status}


@app.post("/api/v1/delete")
async def api_delete(
    request: Request,
    db: Session = Depends(get_db),
):
    _authorize_agent_api(request, db)
    body = await request.json()
    username = body.get("username", "")
    wifi = bool(body.get("wifi", True))
    mobile = bool(body.get("mobile", True))
    result = delete_local_client(username, wifi=wifi, mobile=mobile)
    if not result.ok:
        raise HTTPException(400, result.message)
    return {"ok": True}


@app.post("/api/v1/provision")
async def api_provision(
    request: Request,
    db: Session = Depends(get_db),
):
    _authorize_agent_api(request, db)
    body = await request.json()
    username = body.get("username", "")
    wifi = bool(body.get("wifi"))
    mobile = bool(body.get("mobile"))
    from app.services.ports import ensure_can_provision

    ok, msg = ensure_can_provision(wifi=wifi, mobile=mobile)
    if not ok:
        raise HTTPException(400, msg)
    result = provision_local(username, wifi=wifi, mobile=mobile)
    if not result.ok:
        raise HTTPException(400, result.message)
    return {
        "wifi_vless_url": result.wifi_vless_url,
        "mobile_vless_url": result.mobile_vless_url,
        "hysteria_url": result.hysteria_url,
        "wifi_port": result.wifi_port,
        "uuid": result.uuid,
    }


@app.get("/", include_in_schema=False)
def root(admin: AdminUser | None = Depends(get_optional_admin)):
    if admin:
        return RedirectResponse("/dashboard", status_code=303)
    return RedirectResponse("/login", status_code=303)
