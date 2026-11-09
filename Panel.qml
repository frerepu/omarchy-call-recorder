import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "illegalstudio.omarchy-call-recorder"
  manageIpc: false

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property string configuredMicrophone: String(setting("microphone", "") || "")
  readonly property string configuredDesktopOutput: String(setting("desktopOutput", "") || "")
  readonly property string configuredRecordingDirectory: String(setting("recordingDirectory", "") || "")
  readonly property int configuredNagMinutes: Number(setting("nagMinutes", 15))
  readonly property bool configuredStopOnSuspend: setting("stopOnSuspend", true) !== false
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Cogwheel state. The folder list is built from $HOME rather than hardcoded
  // so it follows the user, and the recorder creates the directory on first
  // use, so an entry that does not exist yet is still a valid choice.
  property bool settingsOpen: false
  readonly property string homeDirectory: String(Quickshell.env("HOME") || "")
  readonly property string defaultRecordingDirectory: root.homeDirectory + "/Music/Recordings"
  readonly property string effectiveRecordingDirectory: root.configuredRecordingDirectory !== ""
    ? root.configuredRecordingDirectory
    : root.defaultRecordingDirectory
  readonly property var recordingDirectoryOptions: {
    var options = [root.defaultRecordingDirectory,
                   root.homeDirectory + "/Documents/Recordings",
                   root.homeDirectory + "/Videos/Recordings",
                   root.homeDirectory + "/Nextcloud/Recordings"]
    // A folder set outside the panel would otherwise have no matching row and
    // the dropdown would render blank.
    if (options.indexOf(root.effectiveRecordingDirectory) === -1)
      options.unshift(root.effectiveRecordingDirectory)
    return options
  }

  // Strings live in i18n/<code>.json beside the QML. Every t() call stays inside
  // a binding so switching language re-renders without a shell restart.
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  Binding {
    target: root.service
    property: "preferredMicrophone"
    value: root.configuredMicrophone
    when: root.service !== null
  }

  Binding {
    target: root.service
    property: "preferredDesktopOutput"
    value: root.configuredDesktopOutput
    when: root.service !== null
  }

  Binding {
    target: root.service
    property: "recordingDirectory"
    value: root.configuredRecordingDirectory
    when: root.service !== null
  }

  Binding {
    target: root.service
    property: "nagMinutes"
    value: root.configuredNagMinutes
    when: root.service !== null
  }

  Binding {
    target: root.service
    property: "stopOnSuspend"
    value: root.configuredStopOnSuspend
    when: root.service !== null
  }

  function selectMicrophone(name) {
    var next = Object.assign({}, settings, { microphone: String(name || "") })
    settings = next
    if (bar && bar.shell) bar.shell.updateEntryInline(moduleName, next)
    if (service) service.setMicrophone(name)
  }

  function selectRecordingDirectory(path) {
    var next = Object.assign({}, settings, { recordingDirectory: String(path || "") })
    settings = next
    if (bar && bar.shell) bar.shell.updateEntryInline(moduleName, next)
    // The recordingDirectory Binding carries the change to the service, so the
    // next take lands in the new folder without restarting the shell.
  }

  function togglePause() {
    if (service) service.togglePause()
  }

  function selectDesktopOutput(name) {
    var next = Object.assign({}, settings, { desktopOutput: String(name || "") })
    settings = next
    if (bar && bar.shell) bar.shell.updateEntryInline(moduleName, next)
    if (service) service.setDesktopOutput(name)
  }

  function toggleMicrophoneMute() {
    if (service) service.setMicrophoneMuted(!service.microphoneMuted)
  }

  function toggleDesktopMute() {
    if (service) service.setDesktopMuted(!service.desktopMuted)
  }

  onOpenedChanged: {
    if (opened && service) service.refreshDevices()
  }

  onVisibleChanged: {
    if (!visible && opened) close()
  }

  // Shown whenever the plugin is loaded, so the recorder is reachable without
  // remembering the keybind. BarIconButton.active dims it while idle, which is
  // how the bar's other widgets distinguish a live state from a resting one.
  visible: service !== null
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  readonly property bool recordingActive: service ? service.active : false

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.service && root.service.paused ? "" : ""
    active: root.recordingActive
    tooltipText: {
      if (!root.service) return strings.t("tooltip.idle")
      if (!root.recordingActive) return strings.t("tooltip.idle")
      var label = strings.t(root.service.paused ? "tooltip.paused" : "tooltip.recording")
      return label + " · " + root.service.formatElapsed(root.service.elapsedSeconds)
    }
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.visible
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "p" || text === "P") root.togglePause()
        else if (text === "m" || text === "M") root.toggleMicrophoneMute()
        else if (text === "d" || text === "D") root.toggleDesktopMute()
        else if ((text === "s" || text === "S") && root.service) root.service.stopRecording()
        else if (text === "g" || text === "G") root.settingsOpen = !root.settingsOpen
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(13)

        Item {
          id: heroHost
          width: parent.width
          implicitHeight: hero.implicitHeight
          readonly property color iconColor: !root.recordingActive || (root.service && root.service.paused)
            ? root.dim
            : root.urgent

          Button {
            id: settingsToggle
            anchors.right: parent.right
            anchors.top: parent.top
            z: 1
            iconText: ""
            tooltipText: strings.t("panel.settings")
            foreground: root.settingsOpen ? root.foreground : root.dim
            fontFamily: root.fontFamily
            onClicked: root.settingsOpen = !root.settingsOpen
          }

          PanelHero {
            id: hero
            // Leave room for the cogwheel so a long title cannot run under it.
            width: parent.width - settingsToggle.implicitWidth
            title: strings.t("panel.title")
            meta: {
              if (!root.service) return strings.t("panel.meta.starting")
              if (root.service.finalizing)
                return strings.t("panel.meta.finalizing").arg(Commons.I18n.formatNumber(root.service.exportProgress))
              if (root.service.stopping) return strings.t("panel.meta.saving")
              if (root.service.paused) return strings.t("panel.meta.paused")
              if (root.service.starting) return strings.t("panel.meta.starting")
              return strings.t("panel.meta.idle")
            }
            // Without the idle branch the panel keeps showing the finished take's
            // length, which reads as a run still in progress.
            detail: root.service && root.recordingActive
              ? root.service.formatElapsed(root.service.elapsedSeconds)
              : "00:00"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: root.service && root.service.paused ? "" : ""
                color: heroHost.iconColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                font.bold: true
              }
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        Dropdown {
          id: microphonePicker
          width: parent.width
          label: strings.t("panel.microphone")
          value: root.service ? root.service.currentMicrophone : ""
          options: root.service ? root.service.microphones : []
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(value) { root.selectMicrophone(value) }
        }

        Dropdown {
          id: desktopPicker
          width: parent.width
          label: strings.t("panel.desktopOutput")
          value: root.configuredDesktopOutput
          options: root.service ? root.service.desktopOutputOptions : []
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(value) { root.selectDesktopOutput(value) }
        }

        Text {
          width: parent.width
          text: root.service ? root.service.desktopStatus : ""
          textFormat: Text.PlainText
          color: root.service && !root.service.desktopHealthy ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        PanelSeparator {
          foreground: root.foreground
          visible: root.settingsOpen
        }

        PanelSectionHeader {
          visible: root.settingsOpen
          text: strings.t("panel.settings")
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Dropdown {
          id: folderPicker
          visible: root.settingsOpen
          width: parent.width
          label: strings.t("panel.recordingFolder")
          value: root.effectiveRecordingDirectory
          options: root.recordingDirectoryOptions
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(value) { root.selectRecordingDirectory(value) }
        }

        Text {
          visible: root.settingsOpen
          width: parent.width
          text: strings.t("panel.recordingFolderHint")
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        PanelSeparator { foreground: root.foreground }

        PanelSectionHeader {
          text: strings.t("panel.recordedLevels")
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        LevelMeter {
          label: strings.t("panel.microphone")
          level: root.service ? root.service.microphoneLevel : 0
          muted: root.service ? root.service.microphoneMuted : false
          paused: root.service ? root.service.paused : false
          foreground: root.foreground
          urgent: root.urgent
          fontFamily: root.fontFamily
        }

        LevelMeter {
          label: strings.t("panel.desktopAudio")
          level: root.service ? root.service.desktopLevel : 0
          muted: root.service ? root.service.desktopMuted : false
          paused: root.service ? root.service.paused : false
          foreground: root.foreground
          urgent: root.urgent
          fontFamily: root.fontFamily
        }

        PanelSeparator { foreground: root.foreground }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            width: (parent.width - parent.spacing) / 2
            text: strings.t(root.service && root.service.paused ? "panel.resume" : "panel.pause")
            iconText: root.service && root.service.paused ? "" : ""
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.togglePause()
          }

          Button {
            width: (parent.width - parent.spacing) / 2
            text: strings.t(root.service && root.service.microphoneMuted ? "panel.unmuteMic" : "panel.muteMic")
            iconText: root.service && root.service.microphoneMuted ? "" : ""
            selected: root.service ? root.service.microphoneMuted : false
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.toggleMicrophoneMute()
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            width: (parent.width - parent.spacing) / 2
            text: strings.t(root.service && root.service.desktopMuted ? "panel.unmuteDesktop" : "panel.muteDesktop")
            iconText: root.service && root.service.desktopMuted ? "󰖁" : "󰕾"
            selected: root.service ? root.service.desktopMuted : false
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.toggleDesktopMute()
          }

          Button {
            width: (parent.width - parent.spacing) / 2
            visible: root.recordingActive
            text: strings.t("panel.stopAndSave")
            iconText: ""
            bordered: true
            foreground: root.urgent
            fontFamily: root.fontFamily
            onClicked: if (root.service) root.service.stopRecording()
          }

          // The panel is reachable while idle now, so it needs its own way to
          // begin a take rather than only offering controls for one in flight.
          Button {
            width: (parent.width - parent.spacing) / 2
            visible: !root.recordingActive
            text: strings.t("panel.startRecording")
            iconText: ""
            bordered: true
            foreground: root.urgent
            fontFamily: root.fontFamily
            onClicked: if (root.service) root.service.startRecording()
          }
        }

        Text {
          width: parent.width
          visible: root.service && root.service.outputPath !== ""
          text: root.service ? root.service.outputPath : ""
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
        }

        Text {
          width: parent.width
          visible: root.service && root.service.recording
          text: strings.t("panel.tracksHint")
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: root.service && root.service.errorText !== ""
          text: root.service ? root.service.errorText : ""
          textFormat: Text.PlainText
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          text: strings.t("panel.shortcuts")
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }
}
