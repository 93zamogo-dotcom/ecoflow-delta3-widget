#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ ! -d .venv ]]; then
  python3 -m venv .venv
  .venv/bin/pip install -r bridge/requirements.txt
fi
if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Fill .env with EcoFlow email/password/SN, then re-run."
  exit 1
fi
cd bridge
exec ../.venv/bin/python server.py
