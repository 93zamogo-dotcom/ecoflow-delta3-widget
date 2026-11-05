"""EcoFlow private (app) API client for DELTA 3 1500.

Official Developer API does not expose this model. Status is fetched the same
way as the EcoFlow mobile app: email/password login → MQTT certification →
`latestQuotas` request over mqtts.
"""

from __future__ import annotations

import base64
import hashlib
import json
import logging
import random
import ssl
import threading
import time
from dataclasses import asdict, dataclass
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import paho.mqtt.client as mqtt

logger = logging.getLogger(__name__)

REGION_HOSTS = {
    "global": "api.ecoflow.com",
    "eu": "api-e.ecoflow.com",
    "asia": "api-a.ecoflow.com",
}

STATE_LABELS = {
    0: "discharging",
    1: "idle",
    2: "charging",
}


@dataclass
class StationStatus:
    sn: str
    online: bool
    soc: int | None
    input_w: int | None
    output_w: int | None
    solar_w: int | None
    ac_out_w: int | None
    ac_in_w: int | None
    state: str | None
    remain_min: int | None
    temp_c: float | None
    cycles: int | None
    updated_at: float
    raw: dict[str, Any]

    def to_public_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data.pop("raw", None)
        data["updated_at_iso"] = time.strftime(
            "%Y-%m-%dT%H:%M:%SZ", time.gmtime(self.updated_at)
        )
        return data


def _http_json(
    method: str,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    body: dict[str, Any] | bytes | None = None,
    form: dict[str, str] | None = None,
    timeout: float = 20.0,
) -> dict[str, Any]:
    req_headers = {"lang": "en_US", "Accept": "application/json"}
    data: bytes | None = None
    if form is not None:
        encoded = "&".join(f"{k}={v}" for k, v in form.items()).encode()
        data = encoded
        req_headers["Content-Type"] = "application/x-www-form-urlencoded"
    elif isinstance(body, dict):
        data = json.dumps(body).encode()
        req_headers["Content-Type"] = "application/json"
    elif isinstance(body, (bytes, bytearray)):
        data = bytes(body)
    if headers:
        req_headers.update(headers)

    request = Request(url, data=data, headers=req_headers, method=method.upper())
    try:
        with urlopen(request, timeout=timeout) as resp:
            payload = json.loads(resp.read().decode())
    except HTTPError as exc:
        detail = exc.read().decode(errors="ignore")
        raise RuntimeError(f"HTTP {exc.code} for {url}: {detail}") from exc
    except URLError as exc:
        raise RuntimeError(f"Network error for {url}: {exc}") from exc

    message = str(payload.get("message", "")).lower()
    code = str(payload.get("code", ""))
    if message != "success" and code not in {"0", "200"}:
        raise RuntimeError(f"EcoFlow API error for {url}: {payload}")
    return payload


def _pick(quota: dict[str, Any], *keys: str) -> Any:
    for key in keys:
        if key in quota and quota[key] is not None:
            return quota[key]
    return None


def _as_int(value: Any) -> int | None:
    if value is None:
        return None
    try:
        return int(round(float(value)))
    except (TypeError, ValueError):
        return None


def _as_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def parse_delta3_1500(sn: str, quota: dict[str, Any], *, online: bool) -> StationStatus:
    state_code = _as_int(_pick(quota, "bms_emsStatus.sysChgDsgState", "bms_emsStatus.chgState"))
    state = STATE_LABELS.get(state_code) if state_code is not None else None

    remain = None
    if state == "charging":
        remain = _as_int(_pick(quota, "bms_emsStatus.chgRemainTime", "pd.remainTime"))
    elif state == "discharging":
        remain = _as_int(_pick(quota, "bms_emsStatus.dsgRemainTime", "pd.remainTime"))
    else:
        remain = _as_int(_pick(quota, "pd.remainTime", "bms_emsStatus.dsgRemainTime"))

    # EcoFlow sometimes encodes "no estimate" as a huge sentinel.
    if remain is not None and remain >= 9999:
        remain = None

    return StationStatus(
        sn=sn,
        online=online,
        soc=_as_int(
            _pick(
                quota,
                "bms_emsStatus.lcdShowSoc",
                "bms_bmsStatus.soc",
                "pd.soc",
            )
        ),
        input_w=_as_int(_pick(quota, "pd.wattsInSum")),
        output_w=_as_int(_pick(quota, "pd.wattsOutSum")),
        solar_w=_as_int(_pick(quota, "mppt.inWatts")),
        ac_out_w=_as_int(_pick(quota, "inv.outputWatts")),
        ac_in_w=_as_int(_pick(quota, "inv.inputWatts")),
        state=state,
        remain_min=remain,
        temp_c=_as_float(_pick(quota, "bms_bmsStatus.temp")),
        cycles=_as_int(_pick(quota, "bms_bmsStatus.cycles")),
        updated_at=time.time(),
        raw=quota,
    )


class EcoFlowClient:
    def __init__(
        self,
        email: str,
        password: str,
        sn: str,
        *,
        region: str = "global",
        poll_timeout_sec: float = 20.0,
    ) -> None:
        self.email = email.strip()
        self.password = password
        self.sn = sn.strip()
        self.region = region.strip().lower() or "global"
        self.poll_timeout_sec = poll_timeout_sec

        self.api_host = REGION_HOSTS.get(self.region, REGION_HOSTS["global"])
        self.token: str | None = None
        self.user_id: str | None = None
        self.mqtt_url: str | None = None
        self.mqtt_port: int = 8883
        self.mqtt_user: str | None = None
        self.mqtt_password: str | None = None

        self._status: StationStatus | None = None
        self._status_lock = threading.Lock()
        self._error: str | None = None
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._client: mqtt.Client | None = None
        self._connected = threading.Event()
        self._quota_event = threading.Event()

    @property
    def status(self) -> StationStatus | None:
        with self._status_lock:
            return self._status

    @property
    def last_error(self) -> str | None:
        return self._error

    def login(self) -> None:
        url = f"https://{self.api_host}/auth/login"
        body = {
            "email": self.email,
            "password": base64.b64encode(self.password.encode()).decode(),
            "scene": "IOT_APP",
            "userType": "ECOFLOW",
        }
        payload = _http_json("POST", url, body=body)
        data = payload["data"]
        self.token = data["token"]
        self.user_id = str(data["user"]["userId"])
        logger.info("Logged in as %s", data["user"].get("name", self.email))

        cert = _http_json(
            "GET",
            f"https://{self.api_host}/iot-auth/app/certification",
            headers={"authorization": f"Bearer {self.token}"},
            form={"userId": self.user_id},
        )
        mqtt_data = cert["data"]
        self.mqtt_url = mqtt_data["url"]
        self.mqtt_port = int(mqtt_data.get("port", 8883))
        self.mqtt_user = mqtt_data["certificateAccount"]
        self.mqtt_password = mqtt_data["certificatePassword"]
        logger.info("MQTT broker %s:%s", self.mqtt_url, self.mqtt_port)

    def _stable_client_id(self) -> str:
        # EcoFlow throttles new client IDs (~10/day). Keep one stable id per user.
        digest = hashlib.sha256(self.user_id.encode()).hexdigest()[:16].upper()
        return f"ANDROID_{digest}_{self.user_id}"

    def _topics(self) -> dict[str, str]:
        assert self.user_id
        return {
            "property": f"/app/device/property/{self.sn}",
            "get": f"/app/{self.user_id}/{self.sn}/thing/property/get",
            "get_reply": f"/app/{self.user_id}/{self.sn}/thing/property/get_reply",
            "status": f"/app/device/status/{self.sn}",
        }

    def _set_status(self, status: StationStatus) -> None:
        with self._status_lock:
            self._status = status
        self._error = None
        self._quota_event.set()

    def _apply_quota(self, quota: dict[str, Any], *, online: bool = True) -> None:
        status = parse_delta3_1500(self.sn, quota, online=online)
        logger.info(
            "Quota sn=%s soc=%s in=%s out=%s state=%s",
            status.sn,
            status.soc,
            status.input_w,
            status.output_w,
            status.state,
        )
        self._set_status(status)

    def _on_connect(self, client: mqtt.Client, _userdata: Any, _flags: dict, reason_code: Any, _properties: Any = None) -> None:
        failed = bool(getattr(reason_code, "is_failure", reason_code != 0))
        if failed:
            self._error = f"MQTT connect failed: {reason_code}"
            logger.error(self._error)
            return
        topics = self._topics()
        client.subscribe(
            [
                (topics["property"], 1),
                (topics["get_reply"], 1),
                (topics["status"], 1),
            ]
        )
        self._connected.set()
        self._request_latest(client)
        logger.info("MQTT connected and subscribed")

    def _request_latest(self, client: mqtt.Client) -> None:
        topics = self._topics()
        payload = {
            "from": "EcoFlowDeltaWidget",
            "id": str(999900000 + random.randint(10000, 99999)),
            "version": "1.1",
            "moduleType": 0,
            "operateType": "latestQuotas",
            "params": {},
        }
        client.publish(topics["get"], json.dumps(payload), qos=1)

    def _on_message(self, _client: mqtt.Client, _userdata: Any, message: mqtt.MQTTMessage) -> None:
        try:
            data = json.loads(message.payload.decode("utf-8", errors="ignore"))
        except Exception:
            logger.exception("Failed to decode MQTT payload on %s", message.topic)
            return

        topic = message.topic
        topics = self._topics()

        if topic == topics["get_reply"] and data.get("operateType") == "latestQuotas":
            body = data.get("data") or {}
            online = int(body.get("online", 0)) == 1
            quota = body.get("quotaMap") or {}
            if online and isinstance(quota, dict):
                self._apply_quota(quota, online=True)
            else:
                self._set_status(
                    StationStatus(
                        sn=self.sn,
                        online=False,
                        soc=None,
                        input_w=None,
                        output_w=None,
                        solar_w=None,
                        ac_out_w=None,
                        ac_in_w=None,
                        state=None,
                        remain_min=None,
                        temp_c=None,
                        cycles=None,
                        updated_at=time.time(),
                        raw={},
                    )
                )
            return

        if topic == topics["property"]:
            params = data.get("params")
            if isinstance(params, dict) and params:
                # Property pushes are partial; merge into last known raw.
                with self._status_lock:
                    previous = dict(self._status.raw) if self._status else {}
                previous.update(params)
                self._apply_quota(previous, online=True)
            return

        if topic == topics["status"]:
            params = data.get("params") or {}
            online = int(params.get("status", 0)) == 1
            with self._status_lock:
                current = self._status
            if current is not None:
                current.online = online
                current.updated_at = time.time()
                self._set_status(current)

    def start_background(self, refresh_every_sec: float = 60.0) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(
            target=self._run_loop,
            args=(refresh_every_sec,),
            name="ecoflow-mqtt",
            daemon=True,
        )
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._client is not None:
            try:
                self._client.loop_stop()
                self._client.disconnect()
            except Exception:
                logger.exception("Error while stopping MQTT client")
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=5)

    def _run_loop(self, refresh_every_sec: float) -> None:
        while not self._stop.is_set():
            try:
                self.login()
                self._connected.clear()
                self._quota_event.clear()
                client_id = self._stable_client_id()
                client = mqtt.Client(
                    callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
                    client_id=client_id,
                    protocol=mqtt.MQTTv311,
                )
                self._client = client
                client.username_pw_set(self.mqtt_user, self.mqtt_password)
                client.tls_set(cert_reqs=ssl.CERT_REQUIRED)
                client.on_connect = self._on_connect
                client.on_message = self._on_message
                assert self.mqtt_url
                client.connect(self.mqtt_url, self.mqtt_port, keepalive=60)
                client.loop_start()

                if not self._connected.wait(timeout=15):
                    raise TimeoutError("MQTT connection timeout")
                if not self._quota_event.wait(timeout=self.poll_timeout_sec):
                    logger.warning("No latestQuotas reply within %.1fs", self.poll_timeout_sec)

                # Keep the session alive and refresh periodically.
                next_refresh = time.time() + refresh_every_sec
                while not self._stop.is_set():
                    if time.time() >= next_refresh:
                        self._request_latest(client)
                        next_refresh = time.time() + refresh_every_sec
                    time.sleep(1)
            except Exception as exc:
                self._error = str(exc)
                logger.exception("EcoFlow bridge loop error")
                time.sleep(10)
            finally:
                if self._client is not None:
                    try:
                        self._client.loop_stop()
                        self._client.disconnect()
                    except Exception:
                        pass
                    self._client = None

    def fetch_once(self) -> StationStatus:
        self.login()
        self._connected.clear()
        self._quota_event.clear()

        client_id = self._stable_client_id()
        client = mqtt.Client(
            callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
            client_id=client_id,
            protocol=mqtt.MQTTv311,
        )
        self._client = client
        client.username_pw_set(self.mqtt_user, self.mqtt_password)
        client.tls_set(cert_reqs=ssl.CERT_REQUIRED)
        client.on_connect = self._on_connect
        client.on_message = self._on_message
        assert self.mqtt_url
        client.connect(self.mqtt_url, self.mqtt_port, keepalive=30)
        client.loop_start()
        try:
            if not self._connected.wait(timeout=15):
                raise TimeoutError("MQTT connection timeout")
            if not self._quota_event.wait(timeout=self.poll_timeout_sec):
                raise TimeoutError(
                    "Station did not answer latestQuotas. Check SN / online status."
                )
            status = self.status
            if status is None:
                raise RuntimeError("No status received")
            return status
        finally:
            client.loop_stop()
            client.disconnect()
            self._client = None
