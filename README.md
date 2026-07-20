# DesnaRobot

```
git clone https://github.com/etkr4k/DesnaRobot.git
cd DesnaRobot
cp .env.example .env
nano .env
docker run --rm httpd:alpine htpasswd -nb admin 'ВАШ_ПАРОЛЬ' > .htpasswd
docker compose up --build -d
```

Вся конфигурация — webhook-урлы, `admin_token`, IP реверс-прокси, порт — в одном `.env` (не коммитится, см. `.gitignore`). При старте контейнера `config.js` и `admin/config.js` генерируются автоматически из `.env` (шаблоны — `html/config.js.template`, `html/admin/config.js.template`), руками их не редактируйте — правки потеряются при следующем `docker compose up`.

Если меняете `.env` на уже запущенном проекте — перечитать его контейнер сам не сможет, нужно пересоздать: `docker compose up -d --force-recreate`.


```
CREATE TABLE orders (
  id           SERIAL PRIMARY KEY,
  address      TEXT NOT NULL,
  qty          INTEGER NOT NULL,
  phone        TEXT NOT NULL,
  date         DATE NOT NULL,
  time         TIME NOT NULL,
  total_price  INTEGER NOT NULL,
  tg_user_id   BIGINT,
  tg_username  TEXT,
  tg_first_name TEXT,
  name		TEXT,
  source       TEXT DEFAULT 'tg_webapp',
  status       TEXT DEFAULT 'new',
  created_at   TIMESTAMPTZ DEFAULT now()
);
```

## Расписание приёма заказов

Расписание (рабочие часы по дням недели, исключения, пауза приёма заявок) настраивается на странице `/admin` и хранится в отдельной таблице, которую читает лендинг и правит админка через вебхуки n8n.

### 1. Таблица в Postgres

```sql
CREATE TABLE schedule_config (
  id                 SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  accepting_orders   BOOLEAN NOT NULL DEFAULT true,
  pause_message      TEXT NOT NULL DEFAULT 'Сейчас не принимаем новые заявки. Загляните позже!',
  slot_step_minutes  INTEGER NOT NULL DEFAULT 60,
  min_lead_hours     INTEGER NOT NULL DEFAULT 2,
  weekly             JSONB NOT NULL DEFAULT '{
    "mon":{"open":true,"start":"12:00","end":"22:00"},
    "tue":{"open":true,"start":"12:00","end":"22:00"},
    "wed":{"open":true,"start":"12:00","end":"22:00"},
    "thu":{"open":true,"start":"12:00","end":"22:00"},
    "fri":{"open":true,"start":"12:00","end":"22:00"},
    "sat":{"open":true,"start":"12:00","end":"22:00"},
    "sun":{"open":true,"start":"12:00","end":"22:00"}
  }',
  exceptions         JSONB NOT NULL DEFAULT '[]',
  blocked_slots      JSONB NOT NULL DEFAULT '[]',
  updated_at         TIMESTAMPTZ DEFAULT now()
);
INSERT INTO schedule_config (id) VALUES (1);
```

`exceptions` — массив точечных переопределений на конкретную дату (один интервал/статус на дату), перекрывает `weekly`:
```json
[
  {"date": "2026-08-01", "open": false, "note": "выходной"},
  {"date": "2026-08-05", "open": true, "start": "10:00", "end": "14:00", "note": "сокращённый день"}
]
```

`blocked_slots` — точечные занятые интервалы внутри дня (например, обед или разовая занятость мастера). В отличие от `exceptions`, на одну дату может быть несколько записей — они не переопределяют весь день, а просто вырезают время из уже открытого дня (по `weekly` или `exceptions`):
```json
[
  {"date": "2026-08-05", "start": "15:00", "end": "16:00", "note": "обед"},
  {"date": "2026-08-05", "start": "19:00", "end": "20:00", "note": "мастер занят"}
]
```

### 2. Вебхуки n8n

Заведите два вебхука в n8n:

- **GET `/webhook/schedule`** — публичный (его дёргает лендинг на каждой загрузке страницы). Один нод Postgres: `SELECT accepting_orders, pause_message, slot_step_minutes, min_lead_hours, weekly, exceptions, blocked_slots FROM schedule_config WHERE id = 1;` — и отдать результат как JSON-ответ.
- **POST `/webhook/schedule`** — приватный, его дёргает `/admin`. Обязательно включите в ноде Webhook аутентификацию **Header Auth** (в n8n: Credential → Header Auth → имя заголовка `X-Admin-Token`, значение — ваш секрет) — то же значение впишите в `.env` (`ADMIN_TOKEN`); страница шлёт его в заголовке `X-Admin-Token` при каждом сохранении. Без этого любой, кто узнает URL вебхука, сможет менять расписание в обход `/admin`. Тело запроса — тот же набор полей, что и в SELECT выше; нод Postgres делает `UPDATE schedule_config SET ... WHERE id = 1`.

Все URL (`WEBHOOK_SITE`, `WEBHOOK_APP`, `WEBHOOK_SCHEDULE_GET`, `WEBHOOK_SCHEDULE_SET`) и `ADMIN_TOKEN` — в `.env`. Используйте длинный случайный токен, не оставляйте `CHANGE_ME`.

Рекомендуется также добавить проверку `accepting_orders`/расписания в существующий workflow приёма заказов (перед вставкой в `orders`), чтобы расписание нельзя было обойти прямым POST на вебхук заказов, минуя лендинг.

### 3. Пароль для `/admin`

Страница `/admin` защищена HTTP Basic Auth на уровне nginx. Файл `.htpasswd` создаётся командой из шага установки выше (он не коммитится, см. `.gitignore`) и должен существовать до `docker compose up`, т.к. монтируется в контейнер.

### 4. Реальный IP клиента в логах (если nginx стоит за реверс-прокси)

Если перед этим контейнером есть свой реверс-прокси (Caddy/другой nginx/Cloudflare и т.п.), в логах nginx по умолчанию будет виден IP прокси, а не реального клиента. Впишите в `.env` (`TRUSTED_PROXY_IP`) IP или подсеть этого прокси — один адрес (`1.2.3.4`) или подсеть (`1.2.3.0/24`). nginx подставит реальный IP клиента из заголовка `X-Forwarded-For`, который должен присылать ваш прокси. Не указывайте здесь ничего шире, чем реальный адрес прокси — иначе кто угодно сможет подделать IP в логах через свой собственный заголовок.

Файл должен существовать до `docker compose up`, т.к. он монтируется в контейнер nginx.
