#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/bridge"

if ! command -v fly >/dev/null 2>&1 && ! command -v flyctl >/dev/null 2>&1; then
  echo "Installing flyctl..."
  curl -L https://fly.io/install.sh | sh
  export FLYCTL_INSTALL="${HOME}/.fly"
  export PATH="$FLYCTL_INSTALL/bin:$PATH"
fi

FLY_BIN="$(command -v fly || command -v flyctl)"

if ! "$FLY_BIN" auth whoami >/dev/null 2>&1; then
  echo "Войдите в Fly.io (откроется браузер)..."
  "$FLY_BIN" auth login
fi

# Create app if missing
if ! "$FLY_BIN" status >/dev/null 2>&1; then
  "$FLY_BIN" apps create ecoflow-delta3-widget --org personal || true
fi

# Load secrets from local .env (never commit .env)
set -a
# shellcheck disable=SC1091
source "$ROOT/.env"
set +a

"$FLY_BIN" secrets set \
  ECOFLOW_EMAIL="$ECOFLOW_EMAIL" \
  ECOFLOW_PASSWORD="$ECOFLOW_PASSWORD" \
  ECOFLOW_SN="$ECOFLOW_SN" \
  ECOFLOW_REGION="${ECOFLOW_REGION:-eu}" \
  BRIDGE_TOKEN="${BRIDGE_TOKEN:-}"

"$FLY_BIN" deploy --ha=false

echo
echo "Готово. URL:"
"$FLY_BIN" status -a ecoflow-delta3-widget | sed -n '1,20p'
echo
echo "Проверка:"
echo "  curl -s https://ecoflow-delta3-widget.fly.dev/status"
echo
echo "В Scriptable поставьте:"
echo '  const BRIDGE_URL = "https://ecoflow-delta3-widget.fly.dev"'
