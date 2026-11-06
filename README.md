# VLESS Manager Pro

Платформа для развёртывания VPN на **Hysteria2** + **VLESS**: телефонный Hysteria2-профиль (Wi‑Fi и мобильный интернет) и отдельный PC VLESS для NekoRay, QR-коды, **web-панель**, **multi-node** через агентов, **systemd**, Let's Encrypt.

Репозиторий: [github.com/sweetpotatohack/vless-manager](https://github.com/sweetpotatohack/vless-manager)

---

## Что это

| Компонент | Назначение |
|-----------|------------|
| **`install_vless_manager.sh`** | Единая установка: Hysteria2, TLS, firewall, sample-клиент, web-панель, systemd |
| **`vless_manager.sh`** | CLI/меню: Hysteria2 + PC VLESS + Cloudflare-профили, QR |
| **`panel/`** | Web **Control Panel** (FastAPI): Proxy, ноды, сертификаты, кабинет админа |
| **Агент на VPS** | Удалённая нода: тот же стек + API для master |

### Профили клиента

Для каждого пользователя выдаётся **два независимых профиля**: телефонный Hysteria2 и PC VLESS. Hysteria2 не трогается, когда добавляется VLESS.

| Профиль | Протокол | Порт клиента | Для кого |
|---------|----------|--------------|----------|
| **Hysteria2** | Hysteria2 (UDP/QUIC) | 25001/udp | Телефон: Wi‑Fi и мобильный интернет |
| **PC VLESS** | VLESS + TCP + TLS (Xray) | 25000–45000/tcp | ПК: NekoRay / v2rayN |

```text
# Телефон (Hysteria2):
hysteria2://user:password@IP:25001/?sni=your.domain&obfs=salamander&obfs-password=OBFS#user

# ПК (VLESS TCP+TLS):
vless://UUID@IP:PORT?encryption=none&security=tls&sni=your.domain&fp=chrome&type=tcp#user-pc
```

Плюс два QR-кода: Hysteria2 (`<user>.png`) и PC VLESS (`<user>-pc.png`).

**Почему Hysteria2 для телефона:**
- **UDP/QUIC** — мобильные операторы режут TCP/443 агрессивнее, чем UDP;
- **обфускация Salamander** — прячет QUIC-рукопожатие от DPI;
- один конфиг для всех сетей, у каждого клиента свой логин/пароль.

**Почему отдельный VLESS для ПК:**
- NekoRay/sing-box на Windows при Hysteria2 с TUN может сыпать `inbound/tun: authentication failed, status code: 404` и не давать интернет;
- VLESS + TCP + TLS работает в NekoRay/v2rayN штатно, без TUN-тюнинга;
- живёт на отдельном TCP-порту и не ломает рабочий Hysteria2.

> **Домен за Cloudflare (оранжевое облако).** Cloudflare не проксирует произвольные TCP-порты, поэтому PC VLESS (TCP+TLS) в `vless://`/QR автоматически получает **прямой IP сервера**, а `sni=` остаётся доменом (под LE-сертификат). Если A-запись домена в Cloudflare стоит «Proxied», а не «DNS only» — не пугайтесь, что в ссылке IP вместо домена: так и нужно, иначе порт 25000–45000 не достучится. Для обхода **через сам Cloudflare** есть отдельный WS-профиль — см. «Cloudflare обход» ниже.

---

## Web-панель

Кадры интерфейса **VLESSPRO** на master: HTTPS `:8765`, тёмная тема, единый вход для всех нод.

| Раздел | Описание |
|--------|----------|
| **Обзор** | Сводка, мониторинг CPU/RAM/диск по каждой ноде |
| **Proxy** | Создание пользователя → Hysteria2 (телефон) + PC VLESS + QR, список клиентов |
| **Ноды** | Master + remote agent, порты firewall, install.sh |
| **Сертификаты** | Let's Encrypt, autoprenew, Hysteria2, certbot timer |
| **Cloudflare** | Обход блокировок: VLESS + WS через CDN, Origin Rule, SSL-режим |
| **Кабинет** | Пароль admin, Telegram / SMTP оповещения |

### Обзор

![Обзор панели — ноды и клиенты](docs/screenshots/dashboard.png)

### Мониторинг нод (CPU / RAM / диск)

Компактные датчики на master: отдельная карточка на каждую ноду (master + agent), обновление каждые 5 с.

![Мониторинг нод — датчики на Обзоре](docs/screenshots/node-monitoring.png)

### Proxy — выдача конфигов

![Proxy — новый пользователь и список клиентов](docs/screenshots/proxy.png)

### Ноды и agent

![Ноды — master, agent, порты на agent-ноде](docs/screenshots/nodes.png)

### Сертификаты

![Сертификаты — LE, autoprenew, Hysteria2](docs/screenshots/certs.png)

### Кабинет

![Кабинет — пароль и оповещения](docs/screenshots/profile.png)

---

## Быстрый старт (master-сервер)

### Что нужно заранее

| Требование | Зачем |
|------------|--------|
| VPS с **root** (Debian / Ubuntu) | Установка Hysteria2, certbot, панели |
| Домен с **A-записью** на IP VPS | Let's Encrypt для SNI Hysteria2 (необязательно, но желательно) |
| Email для Let's Encrypt | Выпуск/продление сертификата |
| Открытый порт **25001/udp** | Hysteria2 (телефон) |
| Открытый диапазон **25000–45000/tcp** | PC VLESS TCP+TLS (NekoRay/v2rayN) |
| Открытый порт **8765/tcp** | Web-панель (HTTPS) |
| Открытый порт **80/tcp** | Let's Encrypt HTTP-01 (только на время выпуска) |
| **Git** на сервере | `git clone` репозитория |

> Без домена установка тоже работает — тогда SNI = IP, сертификат самоподписанный, в клиенте `insecure=1`.

### 1. Клонировать и установить

```bash
apt-get update -y && apt-get install -y git curl
git clone https://github.com/sweetpotatohack/vless-manager.git
cd vless-manager
chmod +x install_vless_manager.sh
sudo ./install_vless_manager.sh
```

Установщик спросит:
- **домен для TLS** (например `vpn.example.com`) и **email** — или Enter для самоподписи;
- остальное сделает сам: Hysteria2, firewall, LE, панель, sample-клиенты (Hysteria2 + PC VLESS).

После установки:

```bash
systemctl status hysteria-server   # Hysteria2 (UDP :25001)
systemctl status vless-panel       # Web-панель :8765
cat /etc/vless-manager/urls/sample_client.txt      # пример Hysteria2
cat /etc/vless-manager/urls/sample_client-pc.txt    # пример PC VLESS
```

### 2. Войти в панель

```
https://IP_или_домен:8765/login
```

Логин/пароль по умолчанию: **admin / admin** — смените сразу в **Кабинет**.

### 3. Создать первого клиента

1. **Proxy** → вкладка.
2. Имя (латиница, без пробелов) → выберите ноду → **«Создать Hysteria2 + PC VLESS»**.
3. Откройте карточку клиента — там две ссылки и два QR:
   - `hysteria2://` — для телефона (v2rayTun / NekoBox / v2rayN с hysteria2);
   - `vless://` — для ПК (NekoRay / v2rayN), отдельный TCP-порт.

Телефонный Hysteria2 работает и на Wi‑Fi, и на мобильном интернете. PC VLESS — для случаев, когда Hysteria2 в NekoRay на Windows не поднимается.

---

## Multi-node: VPN с другого VPS через панель master

Схема: **одна web-панель** на главном сервере (master). Пользователи в **Proxy** выбирают **удалённую ноду** — master по API создаёт конфиг **на agent-VPS**, ссылки показываются в той же панели.

```
[Браузер] → https://master:8765 (Proxy)
                ↓ job queue
         [Agent VPS] → Hysteria2 :25001/udp на agent
```

### Что нужно для agent-ноды

| Требование | Зачем |
|------------|--------|
| Отдельный VPS (root) | Hysteria2 + agent API |
| Домен / LE **или** самоподпись | SNI в Hysteria2-ссылке |
| **Master должен достучаться до agent по TCP 8765** | `POST /api/v1/provision` с master на `api_base` ноды (или agent сам опрашивает master через job queue) |
| Порт **25001/udp** на agent | Hysteria2 |

**На firewall agent:** разрешите **8765/tcp** (для прямых API-вызовов master) и **25001/udp** (VPN).

**На master:** исходящие подключения к `IP_агента:8765` не блокировать.

### Подключение ноды через web (пошагово)

#### 1. На master: вкладка **Ноды**

1. Блок **«Сгенерировать агент»**:
   - **Название** — например `frankfurt-1`
   - **Страна** — отображается в Proxy (DE, NL, …)
   - **Домен** — DNS A/AAAA на IP agent (для SNI Hysteria2; можно пусто → SNI = IP)
2. Нажмите **«Сгенерировать агент»** — появится нода со статусом **pending** и кнопкой **install.sh**.

#### 2. Скопируйте install-скрипт

В строке ноды нажмите **install.sh** — скачается скрипт. Или скачайте напрямую:

```bash
curl -fsSL 'https://MASTER:8765/api/v1/agent/install.sh?token=TOKEN' -o agent.sh
```

Token берётся из install.sh ноды (генерируется на master).

#### 3. На новом VPS (agent)

```bash
# от root
bash agent.sh
# или вручную:
curl -fsSL 'https://MASTER:8765/api/v1/agent/install.sh?token=TOKEN' | bash
```

Скрипт:
- скачивает **bundle** с master (`/api/v1/agent/bundle.tar.gz`);
- запускает `install_vless_manager.sh --remote-agent` (ставит Hysteria2 + панель-agent);
- поднимает **vless-panel** (API :8765);
- регистрируется на master (`POST /api/v1/nodes/register`).

#### 4. Проверка в панели

- **Ноды** → статус **online**, виден **public IP**;
- с master: `curl -k https://IP_АГЕНТА:8765/api/v1/health`;
- **Proxy** → в списке нод появится agent с нужной страной/IP.

#### 5. Выдача VPN на удалённой ноде

В **Proxy** создайте пользователя и выберите **remote-ноду**. Если нода online:
- master ставит задачу в очередь (agent сам забирает через `/api/v1/agent/next-job`), либо
- master дёргает `POST /api/v1/provision` на `api_base` агента.

Ссылка `hysteria2://` и QR появятся в карточке клиента — как для master.

### Проверка agent

```bash
# на agent-ноде
systemctl status vless-panel hysteria-server
/opt/vless-manager/vless_manager.sh cli list-hy2
cat /etc/vless-manager/urls/<имя>.txt
```

### Удаление ноды

**Ноды** → «Удалить» у нужной ноды — master удалит её клиентов и отправит agent команду `node_uninstall`.

---

## Cloudflare обход (VLESS + WebSocket)

Когда провайдер режет прямой IP / REALITY, выдаётся дополнительный профиль через Cloudflare CDN:

```text
Клиент → Cloudflare:443 (VLESS + WS, SNI=поддомен) → сервер:8443 (xray-cf)
```

Это отдельный профиль `<name>-cf` — он не трогает Hysteria2 и PC VLESS.

### Настройка в панели

1. Перенесите NS домена на Cloudflare и дождитесь статуса **Active**.
2. В панели откройте раздел **Cloudflare** (боковое меню).
3. Вставьте **API-токен** Cloudflare (права: Zone → DNS:Edit, Zone → Zone:Edit), укажите **зону** (домен), **hostname** (например `vpn.example.com`), **path** (по умолчанию `/ws-akuma67`) и **origin-порт** (по умолчанию `8443`).
4. Нажмите **«Сохранить и поднять xray-cf»**, затем **«Подготовить домен»** — панель сама создаст A-запись (proxied), Origin Rule на origin-порт и выставит SSL-режим.
5. **«Проверить origin»** — Cloudflare должен достучаться до сервера: HTTP 400/404/502/503 = ок, 521–524 = origin недоступен.

### Выдача CF-профиля

```bash
/opt/vless-manager/vless_manager.sh cli create-cf NAME   # /etc/vless-manager/urls/<name>-cf.txt + QR
/opt/vless-manager/vless_manager.sh cli delete-cf NAME
/opt/vless-manager/vless_manager.sh cli ensure-cf        # поднять/пересобрать xray-cf
/opt/vless-manager/vless_manager.sh cli cf-status
```

Профиль: `vless://UUID@vpn.example.com:443?encryption=none&security=tls&sni=vpn.example.com&fp=chrome&type=ws&path=...&host=vpn.example.com#name-cf`. QR: `/etc/vless-manager/qr-codes/<name>-cf.png`.

---

## CLI (vless-manager)

Основные команды:

```bash
# Создать клиента Hysteria2 + QR
/opt/vless-manager/vless_manager.sh cli create-hy2 NAME

# Создать отдельный PC VLESS (TCP+TLS) для NekoRay — не трогает Hysteria2
/opt/vless-manager/vless_manager.sh cli create-pc NAME

# Удалить клиента Hysteria2
/opt/vless-manager/vless_manager.sh cli delete-hy2 NAME

# Удалить отдельный PC VLESS
/opt/vless-manager/vless_manager.sh cli delete-pc NAME

# Список клиентов
/opt/vless-manager/vless_manager.sh cli list-hy2

# Пересобрать конфиг/сервис Hysteria2 (после ручных правок)
/opt/vless-manager/vless_manager.sh cli ensure-hy2

# Cloudflare-профиль (обход блокировок через CDN)
/opt/vless-manager/vless_manager.sh cli create-cf NAME
/opt/vless-manager/vless_manager.sh cli delete-cf NAME
/opt/vless-manager/vless_manager.sh cli ensure-cf
/opt/vless-manager/vless_manager.sh cli cf-status

# Mobile REALITY (TCP :443, для мобильных сетей)
/opt/vless-manager/vless_manager.sh cli create-mobile NAME

# Сменить публичный хост в ссылках (домен или IP)
/opt/vless-manager/vless_manager.sh cli set-public-host DOMAIN_OR_IP

# Интерактивное меню
vless-manager
```

Ссылка клиента: `/etc/vless-manager/urls/<имя>.txt`, QR: `/etc/vless-manager/qr-codes/<имя>.png`.

---

## Полезные команды

```bash
# Статусы
systemctl status hysteria-server vless-panel
journalctl -u hysteria-server -f
journalctl -u vless-panel -f

# Логи
tail -f /var/log/vless-manager.log

# Перезапуск панели
systemctl restart vless-panel

# Обновление сертификата Hysteria2 из LE
# (панель → Сертификаты → «Синхронизировать Hysteria2»)
```

---

## Порты и firewall

| Служба | Порт | Протокол | Назначение |
|--------|------|----------|------------|
| `hysteria-server.service` | 25001 | udp | Hysteria2 — телефон (Wi‑Fi + LTE) |
| `vless-xray.service` / per-client xray | 25000–45000 | tcp | PC VLESS TCP+TLS (NekoRay/v2rayN) |
| `vless-panel.service` | 8765 | tcp | Web-панель HTTPS |
| `vless-panel.service` | 8766 | tcp | HTTP fallback панели |
| `xray-cf.service` | 8443 | tcp | Cloudflare WS (origin для CDN) |
| certbot | 80 | tcp | Let's Encrypt HTTP-01 (выпуск/продление) |

UFW настраивается установщиком автоматически. Проверить:

```bash
ufw status numbered
```

---

## Структура файлов

```
/etc/vless-manager/
├── hysteria-clients/    # <name>.cred — логин:пароль клиента (авторизация Hysteria2)
├── urls/                # <name>.txt (Hysteria2), <name>-pc.txt (PC VLESS), <name>-cf.txt (Cloudflare WS)
├── qr-codes/            # <name>.png (Hysteria2), <name>-pc.png (PC VLESS), <name>-cf.png (Cloudflare WS)
├── templates/           # подсказки клиента: NekoBox DNS, firewall, шифрование
├── tls.env              # TLS_MODE, PUBLIC_HOST, пути LE
├── hysteria.env         # HY2_OBFS — пароль обфускации Salamander
└── clients.db           # legacy-БД (не используется панелью для Hysteria2)

/etc/hysteria/config.yaml   # конфиг сервера (пересобирается автоматически)
/opt/vless-manager/         # установленные скрипты и панель
```

---

## FAQ / диагностика

### Клиент не подключается
1. `systemctl is-active hysteria-server` → `active`.
2. `ss -ulnp | grep 25001` — порт слушается.
3. `ufw status | grep 25001` — порт открыт.
4. Проверьте внешнюю доступность: `nc -vzu IP 25001` (или check-host.net).

### Мобильный интернет не работает, Wi‑Fi работает
- Hysteria2 идёт по UDP — проверьте, что мобильный оператор не режет UDP (редко, но бывает).
- Убедитесь, что в ссылке `sni=` соответствует домену сертификата.

### Hysteria2 на ПК (NekoRay) ругается `authentication failed, status code: 404`
- Это особенность TUN-inbound sing-box/NekoRay на Windows, а не сервер Hysteria2.
- Используйте карточку клиента → **VLESS TCP+TLS (ПК / NekoRay)** или файл `/etc/vless-manager/urls/<name>-pc.txt`.
- Телефонный Hysteria2 при этом не трогается и продолжает работать.

### Хочу домен после установки с самоподписью
Выпустите LE и укажите в панели (**Сертификаты** → «Перевыпустить»), либо вручную пропишите пути в `/etc/vless-manager/tls.env` и выполните:

```bash
/opt/vless-manager/vless_manager.sh cli ensure-hy2
```

### Где пароль admin?
По умолчанию `admin / admin`. Сменить: **Кабинет** → пароль.

---

## Лицензия

MIT — см. [LICENSE](LICENSE).
