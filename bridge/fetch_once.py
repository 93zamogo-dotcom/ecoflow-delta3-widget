#!/usr/bin/env python3
"""One-shot status fetch for debugging credentials / SN."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from dotenv import load_dotenv

from ecoflow_client import EcoFlowClient

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / ".env")


def main() -> int:
    email = os.getenv("ECOFLOW_EMAIL", "").strip()
    password = os.getenv("ECOFLOW_PASSWORD", "")
    sn = os.getenv("ECOFLOW_SN", "").strip()
    region = os.getenv("ECOFLOW_REGION", "global").strip()
    if not email or not password or not sn:
        print("Set ECOFLOW_EMAIL, ECOFLOW_PASSWORD, ECOFLOW_SN in .env", file=sys.stderr)
        return 2

    client = EcoFlowClient(email, password, sn, region=region)
    status = client.fetch_once()
    print(json.dumps(status.to_public_dict(), ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
