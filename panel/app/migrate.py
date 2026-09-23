from __future__ import annotations

from sqlalchemy import inspect, text

from app.database import engine


def _add_column(conn, table: str, column: str, ddl: str) -> None:
    cols = {c["name"] for c in inspect(engine).get_columns(table)}
    if column in cols:
        return
    conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {ddl}"))


def run_migrations() -> None:
    with engine.begin() as conn:
        _add_column(conn, "nodes", "country", "country VARCHAR(128) DEFAULT ''")
        _add_column(conn, "nodes", "public_ip", "public_ip VARCHAR(45) DEFAULT ''")
        _add_column(conn, "nodes", "agent_status", "agent_status VARCHAR(16) DEFAULT 'online'")
        _add_column(conn, "nodes", "last_seen", "last_seen DATETIME")
        _add_column(conn, "proxy_users", "exit_country", "exit_country VARCHAR(128) DEFAULT ''")
        _add_column(conn, "proxy_users", "exit_ip", "exit_ip VARCHAR(45) DEFAULT ''")
