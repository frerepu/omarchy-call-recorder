import QtQuick
import qs.Commons
import qs.Commons as Commons

Column {
  id: root

  property string label: ""
  property real level: 0
  property bool muted: false
  property bool paused: false
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(5)

  // Strings live in i18n/<code>.json beside the QML and are read live, so a
  // language change under Setup > Language re-renders without a shell restart.
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  Row {
    width: parent.width

    Text {
      textFormat: Text.PlainText
      text: root.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }

    Item {
      width: Math.max(0, parent.width - parent.children[0].implicitWidth - status.implicitWidth)
      height: 1
    }

    Text {
      id: status
      textFormat: Text.PlainText
      text: root.paused
              ? strings.t("meter.paused")
              : (root.muted
                   ? strings.t("meter.muted")
                   : strings.t("meter.level").arg(Commons.I18n.formatNumber(Math.round(root.level * 100))))
      color: root.muted || root.paused ? Qt.darker(root.foreground, 1.45) : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 0.8
    }
  }

  Rectangle {
    width: parent.width
    height: Style.space(8)
    radius: height / 2
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

    Rectangle {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      height: parent.height
      radius: parent.radius
      width: root.paused ? 0 : Math.max(height, parent.width * Math.max(0, Math.min(1, root.level)))
      opacity: root.muted ? 0.35 : 1
      color: root.level > 0.92 ? root.urgent : root.foreground

      // Durations go through Style.duration so they collapse to 0 when the user
      // turns animations off with `omarchy toggle animations`, and the curve is
      // an ease-out as the shell's motion guidance requires.
      Behavior on width { NumberAnimation { duration: Style.duration(90); easing.type: Easing.OutCubic } }
      Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
      Behavior on color { ColorAnimation { duration: Style.duration(100); easing.type: Easing.OutCubic } }
    }
  }
}
