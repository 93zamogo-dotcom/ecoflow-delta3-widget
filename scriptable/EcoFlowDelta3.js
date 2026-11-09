// EcoFlow DELTA 3 1500 — Scriptable widget
const REPO = "93zamogo-dotcom/ecoflow-delta3-widget"
const WIDGET_TITLE = "DELTA 3 1500"
const REFRESH_URL = "scriptable:///run?scriptName=" + encodeURIComponent(Script.name())

function decodeBase64(b64) {
  const data = Data.fromBase64String(b64.replace(/\n/g, ""))
  if (!data) throw new Error("base64 decode failed")
  return data.toRawString()
}

async function fetchStatus() {
  const stamp = Date.now()
  const errors = []

  // 1) GitHub Contents API (works from Scriptable; may return base64 wrapper)
  try {
    const req = new Request(
      `https://api.github.com/repos/${REPO}/contents/status.json?ref=main&ts=${stamp}`
    )
    req.timeoutInterval = 20
    req.headers = {
      Accept: "application/vnd.github+json",
      "User-Agent": "Scriptable-EcoFlow",
      "Cache-Control": "no-cache",
    }
    const payload = await req.loadJSON()
    let data = payload
    if (payload && typeof payload.content === "string" && payload.encoding === "base64") {
      data = JSON.parse(decodeBase64(payload.content))
    }
    if (data && (data.soc != null || data.updated_at || data.sn)) return data
    errors.push("api: empty")
  } catch (e) {
    errors.push("api: " + e)
  }

  // 2) raw.githubusercontent (no fancy Accept header)
  try {
    const req = new Request(
      `https://raw.githubusercontent.com/${REPO}/main/status.json?ts=${stamp}`
    )
    req.timeoutInterval = 20
    req.headers = { "Cache-Control": "no-cache", "User-Agent": "Scriptable-EcoFlow" }
    const data = await req.loadJSON()
    if (data && (data.soc != null || data.updated_at || data.sn)) return data
    errors.push("raw: empty")
  } catch (e) {
    errors.push("raw: " + e)
  }

  throw new Error(errors.join(" | ") || "fetch failed")
}

function stateLabel(state) {
  if (state === "charging") return "Заряд"
  if (state === "discharging") return "Разряд"
  if (state === "idle") return "Простой"
  return "—"
}

function stateColor(state) {
  if (state === "charging") return new Color("#34C759")
  if (state === "discharging") return new Color("#FF9F0A")
  return new Color("#8E8E93")
}

function socColor(soc) {
  if (soc == null) return Color.gray()
  if (soc <= 20) return new Color("#FF453A")
  if (soc <= 40) return new Color("#FF9F0A")
  return new Color("#30D158")
}

function fmtW(value) {
  if (value == null) return "—"
  return `${Math.round(Number(value))} W`
}

function fmtRemain(min) {
  if (min == null) return "—"
  min = Number(min)
  const h = Math.floor(min / 60)
  const m = Math.round(min % 60)
  if (h <= 0) return `${m}м`
  return `${h}ч ${String(m).padStart(2, "0")}м`
}

function fmtAge(updatedAt) {
  if (!updatedAt) return ""
  const age = Math.max(0, Math.round(Date.now() / 1000 - Number(updatedAt)))
  if (age < 60) return `${age}с`
  if (age < 3600) return `${Math.round(age / 60)}м`
  return `${Math.round(age / 3600)}ч`
}

function addRefreshButton(parent) {
  const btn = parent.addStack()
  btn.layoutHorizontally()
  btn.centerAlignContent()
  btn.setPadding(3, 7, 3, 7)
  btn.cornerRadius = 7
  btn.backgroundColor = new Color("#14532D")
  btn.url = REFRESH_URL
  const label = btn.addText("Обновить")
  label.font = Font.semiboldSystemFont(11)
  label.textColor = new Color("#A7F3D0")
}

async function createWidget(data, errorText) {
  const widget = new ListWidget()
  widget.setPadding(12, 14, 12, 14)
  widget.backgroundColor = new Color("#0B1C17")

  const header = widget.addStack()
  header.layoutHorizontally()
  header.centerAlignContent()
  const title = header.addText(WIDGET_TITLE)
  title.font = Font.boldSystemFont(12)
  title.textColor = new Color("#A7F3D0")
  header.addSpacer()
  addRefreshButton(header)

  widget.addSpacer(6)

  if (errorText) {
    const err = widget.addText(String(errorText))
    err.font = Font.systemFont(12)
    err.textColor = new Color("#FF6B6B")
    err.minimumScaleFactor = 0.6
    err.lineLimit = 6
    widget.addSpacer()
    const hint = widget.addText("Нажми Обновить")
    hint.font = Font.systemFont(11)
    hint.textColor = new Color("#9CA3AF")
    widget.url = REFRESH_URL
    return widget
  }

  const row = widget.addStack()
  row.centerAlignContent()

  const soc = data.soc
  const socText = row.addText(soc == null ? "—" : `${soc}%`)
  socText.font = Font.boldSystemFont(40)
  socText.textColor = socColor(soc)
  socText.minimumScaleFactor = 0.5
  row.addSpacer()

  const right = row.addStack()
  right.layoutVertically()
  const state = right.addText(stateLabel(data.state))
  state.font = Font.semiboldSystemFont(14)
  state.textColor = stateColor(data.state)
  const online = right.addText(data.online ? "online" : "offline")
  online.font = Font.systemFont(11)
  online.textColor = data.online ? new Color("#6EE7B7") : new Color("#F87171")

  widget.addSpacer(8)
  const grid = widget.addStack()

  function addMetric(label, value) {
    const col = grid.addStack()
    col.layoutVertically()
    const l = col.addText(label)
    l.font = Font.systemFont(10)
    l.textColor = new Color("#94A3B8")
    const v = col.addText(value)
    v.font = Font.semiboldSystemFont(13)
    v.textColor = Color.white()
    grid.addSpacer()
  }

  addMetric("Вход", fmtW(data.input_w))
  addMetric("Выход", fmtW(data.output_w))
  addMetric("Солнце", fmtW(data.solar_w))

  widget.addSpacer(4)
  const bottom = widget.addStack()
  bottom.layoutHorizontally()
  bottom.centerAlignContent()
  const remain = bottom.addText(`Осталось ${fmtRemain(data.remain_min)}`)
  remain.font = Font.systemFont(11)
  remain.textColor = new Color("#CBD5E1")
  bottom.addSpacer()
  const age = bottom.addText(fmtAge(data.updated_at))
  age.font = Font.systemFont(10)
  age.textColor = new Color("#64748B")

  // Don't set widget.url here — it steals taps from the Обновить button
  widget.refreshAfterDate = new Date(Date.now() + 2 * 60 * 1000)
  return widget
}

let widget
try {
  const data = await fetchStatus()
  widget = await createWidget(data, null)
} catch (err) {
  widget = await createWidget(null, err)
}

Script.setWidget(widget)
if (!config.runsInWidget) {
  await widget.presentSmall()
}
Script.complete()
