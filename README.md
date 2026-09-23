# VLESS Manager Pro

Платформа для развёртывания VPN на **Xray-core**: выдача конфигов **VLESS** (Wi‑Fi / LTE), **Hysteria2**, **REALITY**, QR-коды, **web-панель**, **multi-node** через агентов, **systemd**, Let's Encrypt.

Репозиторий: [github.com/sweetpotatohack/vless-manager](https://github.com/sweetpotatohack/vless-manager)

---

## Что входит в проект

| Компонент | Назначение |
|-----------|------------|
| **`install_vless_manager.sh`** | Единая установка: Xray, TLS, firewall, sample-клиент, **web-панель**, systemd |
| **`vless_manager.sh`** | CLI/меню: клиенты, mobile (REALITY + Hy2), QR, iptables |
| **`vless-servers`** | Запуск/остановка inbound Xray по конфигам клиентов |
| **`panel/`** | Web **Control Panel** (FastAPI): Proxy, ноды, сертификаты, кабинет админа |
| **Агент на VPS** | Удалённая нода: API + те же скрипты, регистрация на master |

### Профили для клиентов

| Профиль | Протокол | Порт | Когда использовать |
|---------|----------|------|---------------------|
| **Wi‑Fi** | VLESS + TLS (LE) | 25000–45000/tcp | Дом, офис, Wi‑Fi |
| **LTE (основной)** | Hysteria2 | 25001/udp | Мобильный интернет (как kibervpn) |
| **LTE (запасной)** | VLESS + REALITY + Vision | 443/tcp | Если UDP режут |

Формат Hy2: `hysteria2://PASSWORD@domain:25001?sni=domain`

---

## Требования

- **ОС:** Debian / Ubuntu (рекомендуется) или RHEL/CentOS family  
- **Права:** root  
- **DNS (Let's Encrypt):** A-запись домена → IPv4 VPS; без «левого» AAAA; Cloudflare — **DNS only**  
- **Порты:** 80/tcp (выпуск LE), 443/tcp (REALITY), 25001/udp (Hy2), 25000–45000/tcp (VLESS Wi‑Fi), **8765/tcp** (панель)  
- **Git** на сервере для clone

---

## Установка (master / один сервер)

```bash
git clone --depth 1 https://github.com/sweetpotatohack/vless-manager.git
cd vless-manager
chmod +x install_vless_manager.sh
sudo ./install_vless_manager.sh
```

Одной строкой:

```bash
git clone --depth 1 https://github.com/sweetpotatohack/vless-manager.git /tmp/vless-manager \
  && cd /tmp/vless-manager && chmod +x install_vless_manager.sh && sudo ./install_vless_manager.sh
```

Установщик:

1. Ставит **Xray**, зависимости (`sqlite3`, `qrencode`, `certbot` при LE)  
2. Создаёт `/etc/vless-manager`, sample-клиент  
3. Регистрирует **`vless-xray.service`** (автозапуск inbound)  
4. Вызывает **`panel/install_panel.sh`** → **`vless-panel.service`** + **`vless-agent.service`**

### TLS при установке

- Введите **домен** и **email** → Let's Encrypt (standalone :80) → `/etc/vless-manager/tls.env`  
- **Enter** без домена → самоподпись (в клиентах **Allow Insecure**)

Без TTY (скрипт из pipe) → самоподпись автоматически.

### После установки

| Действие | Команда / URL |
|----------|----------------|
| Web-панель | `http://ВАШ_IP:8765/login` |
| Логин по умолчанию | `admin` / `admin` (смените в **Кабинет**) |
| CLI-меню | `vless-manager` |
| Статус Xray | `systemctl status vless-xray` |
| Статус панели | `systemctl status vless-panel` |
| Процессы клиентов | `vless-servers status` |

---

## Systemd (автозапуск)

| Служба | Описание |
|--------|----------|
| `vless-xray.service` | Поднимает все VLESS inbound из `/etc/vless-manager/clients/` |
| `vless-panel.service` | Web Control Panel + API агента (:8765) |
| `vless-agent.service` | Alias той же unit (удобно на remote-нодах) |
| `xray-reality.service` | Отдельный REALITY :443 (mobile, если настроен) |
| `hysteria-server.service` | Hysteria2 :25001 (если настроен) |

```bash
sudo systemctl enable --now vless-xray vless-panel
sudo systemctl restart vless-panel
journalctl -u vless-panel -f
journalctl -u vless-xray -f
```

---

## Web Control Panel

### Разделы

| Вкладка | Функции |
|---------|---------|
| **Обзор** | Ноды, число клиентов, срок сертификатов |
| **Proxy** | Имя пользователя → выбор **ноды / страны / IP** → Wi‑Fi и/или LTE → ссылки + QR |
| **Ноды** | Master-страна, **генерация агента** (install.sh + token), список нод |
| **Сертификаты** | Продление LE, перевыпуск на новый DNS, sync Hy2, **автопродление** (≤ N дней) |
| **Кабинет** | Смена пароля, Telegram / email оповещения |

### Выдача конфига (Proxy)

1. **Proxy** → имя (латиница)  
2. Выберите ноду (страна и IP выхода)  
3. Отметьте **Wi‑Fi** и/или **LTE**  
4. Дождитесь генерации (до ~30–90 с)

Перед созданием проверяются **занятые порты** на ноде (`ss` + конфиги клиентов). На удалённой ноде master запрашивает `GET /api/v1/ports` у агента.

### v2rayTun (LTE)

- Сначала импорт **Hysteria2**  
- **Private DNS — ВЫКЛ**, **MUX — ВЫКЛ**  
- REALITY :443 — запасной профиль  

---

## Multi-node (удалённые VPS)

### На master (панель «Ноды»)

1. **Сгенерировать агент** — имя, страна, домен (опционально)  
2. Скопируйте команду на **новый Linux VPS (root)**:

```bash
curl -fsSL 'http://MASTER:8765/api/v1/agent/install.sh?token=TOKEN' | bash
```

3. После установки нода станет **online** и появится в **Proxy**

### Что делает install-скрипт агента

- Качает bundle с master  
- Запускает **`install_vless_manager.sh --remote-agent`**: Xray, `vless-xray`, panel, token  
- Регистрируется: `POST /api/v1/nodes/register`  
- Включает **systemd** `vless-panel` / `vless-agent`

### Firewall на agent-ноде

Откройте минимум: **8765/tcp** (API с master), **25000–45000/tcp**, **443/tcp**, **25001/udp**.

### Agent token

Файл на ноде: `/etc/vless-manager/panel/agent.env` → `VLESS_PANEL_AGENT_TOKEN=...`  
Не публикуйте token; master использует его при `POST /api/v1/provision`.

---

## CLI (`vless_manager.sh`)

Интерактивно:

```bash
vless-manager
# 1  — Wi‑Fi VLESS+TLS (новый порт)
# 10 — LTE: REALITY :443 + Hysteria2 :25001
```

Без меню (для панели и automation):

```bash
/opt/vless-manager/vless_manager.sh cli create-wifi USERNAME
/opt/vless-manager/vless_manager.sh cli create-mobile USERNAME
/opt/vless-manager/vless_manager.sh repair-ports
```

---

## Сертификаты

| Где | Путь / действие |
|-----|-----------------|
| LE live | `/etc/letsencrypt/live/DOMAIN/` |
| Настройки TLS | `/etc/vless-manager/tls.env` |
| Hysteria copy | `/etc/hysteria/certs/` |
| Панель | **Сертификаты** → продление / новый DNS / sync / автопродление |

CLI:

```bash
certbot certificates
certbot renew --dry-run
systemctl status certbot.timer
```

После renew скопируйте certs в Hysteria (кнопка в панели или hook в `/etc/letsencrypt/renewal-hooks/post/`).

---

## API агента (Bearer token)

| Метод | URL | Описание |
|-------|-----|----------|
| GET | `/api/v1/health` | Жив ли сервис |
| GET | `/api/v1/ports` | Слушающие и занятые порты, свободный Wi‑Fi порт |
| POST | `/api/v1/provision` | `{ "username", "wifi", "mobile" }` → ссылки |
| POST | `/api/v1/nodes/register` | Регистрация agent-ноды (из install.sh) |
| GET | `/api/v1/agent/install.sh?token=` | Bootstrap-скрипт |
| GET | `/api/v1/agent/bundle.tar.gz?token=` | Архив для агента |

Заголовок: `Authorization: Bearer TOKEN`

---

## Файлы на сервере

```
/opt/vless-manager/
├── vless_manager.sh          # основной скрипт
├── install_vless_manager.sh
└── panel/                    # код web-панели

/etc/vless-manager/
├── tls.env                   # LE или selfsigned
├── clients/*.json            # inbound Xray (Wi‑Fi)
├── urls/*.txt                # VLESS / hy2 ссылки
├── qr-codes/*.png
├── mobile-reality/*.uuid     # клиенты REALITY hub
├── panel/                    # panel.db, secret.key, agent.env
└── clients.db                # SQLite (CLI)

/etc/systemd/system/
├── vless-xray.service
├── vless-panel.service
└── vless-agent.service
```

---

## Клиентские приложения

- **PC:** [v2rayN](https://github.com/2dust/v2rayN) — импорт URL или QR  
- **Android:** v2rayNG, v2rayTun  
- **iOS:** Shadowrocket, v2rayTun  

Ссылки лежат в `/etc/vless-manager/urls/` и в web-панели после создания пользователя.

---

## Только web-панель (Xray уже установлен)

```bash
cd vless-manager
chmod +x panel/install_panel.sh
sudo ./panel/install_panel.sh
```

---

## Только remote-agent (bundle уже распакован)

```bash
export VLESS_PANEL_AGENT_TOKEN='token_с_master'
export VLESS_PANEL_MASTER_URL='http://master:8765'
sudo ./install_vless_manager.sh --remote-agent
```

---

## Обновление с GitHub

```bash
sudo cp -a /etc/vless-manager /etc/vless-manager.backup.$(date +%F)

cd /path/to/vless-manager
git pull
sudo ./install_vless_manager.sh   # или только panel/install_panel.sh
sudo systemctl restart vless-xray vless-panel
```

---

## Переменные окружения (панель)

| Переменная | По умолчанию | Описание |
|------------|--------------|----------|
| `VLESS_PANEL_PORT` | 8765 | Порт HTTP |
| `VLESS_PANEL_MASTER_URL` | auto | URL master для агентов |
| `VLESS_PANEL_AGENT_TOKEN` | random | Bearer API на ноде |
| `VLESS_PANEL_ROLE` | master / agent | Тип установки |
| `VLESS_MANAGER_SH` | /opt/vless-manager/vless_manager.sh | Путь к CLI |

---

## Безопасность

- Смените пароль **admin** сразу после установки (**Кабинет**).  
- Не выставляйте **8765** в интернет без nginx + TLS или VPN; ограничьте IP в firewall.  
- Не коммитьте `agent.env`, `tls.env`, `clients.db` с секретами.  
- Отзывайте скомпрометированные GitHub PAT / agent token.

---

## Логи и отладка

```bash
tail -f /var/log/vless-manager.log
journalctl -u vless-panel -u vless-xray -u hysteria-server -u xray-reality -f
ss -tulnp | egrep ':(443|8765|25001|250[0-9]{2})'
curl -sS http://127.0.0.1:8765/api/v1/health
```

---

## Лицензия

См. [LICENSE](LICENSE). Автор CLI/форка: AKUMA0xDEAD; развитие panel/multi-node — [sweetpotatohack/vless-manager](https://github.com/sweetpotatohack/vless-manager).
