// EcoFlow DELTA 3 1500 — Scriptable widget
// ONLY GitHub API (jsDelivr CDN freezes for 20+ minutes)
const REPO = "93zamogo-dotcom/ecoflow-delta3-widget"
const WIDGET_TITLE = "DELTA 3 1500"
const REFRESH_URL = "scriptable:///run?scriptName=" + encodeURIComponent(Script.name())

async function fetchStatus() {
  const stamp = Date.now()
  const url =
    `https://api.github.com/repos/${REPO}/contents/status.json?ref=main&_=${stamp}`
  const req = new Request(url)
  req.timeoutInterval = 20
  req.headers = {
    Accept: "application/vnd.github.raw+json",
    "User-Agent": "EcoFlowDeltaWidget",
    "Cache-Control": "no-cache",
    Pragma: "no-cache",
  }
  const data = await req.loadJSON()
  if (!data || (data.soc == null && !data.updated_at)) {
    throw new Error("Пустой status.json")
  }
  return data
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
  return `${Math.round(value)} W`
}

function fmtRemain(min) {
  if (min == null) return "—"
  const h = Math.floor(min / 60)
  const m = min % 60
  if (h <= 0) return `${m}м`
  return `${h}ч ${String(m).padStart(2, "0")}м`
}

function fmtAge(updatedAt) {
  if (!updatedAt) return ""
  const age = Math.max(0, Math.round(Date.now() / 1000 - Number(updatedAt)))
  if (age < 60) return `${age}с назад`
  if (age < 3600) return `${Math.round(age / 60)}м назад`
  return `${Math.round(age / 3600)}ч назад`
}

function addRefreshButton(parent) {
  const btn = parent.addStack()
  btn.layoutHorizontally()
  btn.centerAlignContent()
  btn.setPadding(4, 8, 4, 8)
  btn.cornerRadius = 8
  btn.backgroundColor = new Color("#14532D")
  btn.url = REFRESH_URL
  const label = btn.addText("↻ Обновить")
  label.font = Font.semiboldSystemFont(11)
  label.textColor = new Color("#A7F3D0")
  return btn
}

async function createWidget(data, errorText) {
  const widget = new ListWidget()
  widget.setPadding(12, 14, 12, 14)
  widget.backgroundColor = new Color("#0B1C17")
  // Whole widget also refreshes on tap
  widget.url = REFRESH_URL

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
    const err = widget.addText(errorText)
    err.font = Font.systemFont(13)
    err.textColor = new Color("#FF6B6B")
    err.minimumScaleFactor = 0.7
    widget.addSpacer()
    const hint = widget.addText("Нажми «Обновить»")
    hint.font = Font.systemFont(11)
    hint.textColor = new Color("#9CA3AF")
    return widget
  }

  const row = widget.addStack()
  row.centerAlignContent()

  const soc = data.soc
  const socText = row.addText(soc == null ? "—" : `${soc}%`)
  socText.font = Font.boldSystemFont(42)
  socText.textColor = socColor(soc)
  socText.minimumScaleFactor = 0.5
  row.addSpacer()

  const right = row.addStack()
  right.layoutVertically()
  right.centerAlignContent()

  const state = right.addText(stateLabel(data.state))
  state.font = Font.semiboldSystemFont(14)
  state.textColor = stateColor(data.state)

  const online = right.addText(data.online ? "online" : "offline")
  online.font = Font.systemFont(11)
  online.textColor = data.online ? new Color("#6EE7B7") : new Color("#F87171")

  widget.addSpacer(8)
  const grid = widget.addStack()
  grid.layoutHorizontally()

  function addMetric(stack, label, value) {
    const col = stack.addStack()
    col.layoutVertically()
    const l = col.addText(label)
    l.font = Font.systemFont(10)
    l.textColor = new Color("#94A3B8")
    const v = col.addText(value)
    v.font = Font.semiboldSystemFont(13)
    v.textColor = Color.white()
  }

  addMetric(grid, "Вход", fmtW(data.input_w))
  grid.addSpacer()
  addMetric(grid, "Выход", fmtW(data.output_w))
  grid.addSpacer()
  addMetric(grid, "Солнце", fmtW(data.solar_w))

  widget.addSpacer(6)
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

  widget.refreshAfterDate = new Date(Date.now() + 60 * 1000)
  return widget
}

let widget
try {
  const data = await fetchStatus()
  widget = await createWidget(data, null)
} catch (err) {
  widget = await createWidget(null, String(err))
}

Script.setWidget(widget)
if (!config.runsInWidget) {
  await widget.presentSmall()
}
Script.complete()
