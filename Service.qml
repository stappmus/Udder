import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root
  visible: false

  property var settings: ({})
  property bool panelVisible: false

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || home + "/.config"
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"
  readonly property string apiSocketPath: configHome + "/herdr/herdr.sock"
  readonly property string clientSocketPath: apiSocketPath.slice(-5) === ".sock"
    ? apiSocketPath.slice(0, -5) + "-client.sock" : apiSocketPath + "-client"
  readonly property string stateDir: stateHome + "/omarchy"
  readonly property string pendingPath: stateDir + "/udder.json"
  readonly property string pluginRoot: resolvedPluginRoot()

  property string state: "loading"
  property string message: "Waiting for Herdr…"
  property bool loading: false
  property var agents: []
  property var livePanes: ({})
  property string serverVersion: ""
  property int protocol: 0
  property double lastUpdatedMs: 0
  readonly property var counts: Model.countAgents(agents)

  property bool clientAttached: false

  property var pendingByPane: ({})
  property int pendingRevision: 0
  property bool pendingStateLoaded: false
  readonly property int pendingCount: {
    var revision = pendingRevision
    var count = 0
    for (var paneId in pendingByPane) count++
    return count + revision * 0
  }

  property string integrationState: "checking"
  property string integrationMessage: "Registering the Herdr event bridge…"

  property int requestSerial: 0
  property bool requestPending: false
  property bool refreshQueued: false
  property var announcementQueue: []

  property int focusRequestSerial: 0
  property bool focusRequestPending: false
  property string focusRequestId: ""
  property string focusTargetPaneId: ""

  readonly property int panelRefreshIntervalMs: intSetting("panelRefreshIntervalSec", 2, 1, 30) * 1000
  readonly property int clientCheckIntervalMs: intSetting("clientCheckIntervalSec", 5, 2, 60) * 1000

  signal terminalLaunchRequested()

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, minimum, maximum) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function boolSetting(name, fallback) {
    var value = setting(name, fallback)
    if (value === true || value === false) return value
    var text = String(value).toLowerCase()
    return text === "true" || text === "yes" || text === "on" || text === "1"
  }

  function urlToPath(value) {
    var text = String(value || "")
    if (text.indexOf("file://") === 0) text = text.slice(7)
    try { return decodeURIComponent(text) } catch (error) { return text }
  }

  function resolvedPluginRoot() {
    var manifestPath = urlToPath(Qt.resolvedUrl("manifest.json"))
    var slash = manifestPath.lastIndexOf("/")
    return slash >= 0 ? manifestPath.slice(0, slash) : "."
  }

  function refresh() {
    if (requestPending || apiSocket.connected) {
      refreshQueued = true
      return
    }

    refreshQueued = false
    loading = true
    requestPending = true
    requestSerial++
    requestTimeout.restart()
    apiSocket.connected = true
  }

  function sendSnapshotRequest() {
    if (!apiSocket.connected || !requestPending) return
    var request = {
      id: "udder-snapshot-" + requestSerial,
      method: "session.snapshot",
      params: {}
    }
    apiSocket.write(JSON.stringify(request) + "\n")
    apiSocket.flush()
  }

  function handleSnapshotLine(line) {
    if (!requestPending) return
    var parsed = Model.parseSnapshot(line)
    requestTimeout.stop()
    requestPending = false
    loading = false
    apiSocket.connected = false

    if (parsed.ok) {
      state = "ready"
      message = parsed.agents.length === 0 ? "No agents are running." : ""
      agents = parsed.agents
      var nextPanes = {}
      for (var i = 0; i < parsed.paneIds.length; i++) nextPanes[parsed.paneIds[i]] = true
      livePanes = nextPanes
      serverVersion = parsed.version
      protocol = parsed.protocol
      lastUpdatedMs = Date.now()
      reconcilePending()
    } else {
      state = "error"
      message = parsed.message
    }
    runQueuedRefresh()
  }

  function failRequest(reason) {
    if (!requestPending) return
    requestTimeout.stop()
    requestPending = false
    loading = false
    apiSocket.connected = false
    state = "offline"
    message = String(reason || "Herdr server is not running.")
    agents = []
    livePanes = ({})
    serverVersion = ""
    protocol = 0
    runQueuedRefresh()
  }

  function runQueuedRefresh() {
    if (!refreshQueued) return
    refreshQueued = false
    Qt.callLater(root.refresh)
  }

  function pendingPaneId() {
    var newestPaneId = ""
    var newestCreatedAt = -1
    for (var paneId in pendingByPane) {
      var createdAt = Number(pendingByPane[paneId].createdAt || 0)
      if (createdAt >= newestCreatedAt) {
        newestPaneId = paneId
        newestCreatedAt = createdAt
      }
    }
    return newestPaneId
  }

  function openHerdr(paneId) {
    var target = String(paneId || "")
    if (focusRequestPending || focusSocket.connected) return
    if (target === "") {
      launchTerminal()
      return
    }

    focusRequestSerial++
    focusRequestId = "udder-focus-" + focusRequestSerial
    focusTargetPaneId = target
    focusRequestPending = true
    focusRequestTimeout.restart()
    focusSocket.connected = true
  }

  function sendFocusRequest() {
    if (!focusSocket.connected || !focusRequestPending) return
    var request = Model.paneFocusRequest(focusTargetPaneId, focusRequestId)
    focusSocket.write(JSON.stringify(request) + "\n")
    focusSocket.flush()
  }

  function handleFocusLine(line) {
    if (!focusRequestPending) return
    var response = Model.parsePaneFocusResponse(line, focusRequestId)
    if (!response.handled) return
    var focusedTarget = response.ok && response.paneId === focusTargetPaneId
    var reason = response.message
    if (response.ok && !focusedTarget) reason = "Herdr focused a different pane."
    finishFocusRequest(focusedTarget ? "" : reason)
  }

  function finishFocusRequest(reason) {
    if (!focusRequestPending) return
    focusRequestTimeout.stop()
    focusRequestPending = false
    focusSocket.connected = false
    focusRequestId = ""
    focusTargetPaneId = ""
    if (String(reason || "") !== "") console.warn("udder: pane focus failed:", reason)
    launchTerminal()
  }

  function launchTerminal() {
    terminalLaunchRequested()
  }

  function parseClientSockets(raw) {
    var attached = false
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var fields = lines[i].trim().split(/\s+/)
      if (fields.length < 8) continue
      var path = fields.slice(7).join(" ")
      if (fields[5] === "03" && path === clientSocketPath) {
        attached = true
        break
      }
    }
    applyClientAttached(attached)
  }

  function applyClientAttached(attached) {
    var next = attached === true
    if (clientAttached === next) return
    clientAttached = next
    if (next) {
      announcementTimer.stop()
      announcementQueue = []
      clearPending()
    }
  }

  function isPending(paneId) {
    var revision = pendingRevision
    return !!pendingByPane[String(paneId || "")] || revision < 0
  }

  function setPending(record) {
    var paneId = String(record && record.paneId || "")
    if (paneId === "") return false
    var existed = !!pendingByPane[paneId]
    var next = {}
    for (var key in pendingByPane) next[key] = pendingByPane[key]
    next[paneId] = record
    pendingByPane = next
    pendingRevision++
    schedulePendingSave()
    return !existed
  }

  function removePending(paneId) {
    var id = String(paneId || "")
    if (id === "" || !pendingByPane[id]) return false
    var next = {}
    for (var key in pendingByPane) if (key !== id) next[key] = pendingByPane[key]
    pendingByPane = next
    pendingRevision++
    schedulePendingSave()
    return true
  }

  function clearPending() {
    if (pendingCount === 0) return
    pendingByPane = ({})
    pendingRevision++
    schedulePendingSave()
  }

  function loadPending(raw) {
    var parsed = Model.parsePending(raw)
    if (!parsed.ok && String(raw || "").trim() !== "")
      console.warn("udder: ignoring unreadable pending state", parsed.message)
    pendingByPane = parsed.pending
    pendingRevision++
    pendingStateLoaded = true
    if (clientAttached) clearPending()
  }

  function schedulePendingSave() {
    if (pendingStateLoaded) pendingSaveTimer.restart()
  }

  function flushPending() {
    if (!pendingStateLoaded) return
    pendingFile.setText(JSON.stringify({ schemaVersion: 1, pending: pendingByPane }, null, 2) + "\n")
  }

  function reconcilePending() {
    if (clientAttached) {
      clearPending()
      return
    }
    var live = {}
    for (var i = 0; i < agents.length; i++) live[agents[i].paneId] = agents[i].status
    var stale = []
    for (var paneId in pendingByPane) {
      var pending = pendingByPane[paneId]
      if (pending.released === true) {
        if (!livePanes[paneId]) stale.push(paneId)
      } else if (live[paneId] !== "done") {
        stale.push(paneId)
      }
    }
    for (var j = 0; j < stale.length; j++) removePending(stale[j])
  }

  function handleEvent(eventJson, contextJson) {
    if (clientAttached) return
    var event = Model.parseEvent(eventJson, contextJson)
    if (!event.ok) {
      console.warn("udder: ignored malformed Herdr event")
      return
    }

    if (event.kind === "closed") {
      removePending(event.paneId)
    } else if (event.kind === "detected" && event.released && event.finalStatus === "done") {
      event.status = "done"
      if (setPending(event)) queueAnnouncement(event)
    } else if (event.kind === "detected" && event.released) {
      removePending(event.paneId)
    } else if (event.kind === "status" && event.status === "done") {
      if (setPending(event)) queueAnnouncement(event)
    } else if (event.kind === "status") {
      removePending(event.paneId)
    }

    if (panelVisible) Qt.callLater(refresh)
  }

  function queueAnnouncement(record) {
    var next = announcementQueue.slice()
    next.push(record)
    announcementQueue = next
    announcementTimer.restart()
  }

  function announceQueued() {
    if (clientAttached || announcementQueue.length === 0) {
      announcementQueue = []
      return
    }
    var rows = announcementQueue
    announcementQueue = []
    var headline = rows.length === 1 ? "Agent finished" : rows.length + " agents finished"
    var body = rows.length === 1
      ? rows[0].agentLabel + " finished in " + rows[0].workspaceLabel + "."
      : "Open Herdr to review " + pendingCount + " finished agents."
    if (boolSetting("playCompletionSound", true))
      Quickshell.execDetached([pluginRoot + "/udder-sound"])
    Quickshell.execDetached([
      "omarchy-notification-send",
      "--exec", "omarchy-shell stappmus.udder openHerdr",
      "--app-name", "Udder",
      "-g", "󰆚",
      "-u", "normal",
      headline,
      body
    ])
  }

  function ensureIntegration() {
    if (!boolSetting("autoRegisterEvents", true)) {
      integrationState = "disabled"
      integrationMessage = "Herdr event registration is disabled in Udder settings."
      return
    }
    if (!integrationProcess.running) integrationProcess.running = true
  }

  function applyIntegrationResult(raw, exitCode) {
    try {
      var result = JSON.parse(String(raw || ""))
      integrationState = String(result.state || (exitCode === 0 ? "ready" : "error"))
      integrationMessage = String(result.message || "")
    } catch (error) {
      integrationState = exitCode === 0 ? "ready" : "error"
      integrationMessage = exitCode === 0 ? "" : "Could not register Udder with Herdr."
    }
  }

  Component.onCompleted: {
    ensureStateDir.running = true
    ensureIntegration()
  }

  Socket {
    id: apiSocket
    path: root.apiSocketPath
    connected: false
    onConnectionStateChanged: if (connected) root.sendSnapshotRequest()
    onError: function(errorCode) { root.failRequest("Herdr server is not running.") }

    parser: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { root.handleSnapshotLine(line) }
    }
  }

  Socket {
    id: focusSocket
    path: root.apiSocketPath
    connected: false
    onConnectionStateChanged: if (connected) root.sendFocusRequest()
    onError: function(errorCode) { root.finishFocusRequest("Herdr server is not running.") }

    parser: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { root.handleFocusLine(line) }
    }
  }

  Timer {
    id: focusRequestTimeout
    interval: 1200
    repeat: false
    onTriggered: root.finishFocusRequest("Herdr did not answer the pane focus request.")
  }

  Timer {
    id: requestTimeout
    interval: 2500
    repeat: false
    onTriggered: root.failRequest("Herdr did not answer the snapshot request.")
  }

  Timer {
    interval: root.panelRefreshIntervalMs
    repeat: true
    running: root.panelVisible
    onTriggered: root.refresh()
  }

  FileView {
    id: clientSockets
    path: "/proc/net/unix"
    watchChanges: false
    printErrors: false
    onLoaded: root.parseClientSockets(text())
    onLoadFailed: root.applyClientAttached(false)
  }

  Timer {
    interval: root.clientCheckIntervalMs
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: clientSockets.reload()
  }

  FileView {
    id: pendingFile
    path: root.pendingPath
    watchChanges: false
    printErrors: false
    atomicWrites: true
    onLoaded: root.loadPending(text())
    onLoadFailed: root.loadPending("")
  }

  Timer {
    id: pendingSaveTimer
    interval: 120
    repeat: false
    onTriggered: root.flushPending()
  }

  Timer {
    id: announcementTimer
    interval: 300
    repeat: false
    onTriggered: root.announceQueued()
  }

  Process {
    id: ensureStateDir
    running: false
    command: ["mkdir", "-p", root.stateDir]
    onExited: pendingFile.reload()
  }

  Process {
    id: integrationProcess
    running: false
    command: [root.pluginRoot + "/udder-integrate"]
    onExited: function(exitCode) { root.applyIntegrationResult(integrationOutput.text, exitCode) }

    stdout: StdioCollector {
      id: integrationOutput
      waitForEnd: true
    }
  }
}
