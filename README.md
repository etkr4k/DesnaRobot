# DesnaRobot

`git clone https://github.com/etkr4k/DesnaRobot.git`

`cd DesnaRobot && nano html/config.js`

`docker compose up --build -d`


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
- **POST `/webhook/schedule`** — приватный, его дёргает `/admin`. Обязательно включите в ноде Webhook аутентификацию **Header Auth** (в n8n: Credential → Header Auth → имя заголовка `X-Admin-Token`, значение — ваш секрет) — то же значение секрета пропишите в `html/admin/config.js` (`admin_token`); страница шлёт его в заголовке `X-Admin-Token` при каждом сохранении. Без этого любой, кто узнает URL вебхука, сможет менять расписание в обход `/admin`. Тело запроса — тот же набор полей, что и в SELECT выше; нод Postgres делает `UPDATE schedule_config SET ... WHERE id = 1`.

Пропишите GET-URL в `html/config.js` (`webhook_schedule_get`). Для админки скопируйте шаблон и впишите оба URL и секрет:

```
cp html/admin/config.js.example html/admin/config.js
nano html/admin/config.js
```

`html/admin/config.js` не коммитится (см. `.gitignore`), т.к. содержит реальный `admin_token` — секрет, а не просто адрес вебхука. Используйте длинный случайный токен, а не что-то предсказуемое.

Рекомендуется также добавить проверку `accepting_orders`/расписания в существующий workflow приёма заказов (перед вставкой в `orders`), чтобы расписание нельзя было обойти прямым POST на вебхук заказов, минуя лендинг.

### 3. Пароль для `/admin`

Страница `/admin` защищена HTTP Basic Auth на уровне nginx. Сгенерируйте файл `.htpasswd` в корне проекта (он не коммитится, см. `.gitignore`):

```
docker run --rm httpd:alpine htpasswd -nb admin 'ВАШ_ПАРОЛЬ' > .htpasswd
```

Файл должен существовать до `docker compose up`, т.к. он монтируется в контейнер nginx.
