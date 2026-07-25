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

  // Click-to-edit location, same mechanism as the weather widget: persists
  // to the shared weather.json via omarchy-weather-location, so editing the
  // location here also moves the weather widget's location.
  property bool editingLocation: false
  property bool savingLocation: false
  property var locationSuggestions: []
  property int suggestionIndex: 0
  property string geocodePendingQuery: ""
  property string geocodeActiveQuery: ""

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
    if (root.editingLocation) root.cancelEditingLocation()
    root.popupOpen = false
  }

  function startEditingLocation() {
    editingLocation = true
    savingLocation = false
    locationSuggestions = []
    suggestionIndex = 0
    Qt.callLater(function() {
      locationField.text = root.location
      locationField.selectAll()
      locationField.forceActiveFocus()
    })
  }

  function cancelEditingLocation() {
    editingLocation = false
    savingLocation = false
    locationSuggestions = []
    geocodeDebounce.stop()
  }

  function commitLocation() {
    var picked = Model.locationCommit(locationField.text, locationSuggestions, suggestionIndex)
    if (picked.name === "") {
      cancelEditingLocation()
      return
    }
    savingLocation = true
    persistLocation(picked.name, picked.latitude, picked.longitude)
  }

  function pickSuggestion(suggestion) {
    if (!suggestion) return
    savingLocation = true
    persistLocation(suggestion.name, suggestion.latitude, suggestion.longitude)
  }

  function persistLocation(name, latitude, longitude) {
    if (name && latitude !== null && longitude !== null)
      locationSaveProc.command = ["omarchy-weather-location", "--set", name, latitude + "," + longitude]
    else
      locationSaveProc.command = ["omarchy-weather-location", "--set", name]
    locationSaveProc.running = true
  }

  // Debounced geocoding, mirroring the weather widget's search-as-you-type.
  function requestGeocode() {
    var query = locationField.text.trim()
    if (query.length < 2) {
      locationSuggestions = []
      return
    }
    geocodePendingQuery = query
    if (!geocodeProc.running) startGeocode()
  }

  function startGeocode() {
    geocodeActiveQuery = geocodePendingQuery
    geocodeProc.command = ["curl", "-fsS", "--max-time", "5",
      "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(geocodeActiveQuery) + "&count=5&language=en&format=json"]
    geocodeProc.running = true
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

  Process {
    id: geocodeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.locationSuggestions = root.editingLocation ? Model.parseGeocodingResults(text) : []
        root.suggestionIndex = 0
        if (root.geocodePendingQuery !== root.geocodeActiveQuery) Qt.callLater(root.startGeocode)
      }
    }
  }

  Timer {
    id: geocodeDebounce
    interval: 300
    onTriggered: root.requestGeocode()
  }

  Process {
    id: locationSaveProc
    onExited: function(exitCode) {
      root.savingLocation = false
      root.editingLocation = false
      if (exitCode === 0) root.refresh()
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

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(220))
    contentHeight: popup.fittedContentHeight(col.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLocation
      onCloseRequested: root.close()

      Column {
        id: col
        anchors.fill: parent
        spacing: Style.space(10)

        Item {
          visible: !root.editingLocation
          width: locationRow.implicitWidth
          height: locationRow.implicitHeight

          Row {
            id: locationRow
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

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.startEditingLocation()
          }
        }

        Row {
          visible: root.editingLocation
          spacing: Style.space(6)

          TextField {
            id: locationField
            width: Style.space(190)
            enabled: !root.savingLocation
            placeholderText: "Search city"
            foreground: root.bar.foreground
            font.family: root.bar.fontFamily

            onTextChanged: if (root.editingLocation && !root.savingLocation) geocodeDebounce.restart()

            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.cancelEditingLocation()
                event.accepted = true
              } else if (event.key === Qt.Key_Down) {
                if (root.suggestionIndex < root.locationSuggestions.length - 1) root.suggestionIndex++
                event.accepted = true
              } else if (event.key === Qt.Key_Up) {
                if (root.suggestionIndex > 0) root.suggestionIndex--
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.commitLocation()
                event.accepted = true
              }
            }
          }

          Text {
            text: root.savingLocation ? "󰦖" : ""
            visible: root.savingLocation
            anchors.verticalCenter: parent.verticalCenter
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall

            RotationAnimator on rotation {
              running: root.savingLocation
              from: 0; to: 360
              duration: 800
              loops: Animation.Infinite
            }
          }
        }

        Column {
          visible: root.editingLocation && !root.savingLocation && root.locationSuggestions.length > 0
          width: parent.width
          spacing: 0

          Repeater {
            model: root.locationSuggestions

            Rectangle {
              required property var modelData
              required property int index
              width: parent.width
              height: suggestionRow.implicitHeight + Style.space(10)
              radius: Style.cornerRadius
              color: index === root.suggestionIndex ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"

              Row {
                id: suggestionRow
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)

                Text {
                  text: modelData.name
                  color: index === root.suggestionIndex ? Style.hoverStateColor(root.bar.foreground, Color.accent) : root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  visible: text !== ""
                  text: modelData.description
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: root.suggestionIndex = index
                onClicked: root.pickSuggestion(modelData)
              }
            }
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
}
