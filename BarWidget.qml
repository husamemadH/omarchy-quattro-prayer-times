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
  // Which madhhab the cached timings were actually fetched under, echoed back
  // by the API. Compared against hanafiAsr so a refetch that failed (offline,
  // API down) can't leave the popup quietly showing the other school's Asr.
  property string cachedSchool: ""
  property string lastError: ""
  property bool popupOpen: false
  property date nowTick: new Date()

  // Arrival alerts: the key of the last prayer notified (see Model.prayerKey),
  // and the moment the widget started — prayers whose time already passed
  // before startup must not fire a stale toast on a shell restart.
  property string lastNotifiedKey: ""
  readonly property date startedAt: new Date()

  // Alerts on/off, persisted next to the cached times in its own file —
  // prayer-times.json is rewritten wholesale by prayer-fetch.sh, so a
  // preference stored in there would be lost on the next refresh.
  readonly property string settingsPath: Quickshell.env("HOME") + "/.local/state/omarchy/settings/prayer-alerts.json"
  readonly property string soundPath: "/usr/share/sounds/freedesktop/stereo/bell.oga"
  property bool alertsEnabled: true
  property bool soundEnabled: true

  // Asr per the Hanafi madhhab (shadow twice the object's length) instead of
  // the standard one (shadow equal to it), which puts Asr roughly an hour
  // later. The whole timetable is recomputed server-side, so flipping this
  // has to re-fetch rather than shift the cached time locally.
  property bool hanafiAsr: false

  property bool settingsLoaded: false
  // A refresh asked for before the preference file had been read, or while a
  // fetch was already in flight. Drained by markSettingsReady/fetchProc.
  property bool refetchQueued: false

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
  // True when the times on screen were fetched under the other madhhab.
  readonly property bool asrOutOfDate: root.timings !== null && root.cachedSchool !== ""
    && root.cachedSchool !== (root.hanafiAsr ? "HANAFI" : "STANDARD")

  readonly property string tooltipLabel: nextPrayer
    ? (location ? location + " · " : "") + nextPrayer.name + " in " + Model.timeRemaining(nextPrayer, nowTick) + " (" + Model.formatTime12(nextPrayer.time) + ")"
    : "Prayer times"

  // Countdown beside the icon. Off by default: this widget is built to sit
  // among the wifi/sound icons, and a label changes how much of the bar it
  // claims, so that is the user's call rather than ours. Flipped by the
  // toggle at the bottom of the popup, stored with the alert preferences.
  property bool showCountdown: false

  // The same countdown the tooltip spells out, trimmed to what fits in a bar
  // slot ("Asr 1h 4m"). Empty until the first fetch lands, so the icon stands
  // alone rather than the bar holding width for a placeholder.
  readonly property string countdownText: Model.countdownLabel(nextPrayer, nowTick)

  // A vertical bar has no room for a label, so there the countdown stays in
  // the tooltip whatever the setting says.
  readonly property bool countdownVisible: showCountdown && !vertical && countdownText !== ""

  // Minutes left at which the label takes the urgent accent -- the same colour
  // the popup already gives the next prayer, so the bar and the list agree on
  // what is imminent.
  readonly property int urgentMinutes: 10
  readonly property bool countdownUrgent: {
    var left = Model.minutesRemaining(nextPrayer, nowTick)
    return left >= 0 && left <= urgentMinutes
  }

  // With the label on, this module is a text row in a padded slot, so the
  // open-panel mark tracks what it paints instead of a fraction of the slot it
  // fills -- the same hint the built-in clock gives. Icon-only, the bar's
  // default mark is already right.
  readonly property real openPanelIndicatorWidth: countdownVisible ? content.implicitWidth : 0

  // prayer-fetch.sh is told which Asr to ask for on the command line, so the
  // first fetch has to wait for the preference file: firing before it is read
  // would pull Standard times and visibly correct them a moment later.
  function refresh() {
    if (!root.settingsLoaded || fetchProc.running) {
      root.refetchQueued = true
      return
    }
    root.refetchQueued = false
    fetchProc.running = true
  }

  function markSettingsReady() {
    root.settingsLoaded = true
    if (root.refetchQueued) Qt.callLater(root.refresh)
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

  function loadSettings(raw) {
    if (root.settingsLoaded) return
    var settings = Model.parseSettings(raw)
    root.alertsEnabled = settings.alerts
    root.soundEnabled = settings.sound
    root.showCountdown = settings.countdown
    root.hanafiAsr = settings.hanafiAsr
    root.markSettingsReady()
  }

  function saveSettings() {
    // The file loads asynchronously; marking it loaded here keeps a toggle
    // made in that first moment from being overwritten by the load that
    // lands after it.
    settingsFile.setText(JSON.stringify({
      version: 4,
      alerts: root.alertsEnabled,
      sound: root.soundEnabled,
      countdown: root.showCountdown,
      hanafiAsr: root.hanafiAsr
    }, null, 2) + "\n")
    root.markSettingsReady()
  }

  // Normal urgency: the shell floors it at 8s and gives it the regular
  // accent. Low urgency would allow a 5s toast, but it also renders in the
  // dim "unimportant" tier — too easy to miss, which is the whole point of
  // the alert. Critical is the other extreme: it never auto-dismisses.
  function notifyPrayer(prayer) {
    if (!prayer) return
    notifyProc.running = false
    notifyProc.command = ["notify-send", "-a", "Prayer times", "-u", "normal",
      prayer.name, "It's time for " + prayer.name + " · " + Model.formatTime12(prayer.time)]
    notifyProc.running = true
    if (root.soundEnabled) {
      soundProc.running = false
      soundProc.command = ["paplay", root.soundPath]
      soundProc.running = true
    }
  }

  function checkPrayerArrived() {
    if (!root.alertsEnabled) return
    var now = new Date()
    var due = Model.duePrayer(root.timings, now, root.arrivalWindowMs)
    if (!due || due.date.getTime() < root.startedAt.getTime()) return
    var key = Model.prayerKey(due)
    if (key === root.lastNotifiedKey) return
    root.lastNotifiedKey = key
    root.notifyPrayer(due)
  }

  function applyData(data) {
    if (!data || data.error) {
      root.lastError = (data && data.error) || "unknown error"
      return
    }
    root.timings = data.timings || null
    root.location = data.location || ""
    root.hijri = data.hijri || ""
    root.cachedSchool = data.school || ""
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

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadSettings(text())
    // First run: no file yet. Without this the preference would never load
    // and the first toggle would be dropped as "not loaded".
    onLoadFailed: root.loadSettings("")
  }

  Process {
    id: fetchProc
    command: ["bash", root.scriptPath, Model.asrArg(root.hanafiAsr)]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyData(Model.parseCache(text))
    }
    // A toggle flipped mid-fetch would otherwise be dropped, leaving the
    // popup on the school the in-flight run had already asked for.
    onExited: if (root.refetchQueued) Qt.callLater(root.refresh)
  }

  Process { id: notifyProc }
  Process { id: soundProc }

  // Polls for a prayer whose time just landed. The window is wider than the
  // interval so a missed tick (suspend, clock jump) still alerts; the
  // lastNotifiedKey guard keeps it to one toast per prayer.
  readonly property int arrivalWindowMs: 60000
  Timer {
    interval: 10000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.checkPrayerArrived()
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

  // Icon, plus the countdown when it is switched on. Laid out the way the
  // built-in media widget does it: a Row paints the content inside a
  // WidgetButton whose own label is off, so the button still supplies the
  // bar's tooltip, click registration and hover handling while the width
  // follows the text. With the label hidden the slot is the same icon slot
  // BarIconButton was giving.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    tooltipText: root.tooltipLabel
    fixedWidth: root.vertical
      ? -1
      : (root.countdownVisible ? content.implicitWidth + button.scaledHorizontalMargin * 2 : Style.bar.iconSlot)
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1

    onPressed: function(b) {
      if (b === Qt.RightButton || b === Qt.MiddleButton) root.refresh()
      else root.popupOpen = !root.popupOpen
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(6)

      // OpticalGlyph rather than a bare Text: it puts the mosque on the same
      // optical centre as every other icon in the bar.
      OpticalGlyph {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.bar.iconCanvas
        height: Style.bar.iconCanvas
        text: root.iconGlyph
        fontFamily: button.fontFamily
        fontSize: Style.bar.iconFont
        color: button.foreground
      }

      // Hidden rather than blank: Row leaves invisible children out, so the
      // button shrinks back to the icon slot.
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.countdownVisible
        text: root.countdownText
        color: root.countdownUrgent ? button.activeColor : button.foreground
        font.family: button.fontFamily
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering

        Behavior on color {
          enabled: !root.bar || root.bar.foregroundAnimationEnabled
          ColorAnimation { duration: 160 }
        }
      }
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

        // Only after a re-fetch has failed: the times above are still the
        // other madhhab's, and Asr is the one that differs.
        Text {
          visible: root.asrOutOfDate
          text: "Still showing " + (root.cachedSchool === "HANAFI" ? "Hanafi" : "standard")
            + " Asr — right-click the icon to retry"
          color: root.bar.urgent
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          width: parent.width
        }

        Rectangle {
          width: parent.width
          height: Style.spacing.hairline
          color: root.bar.foreground
          opacity: 0.12
        }

        // Above the alert switches because this one changes the times
        // themselves, not just how they are announced.
        Toggle {
          width: parent.width
          label: "Hanafi Asr"
          description: root.hanafiAsr ? "Shadow twice the object" : "Standard — shadow equal to the object"
          checked: root.hanafiAsr
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          titleSize: Style.font.bodySmall
          onClicked: {
            root.hanafiAsr = !root.hanafiAsr
            root.saveSettings()
            root.refresh()
          }
        }

        Toggle {
          width: parent.width
          label: "Alerts"
          description: root.alertsEnabled ? "Toast at prayer time" : "Off"
          checked: root.alertsEnabled
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          titleSize: Style.font.bodySmall
          onClicked: {
            root.alertsEnabled = !root.alertsEnabled
            root.saveSettings()
          }
        }

        // Hidden when alerts are off: the sound only ever plays alongside a
        // toast, so on its own the switch would control nothing.
        Toggle {
          visible: root.alertsEnabled
          width: parent.width
          label: "Sound"
          description: root.soundEnabled ? "Chime with the toast" : "Silent"
          checked: root.soundEnabled
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          titleSize: Style.font.bodySmall
          onClicked: {
            root.soundEnabled = !root.soundEnabled
            root.saveSettings()
          }
        }

        // Last of the switches: the only one that changes nothing but how the
        // bar looks. Hidden on a vertical bar, where there is no room for the
        // label and the toggle would control nothing.
        Toggle {
          visible: !root.vertical
          width: parent.width
          label: "Countdown in bar"
          description: root.showCountdown ? "Next prayer and time left beside the icon" : "Icon only"
          checked: root.showCountdown
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          titleSize: Style.font.bodySmall
          onClicked: {
            root.showCountdown = !root.showCountdown
            root.saveSettings()
          }
        }

        Text {
          text: "Right/middle-click the icon to refresh"
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
