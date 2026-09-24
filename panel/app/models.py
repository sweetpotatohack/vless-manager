from __future__ import annotations

import datetime as dt

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class AdminUser(Base):
    __tablename__ = "admin_users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    username: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[dt.datetime] = mapped_column(
        DateTime, default=lambda: dt.datetime.utcnow()
    )


class PanelSettings(Base):
    __tablename__ = "panel_settings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    auto_renew_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    auto_renew_days: Mapped[int] = mapped_column(Integer, default=3)
    telegram_bot_token: Mapped[str] = mapped_column(String(256), default="")
    telegram_chat_id: Mapped[str] = mapped_column(String(64), default="")
    notify_email: Mapped[str] = mapped_column(String(256), default="")
    notify_on_cert: Mapped[bool] = mapped_column(Boolean, default=True)
    smtp_host: Mapped[str] = mapped_column(String(255), default="")
    smtp_port: Mapped[int] = mapped_column(Integer, default=587)
    smtp_user: Mapped[str] = mapped_column(String(255), default="")
    smtp_password: Mapped[str] = mapped_column(String(512), default="")
    smtp_security: Mapped[str] = mapped_column(String(16), default="starttls")
    smtp_from_email: Mapped[str] = mapped_column(String(256), default="")


class Node(Base):
    __tablename__ = "nodes"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(128))
    slug: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    domain: Mapped[str] = mapped_column(String(255))
    region: Mapped[str] = mapped_column(String(64), default="local")
    country: Mapped[str] = mapped_column(String(128), default="")
    public_ip: Mapped[str] = mapped_column(String(45), default="")
    agent_status: Mapped[str] = mapped_column(String(16), default="pending")
    last_seen: Mapped[dt.datetime | None] = mapped_column(DateTime, nullable=True)
    metric_cpu: Mapped[float | None] = mapped_column(Float, nullable=True)
    metric_mem: Mapped[float | None] = mapped_column(Float, nullable=True)
    metric_disk: Mapped[float | None] = mapped_column(Float, nullable=True)
    metrics_at: Mapped[dt.datetime | None] = mapped_column(DateTime, nullable=True)
    role: Mapped[str] = mapped_column(String(16), default="local")
    api_base: Mapped[str | None] = mapped_column(String(512), nullable=True)
    api_token: Mapped[str | None] = mapped_column(String(128), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    hysteria_port: Mapped[int] = mapped_column(Integer, default=25001)
    reality_port: Mapped[int] = mapped_column(Integer, default=443)
    created_at: Mapped[dt.datetime] = mapped_column(
        DateTime, default=lambda: dt.datetime.utcnow()
    )

    proxy_users: Mapped[list["ProxyUser"]] = relationship(back_populates="node")


class ProxyUser(Base):
    __tablename__ = "proxy_users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    node_id: Mapped[int] = mapped_column(ForeignKey("nodes.id"), index=True)
    username: Mapped[str] = mapped_column(String(64), index=True)
    has_wifi: Mapped[bool] = mapped_column(Boolean, default=True)
    has_mobile: Mapped[bool] = mapped_column(Boolean, default=True)
    wifi_vless_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    mobile_vless_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    hysteria_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    wifi_port: Mapped[int | None] = mapped_column(Integer, nullable=True)
    uuid: Mapped[str | None] = mapped_column(String(64), nullable=True)
    exit_country: Mapped[str] = mapped_column(String(128), default="")
    exit_ip: Mapped[str] = mapped_column(String(45), default="")
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[dt.datetime] = mapped_column(
        DateTime, default=lambda: dt.datetime.utcnow()
    )

    node: Mapped["Node"] = relationship(back_populates="proxy_users")


class AgentJob(Base):
    """Задачи для remote-нод (agent забирает с master — работает за NAT)."""

    __tablename__ = "agent_jobs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    node_id: Mapped[int] = mapped_column(ForeignKey("nodes.id"), index=True)
    job_type: Mapped[str] = mapped_column(String(16), default="provision")
    username: Mapped[str] = mapped_column(String(64))
    has_wifi: Mapped[bool] = mapped_column(Boolean, default=True)
    has_mobile: Mapped[bool] = mapped_column(Boolean, default=True)
    status: Mapped[str] = mapped_column(String(16), default="pending", index=True)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    wifi_vless_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    mobile_vless_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    hysteria_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    wifi_port: Mapped[int | None] = mapped_column(Integer, nullable=True)
    uuid: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[dt.datetime] = mapped_column(
        DateTime, default=lambda: dt.datetime.utcnow()
    )
    updated_at: Mapped[dt.datetime | None] = mapped_column(DateTime, nullable=True)
