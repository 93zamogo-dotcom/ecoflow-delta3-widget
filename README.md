# EcoFlow DELTA 3 1500 — iPhone widget (free)

Виджет Scriptable читает `status.json`. Файл обновляет **GitHub Actions** — **Mac не нужен**, это бесплатно.

## Как работает

1. GitHub Actions логинится в EcoFlow (MQTT) и пишет `status.json` в репозиторий
2. Основной workflow пытается обновлять каждые ~5 минут (несколько overlapping cron)
3. Watchdog каждые 10 минут: если файл старше 12 минут — обновляет сам
4. iPhone читает через jsDelivr (быстрее, чем raw.githubusercontent CDN)

## Setup

1. Public GitHub-репозиторий + этот проект
2. Settings → Secrets and variables → Actions:
   - `ECOFLOW_EMAIL`
   - `ECOFLOW_PASSWORD`
   - `ECOFLOW_SN`
   - `ECOFLOW_REGION` (`eu` / `global` / `asia`)
3. Actions → **Update EcoFlow status** → Run workflow (один раз)
4. В Scriptable:

```js
const BRIDGE_URL = "https://cdn.jsdelivr.net/gh/<USER>/<REPO>@main"
```

Скрипт ходит на `${BRIDGE_URL}/status.json`.

## Важно

- Пароль EcoFlow только в GitHub Secrets
- GitHub иногда опаздывает с cron — для этого есть watchdog
- Fly.io не используется
