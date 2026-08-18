.pragma library

function objectValue(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {}
}

function arrayValue(value) {
  return Array.isArray(value) ? value : []
}

function textValue(value, fallback) {
  if (value === undefined || value === null) return fallback === undefined ? "" : String(fallback)
  return String(value)
}

function numberValue(value, fallback) {
  var parsed = Number(value)
  return isFinite(parsed) ? parsed : (fallback === undefined ? 0 : fallback)
}

function parseJson(raw) {
  try {
    return { ok: true, value: JSON.parse(String(raw || "")) }
  } catch (error) {
    return { ok: false, message: String(error) }
  }
}

function normalizeStatus(value) {
  var status = textValue(value, "unknown").toLowerCase()
  return ["idle", "working", "blocked", "done", "unknown"].indexOf(status) >= 0
    ? status : "unknown"
}

function statusRank(status) {
  switch (normalizeStatus(status)) {
  case "done": return 0
  case "blocked": return 1
  case "working": return 2
  case "idle": return 3
  default: return 4
  }
}

function leafName(path) {
  var value = textValue(path, "").replace(/\/+$/, "")
  if (value === "") return ""
  var slash = value.lastIndexOf("/")
  return slash >= 0 ? value.slice(slash + 1) : value
}

function titleCase(value) {
  var text = textValue(value, "")
  if (text === "") return "Agent"
  return text.charAt(0).toUpperCase() + text.slice(1)
}

function workspaceMaps(snapshot) {
  var byId = {}
  var rows = arrayValue(snapshot.workspaces)
  for (var i = 0; i < rows.length; i++) {
    var workspace = objectValue(rows[i])
    var id = textValue(workspace.workspace_id, "")
    if (id !== "") byId[id] = workspace
  }

  var tabs = {}
  var tabRows = arrayValue(snapshot.tabs)
  for (var j = 0; j < tabRows.length; j++) {
    var tab = objectValue(tabRows[j])
    var tabId = textValue(tab.tab_id, "")
    if (tabId !== "") tabs[tabId] = tab
  }
  return { workspaces: byId, tabs: tabs }
}

function normalizeAgent(raw, maps) {
  var agent = objectValue(raw)
  var workspaceId = textValue(agent.workspace_id, "")
  var tabId = textValue(agent.tab_id, "")
  var workspace = objectValue(maps.workspaces[workspaceId])
  var tab = objectValue(maps.tabs[tabId])
  var cwd = textValue(agent.foreground_cwd || agent.cwd, "")
  var workspaceLabel = textValue(workspace.label, "")
  if (workspaceLabel === "") workspaceLabel = leafName(cwd)
  if (workspaceLabel === "") workspaceLabel = workspaceId || "Herdr"

  var agentName = textValue(agent.display_agent || agent.agent, "agent")
  var terminalTitle = textValue(agent.terminal_title_stripped || agent.title, "")
  var detailParts = [titleCase(agentName)]
  var folder = leafName(cwd)
  if (folder !== "" && folder.toLowerCase() !== workspaceLabel.toLowerCase()) detailParts.push(folder)
  if (terminalTitle !== "" && terminalTitle.toLowerCase() !== workspaceLabel.toLowerCase()
      && terminalTitle.toLowerCase() !== folder.toLowerCase()) detailParts.push(terminalTitle)

  return {
    key: textValue(agent.pane_id, workspaceId + ":" + tabId),
    paneId: textValue(agent.pane_id, ""),
    workspaceId: workspaceId,
    workspaceLabel: workspaceLabel,
    workspaceNumber: numberValue(workspace.number, 999999),
    tabId: tabId,
    tabNumber: numberValue(tab.number, 999999),
    agent: agentName,
    agentLabel: titleCase(agentName),
    status: normalizeStatus(agent.agent_status),
    title: terminalTitle,
    cwd: cwd,
    detail: detailParts.join(" · "),
    focused: agent.focused === true,
    stateChangeSeq: numberValue(agent.state_change_seq, 0)
  }
}

function sortAgents(agents) {
  var rows = arrayValue(agents).slice()
  rows.sort(function(a, b) {
    var rank = statusRank(a.status) - statusRank(b.status)
    if (rank !== 0) return rank
    var workspace = numberValue(a.workspaceNumber, 999999) - numberValue(b.workspaceNumber, 999999)
    if (workspace !== 0) return workspace
    var tab = numberValue(a.tabNumber, 999999) - numberValue(b.tabNumber, 999999)
    if (tab !== 0) return tab
    return textValue(a.paneId, "").localeCompare(textValue(b.paneId, ""))
  })
  return rows
}

function parseSnapshot(raw) {
  var parsed = parseJson(raw)
  if (!parsed.ok) return { ok: false, message: "Herdr returned unreadable data." }

  var document = objectValue(parsed.value)
  if (document.error) {
    var error = objectValue(document.error)
    return { ok: false, message: textValue(error.message, "Herdr rejected the snapshot request.") }
  }

  var result = objectValue(document.result)
  var snapshot = objectValue(result.snapshot || document.snapshot)
  if (!Array.isArray(snapshot.agents)) {
    return { ok: false, message: "Herdr returned a snapshot without an agent list." }
  }

  var maps = workspaceMaps(snapshot)
  var agents = []
  for (var i = 0; i < snapshot.agents.length; i++) {
    var normalized = normalizeAgent(snapshot.agents[i], maps)
    if (normalized.paneId !== "") agents.push(normalized)
  }

  var paneIds = []
  var panes = arrayValue(snapshot.panes)
  for (var j = 0; j < panes.length; j++) {
    var paneId = textValue(objectValue(panes[j]).pane_id, "")
    if (paneId !== "") paneIds.push(paneId)
  }

  return {
    ok: true,
    version: textValue(snapshot.version, ""),
    protocol: numberValue(snapshot.protocol, 0),
    agents: sortAgents(agents),
    paneIds: paneIds
  }
}

function countAgents(agents) {
  var counts = { total: 0, working: 0, blocked: 0, done: 0, idle: 0, unknown: 0 }
  var rows = arrayValue(agents)
  counts.total = rows.length
  for (var i = 0; i < rows.length; i++) {
    var status = normalizeStatus(rows[i].status)
    counts[status]++
  }
  return counts
}

function copyPanes(panes) {
  var next = {}
  var source = objectValue(panes)
  var keys = Object.keys(source)
  for (var i = 0; i < keys.length; i++) {
    var paneId = textValue(keys[i], "")
    if (paneId !== "") next[paneId] = true
  }
  return next
}

function panesFromAgents(agents, status) {
  var wanted = normalizeStatus(status)
  var next = {}
  var rows = arrayValue(agents)
  for (var i = 0; i < rows.length; i++) {
    var agent = objectValue(rows[i])
    if (normalizeStatus(agent.status) !== wanted) continue
    var paneId = textValue(agent.paneId, "")
    if (paneId !== "") next[paneId] = true
  }
  return next
}

function applyStatusEvent(panes, event, status) {
  var wanted = normalizeStatus(status)
  var next = copyPanes(panes)
  var paneId = textValue(event && event.paneId, "")
  if (paneId === "") return next

  var kind = textValue(event && event.kind, "")
  if (kind === "closed" || (kind === "detected" && event.released === true)) {
    delete next[paneId]
    return next
  }
  if (kind === "status" || kind === "detected") {
    if (normalizeStatus(event.status) === wanted) next[paneId] = true
    else delete next[paneId]
  }
  return next
}

function blockedFromAgents(agents) { return panesFromAgents(agents, "blocked") }
function applyBlockedEvent(blocked, event) { return applyStatusEvent(blocked, event, "blocked") }
function workingFromAgents(agents) { return panesFromAgents(agents, "working") }
function applyWorkingEvent(working, event) { return applyStatusEvent(working, event, "working") }

function paneFocusRequest(paneId, requestId) {
  return {
    id: textValue(requestId, "udder-focus"),
    method: "pane.focus",
    params: { pane_id: textValue(paneId, "") }
  }
}

function parsePaneFocusResponse(raw, requestId) {
  var parsed = parseJson(raw)
  if (!parsed.ok) return { handled: true, ok: false, message: "Herdr returned unreadable focus data." }
  var document = objectValue(parsed.value)
  if (textValue(document.id, "") !== textValue(requestId, ""))
    return { handled: false, ok: false, message: "" }
  if (document.error) {
    var error = objectValue(document.error)
    return { handled: true, ok: false, message: textValue(error.message, "Herdr rejected the pane focus request.") }
  }
  var result = objectValue(document.result)
  var pane = objectValue(result.pane)
  var paneId = textValue(pane.pane_id, "")
  return {
    handled: true,
    ok: paneId !== "",
    paneId: paneId,
    message: paneId === "" ? "Herdr returned a focus response without a pane." : ""
  }
}

function parseEvent(raw, contextRaw) {
  var parsed = parseJson(raw)
  if (!parsed.ok) return { ok: false, message: "Invalid Herdr event." }
  var contextParsed = parseJson(contextRaw || "{}")
  var context = contextParsed.ok ? objectValue(contextParsed.value) : {}
  var envelope = objectValue(parsed.value)
  var data = objectValue(envelope.data)
  if (Object.keys(data).length === 0) data = envelope

  var eventName = textValue(envelope.event || data.type, "").replace(/\./g, "_")
  var paneId = textValue(data.pane_id || context.focused_pane_id, "")
  var workspaceId = textValue(data.workspace_id || context.workspace_id, "")
  var workspaceLabel = textValue(context.workspace_label, "")
  var cwd = textValue(context.focused_pane_cwd || context.workspace_cwd, "")
  if (workspaceLabel === "") workspaceLabel = leafName(cwd)
  if (workspaceLabel === "") workspaceLabel = workspaceId || paneId || "Herdr"
  var agent = textValue(data.display_agent || data.agent || context.focused_pane_agent, "agent")

  var kind = "unknown"
  if (eventName === "pane_agent_status_changed") kind = "status"
  else if (eventName === "pane_closed") kind = "closed"
  else if (eventName === "pane_agent_detected") kind = "detected"

  return {
    ok: kind !== "unknown" && paneId !== "",
    kind: kind,
    paneId: paneId,
    workspaceId: workspaceId,
    workspaceLabel: workspaceLabel,
    cwd: cwd,
    agent: agent,
    agentLabel: titleCase(agent),
    title: textValue(data.title, ""),
    status: normalizeStatus(data.agent_status || context.focused_pane_status),
    released: data.released === true,
    finalStatus: normalizeStatus(data.final_status),
    createdAt: Date.now()
  }
}

function parsePending(raw) {
  var parsed = parseJson(raw)
  if (!parsed.ok) return { ok: false, pending: {}, message: parsed.message }
  var document = objectValue(parsed.value)
  var source = objectValue(document.pending)
  var pending = {}
  var keys = Object.keys(source)
  for (var i = 0; i < keys.length && i < 100; i++) {
    var paneId = textValue(keys[i], "")
    var entry = objectValue(source[keys[i]])
    if (paneId === "") continue
    pending[paneId] = {
      paneId: paneId,
      workspaceId: textValue(entry.workspaceId, ""),
      workspaceLabel: textValue(entry.workspaceLabel, entry.workspaceId || paneId),
      cwd: textValue(entry.cwd, ""),
      agent: textValue(entry.agent, "agent"),
      agentLabel: textValue(entry.agentLabel, titleCase(entry.agent || "agent")),
      title: textValue(entry.title, ""),
      status: "done",
      released: entry.released === true,
      finalStatus: normalizeStatus(entry.finalStatus),
      createdAt: numberValue(entry.createdAt, 0)
    }
  }
  return { ok: true, pending: pending, message: "" }
}
