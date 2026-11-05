# EcoFlow DELTA 3 1500 — iPhone widget (free)

Виджет Scriptable читает `status.json`. Файл обновляет **GitHub Actions** каждые 15 минут — **Mac и Fly.io не нужны**, это бесплатно.

## Как работает

1. GitHub Actions логинится в EcoFlow (MQTT) и пишет `status.json` в репозиторий
2. iPhone читает raw URL этого файла
3. Обновление виджета — примерно раз в 15 минут (лимит Actions + iOS)

## Setup

1. Создайте **public** GitHub-репозиторий и запушьте этот проект
2. В Settings → Secrets and variables → Actions добавьте:
   - `ECOFLOW_EMAIL`
   - `ECOFLOW_PASSWORD`
   - `ECOFLOW_SN`
   - `ECOFLOW_REGION` (`eu` / `global` / `asia`)
3. Actions → **Update EcoFlow status** → Run workflow
4. В Scriptable:

```js
const BRIDGE_URL = "https://raw.githubusercontent.com/<USER>/<REPO>/main"
```

Скрипт ходит на `${BRIDGE_URL}/status.json`.

## Важно

- Пароль EcoFlow храните только в GitHub Secrets, не в коде
- Смените пароль EcoFlow, если он светился в чатах
- Fly.io-приложение удалено, чтобы не было оплаты
