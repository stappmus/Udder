import QtQuick
import Quickshell
import "plugin" as Udder

ShellRoot {
  id: shell

  readonly property string focusProbePaneId: Quickshell.env("UDDER_SMOKE_PANE_ID") || ""
  property bool focusProbePassed: focusProbePaneId === ""
  property bool rowProbePassed: false

  QtObject {
    id: fakeBar
    property color foreground: "#d8dee9"
    property color barForeground: foreground
    property color urgent: "#bf616a"
    property string fontFamily: "monospace"
    property string position: "top"
    property int barSize: 26
    property bool vertical: false
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    property var clickTargets: []

    function registerClickTarget(target) {}
    function unregisterClickTarget(target) {}
    function showTooltip(target, text) {}
    function hideTooltip(target) {}
    function requestPopout(target) { activePopout = target }
    function releasePopout(target) { if (activePopout === target) activePopout = null }
    function moduleWidgets(name) { return [] }
    function switchPanelFrom(panel, direction) { return false }
  }

  Udder.Panel {
    id: widget
    bar: fakeBar
    settings: ({
      autoRegisterEvents: false,
      panelRefreshIntervalSec: 2,
      clientCheckIntervalSec: 5
    })
    Component.onCompleted: open()
  }

  Udder.Service {
    id: focusProbe
    settings: ({ autoRegisterEvents: false })
    onTerminalLaunchRequested: shell.focusProbePassed = true
  }

  Udder.AgentRow {
    id: rowProbe
    visible: false
    agent: ({ paneId: "w7:p1", workspaceLabel: "Speaker adjustment", status: "idle" })
    onActivated: function(paneId) { shell.rowProbePassed = paneId === "w7:p1" }
    Component.onCompleted: activate()
  }

  Timer {
    interval: 1
    running: shell.focusProbePaneId !== ""
    onTriggered: focusProbe.openHerdr(shell.focusProbePaneId)
  }

  Timer {
    interval: 1200
    running: true
    onTriggered: {
      if (!shell.focusProbePassed || !shell.rowProbePassed) {
        console.error("udder qml focus smoke failed", shell.focusProbePassed, shell.rowProbePassed)
        widget.close()
        Qt.quit()
        return
      }
      console.log("udder qml smoke passed", widget.width, widget.height, widget.opened, "focus", shell.focusProbePassed, "row", shell.rowProbePassed)
      widget.close()
      Qt.quit()
    }
  }
}
