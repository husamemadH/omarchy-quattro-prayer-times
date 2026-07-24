import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "local.prayer-times"

  readonly property string iconGlyph: "" // nf-fa-mosque
  readonly property string cachePath: Quickshell.env("HOME") + "/.local/state/omarchy/settings/prayer-times.json"
  readonly property string scriptPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/local.prayer-times/prayer-fetch.sh"

  property var timings: null
  property string location: ""
  property string hijri: ""
  property string lastError: ""
  property bool popupOpen: false
  property date nowTick: new Date()

  readonly property var nextPrayer: Model.nextPrayer(timings, nowTick)
  readonly property string tooltipLabel: nextPrayer
    ? (location ? location + " · " : "") + nextPrayer.name + " in " + Model.timeRemaining(nextPrayer, nowTick) + " (" + Model.formatTime12(nextPrayer.time) + ")"
    : "Prayer times"

  function refresh() {
    if (!fetchProc.running) fetchProc.running = true
  }

  // Contract PopupCard expects on its `owner`: when the focus-grab dismisses
  // the popup (click outside), it calls owner.close() when present. Without
  // this, PopupCard falls back to writing its own `open` property directly,
  // which silently severs the `open: root.popupOpen` binding below and
  // leaves the popup permanently unable to reopen.
  function close() {
    root.popupOpen = false
  }

  function applyData(data) {
    if (!data || data.error) {
      root.lastError = (data && data.error) || "unknown error"
      return
    }
    root.timings = data.timings || null
    root.location = data.location || ""
    root.hijri = data.hijri || ""
    root.lastError = ""
  }

  Component.onCompleted: refresh()

  FileView {
    id: cacheFile
    path: root.cachePath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyData(Model.parseCache(text()))
    onFileChanged: reload()
  }

  Process {
    id: fetchProc
    command: ["bash", root.scriptPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyData(Model.parseCache(text))
    }
  }

  // Live countdown; cheap enough to tick every 30s without re-fetching.
  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.nowTick = new Date()
  }

  // Re-fetch once the calendar day rolls over.
  property string lastFetchDate: Qt.formatDate(new Date(), "yyyy-MM-dd")
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: {
      var today = Qt.formatDate(new Date(), "yyyy-MM-dd")
      if (today !== root.lastFetchDate) {
        root.lastFetchDate = today
        root.refresh()
      }
    }
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.iconGlyph
    tooltipText: root.tooltipLabel
    onPressed: function(b) {
      if (b === Qt.RightButton || b === Qt.MiddleButton) root.refresh()
      else root.popupOpen = !root.popupOpen
    }
  }

  PopupCard {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(220))
    contentHeight: popup.fittedContentHeight(col.implicitHeight)

    Column {
      id: col
      anchors.fill: parent
      spacing: Style.space(10)

      Row {
        spacing: Style.space(6)
        Text {
          text: root.iconGlyph
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.title
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          text: root.location || "Prayer times"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Text {
        visible: root.hijri !== ""
        text: root.hijri
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: root.lastError !== "" && !root.timings
        text: "Couldn't load prayer times (" + root.lastError + ")"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        width: parent.width
      }

      Repeater {
        model: root.timings ? Model.PRAYER_ORDER : []
        delegate: Row {
          required property string modelData

          readonly property bool isNext: root.nextPrayer && root.nextPrayer.name === modelData

          width: col.width
          spacing: Style.space(8)

          Text {
            width: Style.space(72)
            text: modelData
            color: isNext ? root.bar.urgent : root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: isNext
          }
          Text {
            text: root.timings[modelData] ? Model.formatTime12(root.timings[modelData]) : ""
            color: isNext ? root.bar.urgent : Qt.darker(root.bar.foreground, 1.2)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: isNext
          }
        }
      }

      Rectangle {
        width: parent.width
        height: Style.spacing.hairline
        color: root.bar.foreground
        opacity: 0.12
      }

      Text {
        text: "Left-click: toggle · Right/middle-click: refresh"
        color: Qt.darker(root.bar.foreground, 1.6)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        width: parent.width
      }
    }
  }
}
