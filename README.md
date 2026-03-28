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
