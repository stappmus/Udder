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

  property var remoteConnections: []
  property int remoteConnectionsRevision: 0
  property var remoteTracking: ({})
  property int remoteTrackingRevision: 0
  property var remoteDismissed: ({})
  property int remoteDismissedRevision: 0
  property var remoteSnapshots: ({})
  property int remoteSnapshotsRevision: 0
  property string remoteSocketSignature: ""
  property bool remoteDiscoveryQueued: false
  property string activeRemoteId: ""
  property var remoteRefreshQueue: []
  property string remoteRequestId: ""

  readonly property var trackedRemoteConnections: {
    var connectionsRevision = remoteConnectionsRevision
    var trackingRevision = remoteTrackingRevision
    var rows = []
    for (var i = 0; i < remoteConnections.length; i++) {
      var remote = remoteConnections[i]
      if (remote && remoteTracking[remote.id]) rows.push(remote)
    }
    return rows
  }
  readonly property var remotePrompt: {
    var connectionsRevision = remoteConnectionsRevision
    var trackingRevision = remoteTrackingRevision
    var dismissedRevision = remoteDismissedRevision
    if (!pendingStateLoaded) return null
    for (var i = 0; i < remoteConnections.length; i++) {
      var remote = remoteConnections[i]
      if (remote && !remoteTracking[remote.id] && !remoteDismissed[remote.id]) return remote
    }
    return null
  }
  readonly property bool viewingRemote: activeRemoteId !== ""
  readonly property var activeRemoteConnection: remoteConnection(activeRemoteId)
  readonly property var activeRemoteSnapshot: remoteSnapshot(activeRemoteId)
  readonly property var viewAgents: viewingRemote ? activeRemoteSnapshot.agents : agents
  readonly property var viewCounts: Model.countAgents(viewAgents)
  readonly property string viewState: viewingRemote ? activeRemoteSnapshot.state : state
  readonly property string viewMessage: viewingRemote ? activeRemoteSnapshot.message : message
  readonly property bool viewLoading: viewingRemote ? activeRemoteSnapshot.loading : loading
  readonly property string viewLabel: viewingRemote && activeRemoteConnection
    ? activeRemoteConnection.label : "Local"
  readonly property int trackedBlockedCount: {
    var connectionsRevision = remoteConnectionsRevision
    var snapshotsRevision = remoteSnapshotsRevision
    var trackingRevision = remoteTrackingRevision
    var count = 0
    for (var i = 0; i < remoteConnections.length; i++) {
      var remote = remoteConnections[i]
      if (!remote || !remoteTracking[remote.id]) continue
      count += Model.countAgents(remoteSnapshot(remote.id).agents).blocked
    }
    return count
  }
  readonly property int trackedAgentCount: {
    var connectionsRevision = remoteConnectionsRevision
    var snapshotsRevision = remoteSnapshotsRevision
    var trackingRevision = remoteTrackingRevision
    var count = 0
    for (var i = 0; i < remoteConnections.length; i++) {
      var remote = remoteConnections[i]
      if (!remote || !remoteTracking[remote.id]) continue
      count += remoteSnapshot(remote.id).agents.length
    }
    return count
  }
  readonly property int trackedWorkingCount: {
    var connectionsRevision = remoteConnectionsRevision
    var snapshotsRevision = remoteSnapshotsRevision
    var trackingRevision = remoteTrackingRevision
    var count = 0
    for (var i = 0; i < remoteConnections.length; i++) {
      var remote = remoteConnections[i]
      if (!remote || !remoteTracking[remote.id]) continue
      count += Model.countAgents(remoteSnapshot(remote.id).agents).working
    }
    return count
  }

  property var pendingByPane: ({})
  property int pendingRevision: 0
  property bool pendingStateLoaded: false
  readonly property int pendingCount: {
    var revision = pendingRevision
    var count = 0
    for (var paneId in pendingByPane) count++
    return count + revision * 0
  }

  property var blockedByPane: ({})
  property int blockedRevision: 0
  readonly property int blockedCount: {
    var revision = blockedRevision
    var count = 0
    for (var paneId in blockedByPane) count++
    return count + revision * 0
  }

  property var workingByPane: ({})
  property int workingRevision: 0
  readonly property int workingCount: {
    var revision = workingRevision
    var count = 0
    for (var paneId in workingByPane) count++
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
  readonly property int remoteRefreshIntervalMs: intSetting("remoteRefreshIntervalSec", 10, 5, 60) * 1000

  signal terminalLaunchRequested()
  signal remoteTerminalLaunchRequested(string target, string session)

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

  function remoteConnection(remoteId) {
    var revision = remoteConnectionsRevision
    var wanted = String(remoteId || "")
    for (var i = 0; i < remoteConnections.length; i++) {
      var remote = remoteConnections[i]
      if (remote && remote.id === wanted) return remote
    }
    return null
  }

  function remoteSnapshot(remoteId) {
    var revision = remoteSnapshotsRevision
    var snapshot = remoteSnapshots[String(remoteId || "")]
    if (snapshot && typeof snapshot === "object") return snapshot
    return {
      state: "loading",
      message: "Waiting for the remote Herdr session…",
      loading: false,
      agents: [],
      version: "",
      protocol: 0,
      lastUpdatedMs: 0
    }
  }

  function firstTrackedRemoteWithStatus(status) {
    var wanted = String(status || "")
    var rows = trackedRemoteConnections
    for (var i = 0; i < rows.length; i++) {
      var agents = remoteSnapshot(rows[i].id).agents
      for (var j = 0; j < agents.length; j++)
        if (agents[j] && agents[j].status === wanted) return rows[i].id
    }
    return ""
  }

  function setActiveRemote(remoteId) {
    var wanted = String(remoteId || "")
    if (wanted !== "" && (!remoteTracking[wanted] || !remoteConnection(wanted))) wanted = ""
    activeRemoteId = wanted
    if (wanted !== "") queueRemoteRefresh(wanted)
  }

  function refreshView() {
    if (activeRemoteId !== "") queueRemoteRefresh(activeRemoteId)
    else refresh()
  }

  function refreshAll() {
    refresh()
    refreshTrackedRemotes()
  }

  function refresh() {
    if (requestPending) {
      refreshQueued = true
      return
    }

    refreshQueued = false
    loading = true
    requestPending = true
    requestSerial++
    requestTimeout.restart()
    apiSocketLoader.active = false
    apiSocketLoader.active = true
  }

  function sendSnapshotRequest(socket) {
    if (!socket || !requestPending) return
    var request = {
      id: "udder-snapshot-" + requestSerial,
      method: "session.snapshot",
      params: {}
    }
    socket.write(JSON.stringify(request) + "\n")
    socket.flush()
  }

  function handleSnapshotLine(line) {
    if (!requestPending) return
    var parsed = Model.parseSnapshot(line)
    requestTimeout.stop()
    requestPending = false
    loading = false
    apiSocketLoader.active = false

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
      replaceBlocked(Model.blockedFromAgents(parsed.agents))
      replaceWorking(Model.workingFromAgents(parsed.agents))
      reconcilePending()
    } else {
      state = "error"
      message = parsed.message
      clearLiveState()
    }
    runQueuedRefresh()
  }

  function clearLiveState() {
    agents = []
    livePanes = ({})
    serverVersion = ""
    protocol = 0
    replaceBlocked({})
    replaceWorking({})
  }

  function failRequest(reason) {
    if (!requestPending) return
    requestTimeout.stop()
    requestPending = false
    loading = false
    apiSocketLoader.active = false
    state = "offline"
    message = String(reason || "Herdr server is not running.")
    clearLiveState()
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
    if (focusRequestPending) return
    if (target === "") {
      launchTerminal()
      return
    }

    focusRequestSerial++
    focusRequestId = "udder-focus-" + focusRequestSerial
    focusTargetPaneId = target
    focusRequestPending = true
    focusRequestTimeout.restart()
    focusSocketLoader.active = false
    focusSocketLoader.active = true
  }

  function sendFocusRequest(socket) {
    if (!socket || !focusRequestPending) return
    var request = Model.paneFocusRequest(focusTargetPaneId, focusRequestId)
    socket.write(JSON.stringify(request) + "\n")
    socket.flush()
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
    focusSocketLoader.active = false
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
    var serverPresent = false
    var remotePaths = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var fields = lines[i].trim().split(/\s+/)
      if (fields.length < 8) continue
      var path = fields.slice(7).join(" ")
      if (path === apiSocketPath) serverPresent = true
      if (fields[5] === "03" && path === clientSocketPath) attached = true
      if (fields[5] === "03" && path.indexOf("/herdr-remote-") >= 0)
        remotePaths[path] = true
    }
    var nextRemoteSignature = Object.keys(remotePaths).sort().join("\n")
    if (nextRemoteSignature !== remoteSocketSignature) {
      remoteSocketSignature = nextRemoteSignature
      discoverRemotes()
    }
    applyClientAttached(attached)
    if (!serverPresent && state === "ready" && !requestPending) {
      state = "offline"
      message = "Herdr server is not running."
      clearLiveState()
    } else if (serverPresent && state !== "ready" && !requestPending) {
      Qt.callLater(root.refresh)
    }
  }

  function discoverRemotes() {
    if (remoteDiscoveryProcess.running) {
      remoteDiscoveryQueued = true
      return
    }
    remoteDiscoveryQueued = false
    remoteDiscoveryProcess.running = true
  }

  function applyRemoteDiscovery(raw, exitCode) {
    var parsed = exitCode === 0 ? Model.parseRemoteDiscovery(raw) : { ok: false, remotes: [] }
    var discoveredConnections = parsed.ok ? parsed.remotes : []
    var nextConnections = Model.mergeRemoteConnections(discoveredConnections, remoteTracking)
    var activeIds = {}
    for (var i = 0; i < discoveredConnections.length; i++)
      activeIds[discoveredConnections[i].id] = true

    remoteConnections = nextConnections
    remoteConnectionsRevision++

    var nextDismissed = {}
    for (var dismissedId in remoteDismissed)
      if (activeIds[dismissedId]) nextDismissed[dismissedId] = true
    remoteDismissed = nextDismissed
    remoteDismissedRevision++

    var nextSnapshots = {}
    for (var snapshotId in remoteSnapshots) {
      if (activeIds[snapshotId] || remoteTracking[snapshotId])
        nextSnapshots[snapshotId] = remoteSnapshots[snapshotId]
    }
    remoteSnapshots = nextSnapshots
    remoteSnapshotsRevision++

    if (activeRemoteId !== "" && !remoteTracking[activeRemoteId]) activeRemoteId = ""
    refreshTrackedRemotes()
    if (remoteDiscoveryQueued) Qt.callLater(root.discoverRemotes)
  }

  function trackRemote(remoteId) {
    var id = String(remoteId || "")
    var remote = remoteConnection(id)
    if (id === "" || !remote) return
    var next = {}
    for (var key in remoteTracking) next[key] = remoteTracking[key]
    next[id] = {
      id: id,
      target: remote.target,
      session: remote.session,
      label: remote.label
    }
    remoteTracking = next
    remoteTrackingRevision++
    dismissRemote(id)
    schedulePendingSave()
    queueRemoteRefresh(id)
  }

  function untrackRemote(remoteId) {
    var id = String(remoteId || "")
    if (id === "" || !remoteTracking[id]) return
    var remote = remoteConnection(id) || remoteTracking[id]
    var next = {}
    for (var key in remoteTracking) if (key !== id) next[key] = remoteTracking[key]
    remoteTracking = next
    remoteTrackingRevision++
    if (activeRemoteId === id) activeRemoteId = ""
    dismissRemote(id)
    if (remote && remote.target)
      Quickshell.execDetached([
        pluginRoot + "/udder-remote", "stop", String(remote.target), String(remote.session || "default")
      ])
    schedulePendingSave()
    discoverRemotes()
  }

  function dismissRemote(remoteId) {
    var id = String(remoteId || "")
    if (id === "") return
    var next = {}
    for (var key in remoteDismissed) next[key] = remoteDismissed[key]
    next[id] = true
    remoteDismissed = next
    remoteDismissedRevision++
  }

  function refreshTrackedRemotes() {
    var rows = trackedRemoteConnections
    for (var i = 0; i < rows.length; i++) queueRemoteRefresh(rows[i].id)
  }

  function queueRemoteRefresh(remoteId) {
    var id = String(remoteId || "")
    if (id === "" || !remoteTracking[id] || !remoteConnection(id)) return
    if (remoteRequestId === id || remoteRefreshQueue.indexOf(id) >= 0) return
    var next = remoteRefreshQueue.slice()
    next.push(id)
    remoteRefreshQueue = next
    pumpRemoteRefresh()
  }

  function pumpRemoteRefresh() {
    if (remoteRequestId !== "" || remoteSnapshotProcess.running || remoteRefreshQueue.length === 0) return
    var id = remoteRefreshQueue[0]
    remoteRefreshQueue = remoteRefreshQueue.slice(1)
    var remote = remoteConnection(id)
    if (!remote || !remoteTracking[id]) {
      Qt.callLater(root.pumpRemoteRefresh)
      return
    }

    remoteRequestId = id
    setRemoteSnapshot(id, {
      state: remoteSnapshot(id).state,
      message: remoteSnapshot(id).message,
      loading: true,
      agents: remoteSnapshot(id).agents,
      version: remoteSnapshot(id).version,
      protocol: remoteSnapshot(id).protocol,
      lastUpdatedMs: remoteSnapshot(id).lastUpdatedMs
    })
    remoteSnapshotProcess.command = [
      pluginRoot + "/udder-remote", "snapshot", String(remote.target), String(remote.session || "default")
    ]
    remoteSnapshotProcess.running = true
  }

  function setRemoteSnapshot(remoteId, snapshot) {
    var next = {}
    for (var key in remoteSnapshots) next[key] = remoteSnapshots[key]
    next[String(remoteId || "")] = snapshot
    remoteSnapshots = next
    remoteSnapshotsRevision++
  }

  function applyRemoteSnapshot(raw, exitCode) {
    var id = remoteRequestId
    remoteRequestId = ""
    if (id === "") return
    var parsed = exitCode === 0 ? Model.parseSnapshot(raw) : { ok: false }
    if (parsed.ok) {
      setRemoteSnapshot(id, {
        state: "ready",
        message: parsed.agents.length === 0 ? "No agents are running." : "",
        loading: false,
        agents: parsed.agents,
        version: parsed.version,
        protocol: parsed.protocol,
        lastUpdatedMs: Date.now()
      })
    } else {
      setRemoteSnapshot(id, {
        state: "offline",
        message: "Could not read the remote Herdr session.",
        loading: false,
        agents: [],
        version: "",
        protocol: 0,
        lastUpdatedMs: 0
      })
    }
    Qt.callLater(root.pumpRemoteRefresh)
  }

  function openRemote(remoteId) {
    var remote = remoteConnection(remoteId)
    if (remote) remoteTerminalLaunchRequested(remote.target, remote.session || "default")
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
    Qt.callLater(root.refresh)
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
    remoteTracking = parsed.remoteTracking || ({})
    remoteTrackingRevision++
    remoteConnections = Model.mergeRemoteConnections(remoteConnections, remoteTracking)
    remoteConnectionsRevision++
    pendingStateLoaded = true
    if (clientAttached) clearPending()
    schedulePendingSave()
    discoverRemotes()
    refreshTrackedRemotes()
  }

  function replaceBlocked(next) {
    blockedByPane = next && typeof next === "object" ? next : {}
    blockedRevision++
  }

  function replaceWorking(next) {
    workingByPane = next && typeof next === "object" ? next : {}
    workingRevision++
  }

  function schedulePendingSave() {
    if (pendingStateLoaded) pendingSaveTimer.restart()
  }

  function flushPending() {
    if (!pendingStateLoaded) return
    pendingFile.setText(JSON.stringify({
      schemaVersion: 3,
      pending: pendingByPane,
      remoteTracking: remoteTracking
    }, null, 2) + "\n")
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
    var event = Model.parseEvent(eventJson, contextJson)
    if (!event.ok) {
      console.warn("udder: ignored malformed Herdr event")
      return
    }

    replaceBlocked(Model.applyBlockedEvent(blockedByPane, event))
    replaceWorking(Model.applyWorkingEvent(workingByPane, event))

    if (!clientAttached) {
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
    }

    Qt.callLater(refresh)
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
    discoverRemotes()
    Qt.callLater(root.refresh)
  }

  Loader {
    id: apiSocketLoader
    active: false

    sourceComponent: Component {
      Socket {
        id: apiSocket
        path: root.apiSocketPath
        connected: true
        onConnectionStateChanged: if (connected) root.sendSnapshotRequest(apiSocket)
        onError: function(errorCode) { root.failRequest("Herdr server is not running.") }

        parser: SplitParser {
          splitMarker: "\n"
          onRead: function(line) { root.handleSnapshotLine(line) }
        }
      }
    }
  }

  Loader {
    id: focusSocketLoader
    active: false

    sourceComponent: Component {
      Socket {
        id: focusSocket
        path: root.apiSocketPath
        connected: true
        onConnectionStateChanged: if (connected) root.sendFocusRequest(focusSocket)
        onError: function(errorCode) { root.finishFocusRequest("Herdr server is not running.") }

        parser: SplitParser {
          splitMarker: "\n"
          onRead: function(line) { root.handleFocusLine(line) }
        }
      }
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
    onTriggered: root.refreshView()
  }

  Timer {
    interval: root.remoteRefreshIntervalMs
    repeat: true
    running: root.trackedRemoteConnections.length > 0
    onTriggered: root.refreshTrackedRemotes()
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

  Process {
    id: remoteDiscoveryProcess
    running: false
    command: [root.pluginRoot + "/udder-remote", "discover"]
    onExited: function(exitCode) {
      root.applyRemoteDiscovery(remoteDiscoveryOutput.text, exitCode)
    }

    stdout: StdioCollector {
      id: remoteDiscoveryOutput
      waitForEnd: true
    }
  }

  Process {
    id: remoteSnapshotProcess
    running: false
    onExited: function(exitCode) {
      root.applyRemoteSnapshot(remoteSnapshotOutput.text, exitCode)
    }

    stdout: StdioCollector {
      id: remoteSnapshotOutput
      waitForEnd: true
    }
  }
}
