import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  property var agent: ({})
  property bool selected: false
  property bool pending: false
  property bool animationsEnabled: false
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family
  property bool pointerHovered: hoverHandler.hovered

  signal activated(string paneId)
  signal hoveredRow()

  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color stateColor: {
    if (pending || agent.status === "done" || agent.status === "blocked") return urgent
    if (agent.status === "working") return accent
    return dim
  }

  function alpha(color, amount) { return Qt.rgba(color.r, color.g, color.b, amount) }

  function activate() {
    activated(String(agent.paneId || ""))
  }

  implicitHeight: Style.space(62)
  color: selected || pointerHovered ? Style.hoverFillFor(foreground, accent) : "transparent"
  borderSpec: selected
    ? Border.controlSpec("normal", foreground, accent)
    : Border.flat(alpha(foreground, 0.13), 1)
  radius: Style.cornerRadius

  HoverHandler {
    id: hoverHandler
    onHoveredChanged: if (hovered) root.hoveredRow()
  }

  TapHandler {
    acceptedButtons: Qt.LeftButton
    onTapped: root.activate()
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Style.space(12)
    anchors.rightMargin: Style.space(10)
    anchors.topMargin: Style.space(8)
    anchors.bottomMargin: Style.space(8)
    spacing: Style.space(10)

    Item {
      Layout.preferredWidth: Style.space(20)
      Layout.fillHeight: true

      Rectangle {
        anchors.centerIn: parent
        width: Style.space(9)
        height: width
        radius: width / 2
        color: root.stateColor

        SequentialAnimation on opacity {
          running: root.animationsEnabled && root.agent.status === "working"
          loops: Animation.Infinite
          NumberAnimation { from: 1; to: 0.35; duration: 800; easing.type: Easing.InOutSine }
          NumberAnimation { from: 0.35; to: 1; duration: 800; easing.type: Easing.InOutSine }
        }
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      spacing: Style.space(2)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(7)

        Text {
          Layout.fillWidth: true
          text: String(root.agent.workspaceLabel || "Herdr")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          visible: root.agent.focused === true
          text: "FOCUSED"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      Text {
        Layout.fillWidth: true
        text: String(root.agent.detail || root.agent.agentLabel || "Agent")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideMiddle
      }
    }

    BorderSurface {
      Layout.alignment: Qt.AlignVCenter
      implicitWidth: statusText.implicitWidth + Style.space(12)
      implicitHeight: statusText.implicitHeight + Style.space(6)
      color: root.alpha(root.stateColor, 0.10)
      borderSpec: Border.flat(root.alpha(root.stateColor, 0.35), 1)
      radius: Style.cornerRadius

      Text {
        id: statusText
        anchors.centerIn: parent
        text: root.pending ? "FINISHED" : String(root.agent.status || "unknown").toUpperCase()
        color: root.stateColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }
}
