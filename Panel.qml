import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "stappmus.udder"
  ipcTarget: "stappmus.udder"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property bool cursorActive: false
  property int cursorIndex: 0
  property bool cowFlashHot: true
  property string selectedSessionId: "local"

  readonly property var sessionOptions: {
    var rows = [{ value: "local", label: "Local", icon: "󰒋" }]
    var remotes = herdr.trackedRemoteConnections
    for (var i = 0; i < remotes.length; i++) {
      rows.push({ value: remotes[i].id, label: remotes[i].label, icon: "󰌘" })
    }
    return rows
  }

  readonly property bool cowBlocked: {
    if (herdr.blockedCount + herdr.trackedBlockedCount > 0) return true
    var agents = herdr.agents
    for (var i = 0; i < agents.length; i++) {
      if (agents[i] && agents[i].status === "blocked") return true
    }
    return false
  }
  readonly property bool cowWorking: {
    if (herdr.workingCount + herdr.trackedWorkingCount > 0) return true
    var agents = herdr.agents
    for (var i = 0; i < agents.length; i++) {
      if (agents[i] && agents[i].status === "working") return true
    }
    return false
  }
  readonly property bool cowPending: herdr.pendingCount > 0 && !herdr.clientAttached
  readonly property bool cowRemotePrompt: herdr.remotePrompt !== null
  readonly property bool cowLit: cowWorking || cowPending || cowRemotePrompt || (cowBlocked && cowFlashHot)

  function alpha(color, amount) { return Qt.rgba(color.r, color.g, color.b, amount) }

  function heroMeta() {
    if (herdr.viewingRemote) {
      if (herdr.viewLoading && herdr.viewState !== "ready") return "Checking " + herdr.viewLabel + " over SSH…"
      if (herdr.viewState !== "ready") return herdr.viewMessage
      if (herdr.viewCounts.total === 0) return "No agents are running on " + herdr.viewLabel
      var remoteParts = [herdr.viewCounts.total + " agent" + (herdr.viewCounts.total === 1 ? "" : "s")]
      if (herdr.viewCounts.working > 0) remoteParts.push(herdr.viewCounts.working + " working")
      if (herdr.viewCounts.blocked > 0) remoteParts.push(herdr.viewCounts.blocked + " blocked")
      if (herdr.viewCounts.done > 0) remoteParts.push(herdr.viewCounts.done + " done")
      return remoteParts.join(" · ")
    }
    if (herdr.clientAttached)
      return "Herdr attached · completion monitoring paused"
    if (herdr.loading && herdr.state !== "ready") return "Checking the default Herdr session…"
    if (herdr.state !== "ready") return herdr.message
    if (herdr.counts.total === 0) return "No agents are running"
    var parts = [herdr.counts.total + " agent" + (herdr.counts.total === 1 ? "" : "s")]
    if (herdr.counts.working > 0) parts.push(herdr.counts.working + " working")
    if (herdr.counts.blocked > 0) parts.push(herdr.counts.blocked + " blocked")
    if (herdr.counts.done > 0) parts.push(herdr.counts.done + " done")
    return parts.join(" · ")
  }

  function tooltipText() {
    if (root.cowBlocked)
      return Math.max(herdr.blockedCount, Number(herdr.counts.blocked) || 0)
        + herdr.trackedBlockedCount + " blocked · click to review"
    if (herdr.pendingCount > 0)
      return herdr.pendingCount + " finished · click to open Herdr"
    if (root.cowRemotePrompt)
      return "Remote Herdr detected · click to choose"
    if (root.cowWorking)
      return Math.max(herdr.workingCount, Number(herdr.counts.working) || 0)
        + herdr.trackedWorkingCount + " working"
    if (herdr.clientAttached) return "Herdr is open · monitoring paused"
    if (herdr.state === "ready")
      return herdr.counts.total + " Herdr agent" + (herdr.counts.total === 1 ? "" : "s")
    return "Udder · Herdr agents"
  }

  function launchHerdr(target) {
    if (herdr.viewingRemote) {
      close()
      herdr.openRemote(herdr.activeRemoteId)
      return
    }
    launchLocalHerdr(target)
  }

  function launchLocalHerdr(target) {
    var paneId = ""
    if (typeof target === "string") paneId = target
    else if (target && target.paneId) paneId = String(target.paneId)
    else if (herdr.pendingCount > 0) paneId = herdr.pendingPaneId()
    herdr.clearPending()
    close()
    herdr.openHerdr(paneId)
  }

  function launchSelectedHerdr() {
    if (herdr.viewAgents.length > 0 && cursorIndex >= 0 && cursorIndex < herdr.viewAgents.length)
      launchHerdr(herdr.viewAgents[cursorIndex])
    else
      launchHerdr()
  }

  function moveCursor(delta) {
    if (herdr.viewAgents.length === 0) return
    cursorActive = true
    cursorIndex = Math.max(0, Math.min(herdr.viewAgents.length - 1, cursorIndex + delta))
    scrollSelectedIntoView()
  }

  function scrollSelectedIntoView() {
    Qt.callLater(function() {
      var item = agentRepeater.itemAt(root.cursorIndex)
      if (!item || !panelFlick) return
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var margin = Style.space(8)
      var top = point.y
      var bottom = top + item.height
      if (top < panelFlick.contentY + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > panelFlick.contentY + panelFlick.height - margin)
        panelFlick.contentY = Math.min(panelFlick.contentHeight - panelFlick.height, bottom + margin - panelFlick.height)
    })
  }

  function ensureCursor() {
    if (herdr.viewAgents.length === 0) cursorIndex = 0
    else cursorIndex = Math.max(0, Math.min(herdr.viewAgents.length - 1, cursorIndex))
  }

  function selectSession(sessionId) {
    var wanted = String(sessionId || "local")
    selectedSessionId = wanted
    herdr.setActiveRemote(wanted === "local" ? "" : wanted)
    cursorActive = false
    cursorIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    herdr.refreshView()
  }

  function ensureSelectedSession() {
    if (selectedSessionId === "local") return
    for (var i = 0; i < herdr.trackedRemoteConnections.length; i++)
      if (herdr.trackedRemoteConnections[i].id === selectedSessionId) return
    selectSession("local")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    herdr.panelVisible = opened
    if (opened) {
      if (root.cowBlocked && herdr.blockedCount === 0 && herdr.counts.blocked === 0) {
        var blockedRemoteId = herdr.firstTrackedRemoteWithStatus("blocked")
        if (blockedRemoteId !== "") root.selectSession(blockedRemoteId)
      }
      cursorActive = false
      cursorIndex = 0
      if (panelFlick) panelFlick.contentY = 0
      herdr.refreshView()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  Service {
    id: herdr
    settings: root.settings
    onViewAgentsChanged: root.ensureCursor()
    onTrackedRemoteConnectionsChanged: root.ensureSelectedSession()
    onTerminalLaunchRequested: Quickshell.execDetached([herdr.pluginRoot + "/udder-open"])
    onRemoteTerminalLaunchRequested: function(pid) {
      Quickshell.execDetached([herdr.pluginRoot + "/udder-open", "--remote", String(pid)])
    }
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { herdr.refreshAll(); return "ok" }
    function event(eventJson: string, contextJson: string, clientAttachedText: string): string {
      herdr.applyClientAttached(clientAttachedText === "true")
      herdr.handleEvent(eventJson, contextJson)
      return "ok"
    }
    function openHerdr(): void { root.launchLocalHerdr() }
    function clientActive(): void { herdr.applyClientAttached(true) }
    function status(): string {
      return JSON.stringify({
        state: herdr.state,
        agents: herdr.counts,
        clientAttached: herdr.clientAttached,
        pending: herdr.pendingCount,
        blocked: herdr.blockedCount,
        working: herdr.workingCount,
        remoteDiscovered: herdr.remoteConnections.length,
        remotes: herdr.trackedRemoteConnections.length,
        remoteAgents: herdr.trackedAgentCount,
        remoteBlocked: herdr.trackedBlockedCount,
        remoteWorking: herdr.trackedWorkingCount,
        activeRemote: herdr.activeRemoteId,
        remotePrompt: herdr.remotePrompt ? herdr.remotePrompt.label : "",
        integration: herdr.integrationState
      })
    }
  }

  Timer {
    interval: 450
    repeat: true
    running: root.cowBlocked
    triggeredOnStart: true
    onTriggered: root.cowFlashHot = !root.cowFlashHot
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰆚"
    active: root.cowBlocked && root.cowFlashHot
    dimmed: !root.cowLit
    tooltipText: root.tooltipText()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) {
        root.launchLocalHerdr()
      } else if (buttonCode === Qt.RightButton) {
        herdr.refreshAll()
      } else if (root.cowBlocked) {
        root.toggle()
      } else if (herdr.pendingCount > 0 && !herdr.clientAttached) {
        root.launchLocalHerdr()
      } else {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: root.launchSelectedHerdr()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" || text === "R") herdr.refreshView()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: content
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: herdr.viewingRemote ? "Udder · " + herdr.viewLabel : "Udder"
            meta: root.heroMeta()
            detail: herdr.viewingRemote ? "REMOTE" : (herdr.clientAttached
              ? "ATTACHED" : (herdr.pendingCount > 0 ? herdr.pendingCount + " READY" : "WATCHING"))
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: "󰆚"
                color: herdr.pendingCount > 0 ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
              }
            }
          }

          BorderSurface {
            visible: herdr.remotePrompt !== null
            width: parent.width
            implicitHeight: remotePromptContent.implicitHeight + Style.space(20)
            color: root.alpha(root.accent, 0.08)
            borderSpec: Border.flat(root.alpha(root.accent, 0.35), 1)
            radius: Style.cornerRadius

            Column {
              id: remotePromptContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              Text {
                width: parent.width
                text: herdr.remotePrompt
                  ? "Remote Herdr detected: " + herdr.remotePrompt.label : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                wrapMode: Text.WordWrap
              }

              Text {
                width: parent.width
                text: "Track its agents in Udder over the existing SSH connection?"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              Row {
                spacing: Style.space(8)

                Button {
                  text: "Track"
                  bordered: true
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  onClicked: {
                    var remote = herdr.remotePrompt
                    if (!remote) return
                    herdr.trackRemote(remote.id)
                    root.selectSession(remote.id)
                  }
                }

                Button {
                  text: "Not now"
                  bordered: true
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  onClicked: {
                    if (herdr.remotePrompt) herdr.dismissRemote(herdr.remotePrompt.id)
                  }
                }
              }
            }
          }

          ButtonGroup {
            visible: root.sessionOptions.length > 1
            options: root.sessionOptions
            value: root.selectedSessionId
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            focusable: false
            onChanged: function(value) { root.selectSession(value) }
          }

          Row {
            visible: herdr.viewingRemote
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width - stopTrackingButton.implicitWidth - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              text: "Connected through Herdr’s existing SSH session"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Button {
              id: stopTrackingButton
              text: "Stop tracking"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onClicked: {
                var remoteId = herdr.activeRemoteId
                root.selectSession("local")
                herdr.untrackRemote(remoteId)
              }
            }
          }

          BorderSurface {
            visible: herdr.viewState !== "ready"
            width: parent.width
            implicitHeight: serverStatus.implicitHeight + Style.space(20)
            color: root.alpha(herdr.viewState === "offline" ? root.foreground : root.urgent, 0.08)
            borderSpec: Border.flat(root.alpha(herdr.viewState === "offline" ? root.foreground : root.urgent, 0.30), 1)
            radius: Style.cornerRadius

            Text {
              id: serverStatus
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(10)
              text: herdr.viewMessage
              color: herdr.viewState === "offline" ? root.dim : root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }
          }

          BorderSurface {
            visible: !herdr.viewingRemote
              && herdr.integrationState !== "ready" && herdr.integrationState !== "checking"
            width: parent.width
            implicitHeight: integrationText.implicitHeight + Style.space(20)
            color: root.alpha(root.urgent, 0.08)
            borderSpec: Border.flat(root.alpha(root.urgent, 0.30), 1)
            radius: Style.cornerRadius

            Text {
              id: integrationText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(10)
              text: herdr.integrationMessage
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            width: parent.width
            text: herdr.viewLabel.toUpperCase() + " AGENTS  " + herdr.viewAgents.length
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          BorderSurface {
            visible: herdr.viewState === "ready" && herdr.viewAgents.length === 0
            width: parent.width
            implicitHeight: emptyText.implicitHeight + Style.space(28)
            color: "transparent"
            borderSpec: Border.flat(root.alpha(root.foreground, 0.13), 1)
            radius: Style.cornerRadius

            Text {
              id: emptyText
              anchors.centerIn: parent
              text: "No agents are running."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          Repeater {
            id: agentRepeater
            model: herdr.viewAgents

            AgentRow {
              required property int index
              required property var modelData
              width: content.width
              agent: modelData
              pending: !herdr.viewingRemote && herdr.isPending(modelData.paneId)
              selected: root.cursorActive && root.cursorIndex === index
              animationsEnabled: root.opened
              foreground: root.foreground
              accent: root.accent
              urgent: root.urgent
              fontFamily: root.fontFamily
              onHoveredRow: {
                root.cursorActive = true
                root.cursorIndex = index
              }
              onActivated: function(paneId) { root.launchHerdr(paneId) }
            }
          }

          Text {
            width: parent.width
            text: "j/k navigate  ·  Enter open selected  ·  r refresh  ·  Esc close"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
