# VLESS Manager Pro — Web Panel

Веб-панель для **multi-node** выдачи конфигов: VLESS (Wi‑Fi / REALITY) + **Hysteria2**, QR-коды, статус Let's Encrypt.

## Установка

**Рекомендуется** — вместе с VLESS Manager:

```bash
sudo ./install_vless_manager.sh
```

Только панель (если Xray уже стоит):

```bash
chmod +x panel/install_panel.sh && sudo ./panel/install_panel.sh
```

Службы: `vless-panel.service`, `vless-agent.service` (alias), `systemctl enable --now vless-panel`.

Откройте **http://IP:8765** (или проксируйте через nginx на 443).

Первый вход на `/login` создаёт учётку администратора.

## Разделы

| Страница | Назначение |
|----------|------------|
| **Proxy** | Создать пользователя на выбранной ноде → ссылки + QR |
| **Ноды** | Локальная нода + регистрация удалённых серверов |
| **Сертификаты** | `certbot certificates`, срок действия, копия для Hysteria |

## Multi-node

1. На каждом VPS: VPN (kibervpn/deploy) + `install_panel.sh`.
2. На **master** в «Ноды» добавьте сервер: API URL `http://IP:8765`, token из `/etc/vless-manager/panel/agent.env` (`VLESS_PANEL_AGENT_TOKEN`).
3. Создание клиента на удалённой ноде вызывает `POST /api/v1/provision` на агенте.

Локальная нода (`role=local`) провision через `vless_manager.sh cli create-wifi|create-mobile`.

## Безопасность

- Панель слушает `0.0.0.0:8765` — закройте firewall или повесьте nginx + TLS + basic auth.
- Не публикуйте agent token.

## Переменные окружения

| Переменная | Описание |
|------------|----------|
| `VLESS_PANEL_PORT` | Порт (8765) |
| `VLESS_PANEL_AGENT_TOKEN` | Bearer для API provision |
| `VLESS_MANAGER_SH` | Путь к vless_manager.sh |
