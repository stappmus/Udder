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

  function alpha(color, amount) { return Qt.rgba(color.r, color.g, color.b, amount) }

  function heroMeta() {
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
    if (herdr.pendingCount > 0)
      return herdr.pendingCount + " finished · click to open Herdr"
    if (herdr.clientAttached) return "Herdr is open · monitoring paused"
    if (herdr.state === "ready")
      return herdr.counts.total + " Herdr agent" + (herdr.counts.total === 1 ? "" : "s")
    return "Udder · Herdr agents"
  }

  function launchHerdr(target) {
    var paneId = ""
    if (typeof target === "string") paneId = target
    else if (target && target.paneId) paneId = String(target.paneId)
    else if (herdr.pendingCount > 0) paneId = herdr.pendingPaneId()
    herdr.clearPending()
    close()
    herdr.openHerdr(paneId)
  }

  function launchSelectedHerdr() {
    if (herdr.agents.length > 0 && cursorIndex >= 0 && cursorIndex < herdr.agents.length)
      launchHerdr(herdr.agents[cursorIndex])
    else
      launchHerdr()
  }

  function moveCursor(delta) {
    if (herdr.agents.length === 0) return
    cursorActive = true
    cursorIndex = Math.max(0, Math.min(herdr.agents.length - 1, cursorIndex + delta))
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
    if (herdr.agents.length === 0) cursorIndex = 0
    else cursorIndex = Math.max(0, Math.min(herdr.agents.length - 1, cursorIndex))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    herdr.panelVisible = opened
    if (opened) {
      cursorActive = false
      cursorIndex = 0
      if (panelFlick) panelFlick.contentY = 0
      herdr.refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  Service {
    id: herdr
    settings: root.settings
    onAgentsChanged: root.ensureCursor()
    onTerminalLaunchRequested: Quickshell.execDetached([herdr.pluginRoot + "/udder-open"])
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { herdr.refresh(); return "ok" }
    function event(eventJson: string, contextJson: string): string {
      herdr.handleEvent(eventJson, contextJson)
      return "ok"
    }
    function openHerdr(): void { root.launchHerdr() }
    function clientActive(): void { herdr.applyClientAttached(true) }
    function status(): string {
      return JSON.stringify({
        state: herdr.state,
        agents: herdr.counts,
        clientAttached: herdr.clientAttached,
        pending: herdr.pendingCount,
        integration: herdr.integrationState
      })
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰆚"
    active: herdr.pendingCount > 0 && !herdr.clientAttached
    dimmed: herdr.clientAttached
    tooltipText: root.tooltipText()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) {
        root.launchHerdr()
      } else if (buttonCode === Qt.RightButton) {
        herdr.refresh()
      } else if (herdr.pendingCount > 0 && !herdr.clientAttached) {
        root.launchHerdr()
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
        if (text === "r" || text === "R") herdr.refresh()
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
            title: "Udder"
            meta: root.heroMeta()
            detail: herdr.clientAttached ? "ATTACHED" : (herdr.pendingCount > 0 ? herdr.pendingCount + " READY" : "WATCHING")
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
            visible: herdr.state !== "ready"
            width: parent.width
            implicitHeight: serverStatus.implicitHeight + Style.space(20)
            color: root.alpha(herdr.state === "offline" ? root.foreground : root.urgent, 0.08)
            borderSpec: Border.flat(root.alpha(herdr.state === "offline" ? root.foreground : root.urgent, 0.30), 1)
            radius: Style.cornerRadius

            Text {
              id: serverStatus
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(10)
              text: herdr.message
              color: herdr.state === "offline" ? root.dim : root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }
          }

          BorderSurface {
            visible: herdr.integrationState !== "ready" && herdr.integrationState !== "checking"
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
            text: "HERDR AGENTS  " + herdr.agents.length
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          BorderSurface {
            visible: herdr.state === "ready" && herdr.agents.length === 0
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
            model: herdr.agents

            AgentRow {
              required property int index
              required property var modelData
              width: content.width
              agent: modelData
              pending: herdr.isPending(modelData.paneId)
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
