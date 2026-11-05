#!/usr/bin/env python3
"""HTTP bridge for the iPhone Scriptable / Shortcuts widget."""

from __future__ import annotations

import logging
import os
import time
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv
from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from ecoflow_client import EcoFlowClient

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / ".env")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("ecoflow.bridge")

EMAIL = os.getenv("ECOFLOW_EMAIL", "").strip()
PASSWORD = os.getenv("ECOFLOW_PASSWORD", "")
SN = os.getenv("ECOFLOW_SN", "").strip()
REGION = os.getenv("ECOFLOW_REGION", "global").strip()
TOKEN = os.getenv("BRIDGE_TOKEN", "").strip()
REFRESH_EVERY = float(os.getenv("BRIDGE_REFRESH_SEC", "60"))

if not EMAIL or not PASSWORD or not SN:
    raise SystemExit(
        "Fill ECOFLOW_EMAIL, ECOFLOW_PASSWORD and ECOFLOW_SN in .env before starting."
    )

client = EcoFlowClient(EMAIL, PASSWORD, SN, region=REGION)
app = FastAPI(title="EcoFlow DELTA 3 1500 Bridge", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"],
)


def _authorize(x_ecoflow_token: Optional[str]) -> None:
    if TOKEN and x_ecoflow_token != TOKEN:
        raise HTTPException(status_code=401, detail="Invalid bridge token")


@app.on_event("startup")
def _startup() -> None:
    logger.info("Starting EcoFlow MQTT bridge for %s (%s)", SN, REGION)
    client.start_background(refresh_every_sec=REFRESH_EVERY)


@app.on_event("shutdown")
def _shutdown() -> None:
    client.stop()


@app.get("/health")
def health() -> dict:
    status = client.status
    return {
        "ok": True,
        "sn": SN,
        "has_status": status is not None,
        "age_sec": None if status is None else round(time.time() - status.updated_at, 1),
        "error": client.last_error,
    }


@app.get("/status")
def status(x_ecoflow_token: Optional[str] = Header(default=None)) -> dict:
    _authorize(x_ecoflow_token)
    current = client.status
    if current is None:
        raise HTTPException(
            status_code=503,
            detail=client.last_error or "Waiting for first MQTT quota from the station",
        )
    payload = current.to_public_dict()
    payload["error"] = client.last_error
    return payload


@app.get("/status/refresh")
def refresh(x_ecoflow_token: Optional[str] = Header(default=None)) -> dict:
    _authorize(x_ecoflow_token)
    try:
        return client.fetch_once().to_public_dict()
    except Exception as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


def main() -> None:
    import uvicorn

    host = os.getenv("BRIDGE_HOST", "0.0.0.0")
    # Fly.io / Render / Railway set PORT; local .env uses BRIDGE_PORT
    port = int(os.getenv("PORT") or os.getenv("BRIDGE_PORT", "8080"))
    uvicorn.run("server:app", host=host, port=port, reload=False)


if __name__ == "__main__":
    main()
