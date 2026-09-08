import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Downloader.js" as Downloader

Panel {
  id: root
  moduleName: "billy.ytdl"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  property string inputUrl: ""
  property bool isAudioMode: true // Default: AUDIO mode
  property int selectedAudioIndex: 0
  property int selectedVideoIndex: 0

  readonly property var currentFormats: isAudioMode ? Downloader.AUDIO_FORMATS : Downloader.VIDEO_FORMATS
  readonly property var currentFormat: isAudioMode
    ? Downloader.AUDIO_FORMATS[selectedAudioIndex]
    : Downloader.VIDEO_FORMATS[selectedVideoIndex]

  property bool dropdownOpen: false
  property int taglineIndex: 0
  readonly property var taglines: Downloader.TAGLINES
  readonly property string currentTagline: taglines[taglineIndex % taglines.length]

  property string videoTitle: ""
  property string videoDuration: ""
  property bool metadataLoading: false

  property var queue: []
  property var recentDownloads: []
  readonly property bool isDownloading: ytdlp.running

  function open() {
    root.controller.show()
    checkClipboard()
    cycleTagline()
    Qt.callLater(function() {
      if (root.inputUrl === "") urlField.forceActiveFocus()
      else keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    root.controller.hide()
    root.dropdownOpen = false
    // Auto-clear recent downloads on close as requested
    root.recentDownloads = []
  }

  function toggle() {
    if (opened) close()
    else open()
  }

  function cycleTagline() {
    taglineIndex = (taglineIndex + 1) % taglines.length
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function") {
      return root.bar.switchPanelFrom(root, direction)
    }
    return false
  }

  function checkClipboard() {
    if (!clipboardProc.running) {
      clipboardProc.running = true
    }
  }

  function pasteFromClipboard() {
    checkClipboard()
  }

  function fetchMetadata(url) {
    if (!url || !Downloader.isValidUrl(url)) return
    if (metaProc.running) metaProc.running = false
    root.metadataLoading = true
    root.videoTitle = ""
    root.videoDuration = ""
    metaProc.command = ["yt-dlp", "--dump-json", "--no-playlist", "--skip-download", url]
    metaProc.running = true
  }

  function startDownload() {
    var url = Downloader.cleanUrl(root.inputUrl)
    if (!url) return

    var fmt = root.currentFormat
    var homeDir = Quickshell.env("HOME") || "/home/billy"
    var dest = fmt.isAudio ? (homeDir + "/Music") : (homeDir + "/Videos")
    var title = root.videoTitle !== "" ? root.videoTitle : "Fetch Stream"

    var task = {
      url: url,
      format: fmt,
      title: title,
      destination: dest
    }

    if (ytdlp.running) {
      var q = root.queue.slice()
      q.push(task)
      root.queue = q
      notifyProc.send("Queued", title + " (" + fmt.label + ")", "media-playback-start")
    } else {
      ytdlp.start(task)
    }

    root.inputUrl = ""
    root.videoTitle = ""
    root.videoDuration = ""
    root.dropdownOpen = false
  }

  Timer {
    id: taglineTimer
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: root.cycleTagline()
  }

  Process {
    id: clipboardProc
    command: ["wl-paste", "--no-newline"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (Downloader.isValidUrl(raw)) {
          if (root.inputUrl !== raw) {
            root.inputUrl = raw
            root.fetchMetadata(raw)
          }
        }
      }
    }
  }

  Process {
    id: metaProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.metadataLoading = false
        try {
          var meta = JSON.parse(String(text || "").trim())
          if (meta && meta.title) {
            root.videoTitle = meta.title
            root.videoDuration = meta.duration_string || Downloader.formatDuration(meta.duration)
          }
        } catch (e) {}
      }
    }
    onExited: function(exitCode) {
      root.metadataLoading = false
    }
  }

  Process {
    id: notifyProc
    function send(title, body, icon) {
      command = ["notify-send", "-a", "Fetch", "-i", icon || "video-x-generic", title, body]
      running = true
    }
  }

  Process {
    id: xdgProc
    function openTarget(path) {
      if (path && path !== "") {
        command = ["xdg-open", path]
        running = true
      }
    }
  }

  YtDlpProcess {
    id: ytdlp
    onFinished: function(task, success, filePath, errorMsg) {
      if (success) {
        var rec = root.recentDownloads.slice()
        rec.unshift({
          title: task.title,
          filePath: filePath,
          isAudio: task.format.isAudio,
          format: task.format.label
        })
        if (rec.length > 3) rec = rec.slice(0, 3)
        root.recentDownloads = rec

        notifyProc.send("Download Complete", (task.title || "Media") + "\nSaved to " + task.destination, task.format.isAudio ? "audio-x-generic" : "video-x-generic")
      } else {
        notifyProc.send("Download Failed", errorMsg || "Download failed", "dialog-error")
      }

      if (root.queue.length > 0) {
        var next = root.queue[0]
        root.queue = root.queue.slice(1)
        ytdlp.start(next)
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(310))
    contentHeight: panel.fittedContentHeight(cardColumn.implicitHeight + Style.space(32), Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: urlField.activeFocus
      onCloseRequested: {
        if (root.dropdownOpen) root.dropdownOpen = false
        else root.close()
      }
      onActivateRequested: root.startDownload()
      onTabRequested: function(direction) {
        urlField.forceActiveFocus()
      }
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) {
          root.isAudioMode = !root.isAudioMode
          root.dropdownOpen = false
          return
        }
        if (dy !== 0) {
          if (root.dropdownOpen) {
            var formatsCount = root.currentFormats.length
            if (root.isAudioMode) {
              root.selectedAudioIndex = (root.selectedAudioIndex + dy + formatsCount) % formatsCount
            } else {
              root.selectedVideoIndex = (root.selectedVideoIndex + dy + formatsCount) % formatsCount
            }
          } else {
            if (dy < 0) urlField.forceActiveFocus()
            else root.dropdownOpen = true
          }
        }
      }
      onTextKey: function(t) {
        if (t === "a" || t === "A") { root.isAudioMode = true; root.dropdownOpen = false }
        else if (t === "v" || t === "V") { root.isAudioMode = false; root.dropdownOpen = false }
        else if (t === "c" || t === "C") {
          if (ytdlp.running) ytdlp.cancel()
          else root.recentDownloads = []
        } else if (t === "p" || t === "P") {
          root.pasteFromClipboard()
          urlField.forceActiveFocus()
        } else if (t === "1") {
          if (root.isAudioMode) root.selectedAudioIndex = 0; else root.selectedVideoIndex = 0; root.dropdownOpen = false
        } else if (t === "2") {
          if (root.isAudioMode) root.selectedAudioIndex = 1; else root.selectedVideoIndex = 1; root.dropdownOpen = false
        } else if (t === "3") {
          if (root.isAudioMode) root.selectedAudioIndex = 2; else root.selectedVideoIndex = 2; root.dropdownOpen = false
        } else if (t === "4") {
          if (root.isAudioMode) root.selectedAudioIndex = 3; else root.selectedVideoIndex = 3; root.dropdownOpen = false
        }
      }

      // Main Outer Card Container
      Rectangle {
        id: cardBg
        anchors.fill: parent
        color: "#13161f"
        radius: Style.space(14)
        border.color: "#202534"
        border.width: 1

        Column {
          id: cardColumn
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: Style.space(16)
          spacing: Style.space(11)

          // 1. Header (Icon, Title "Fetch", Subtitle rotating satire)
          RowLayout {
            width: parent.width
            spacing: Style.space(10)

            Text {
              text: "\uf019"
              font.family: Style.font.family
              font.pixelSize: Style.space(18)
              color: "#ffffff"
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(1)

              Text {
                text: "Fetch"
                font.family: Style.font.family
                font.pixelSize: Style.space(16)
                font.bold: true
                color: "#ffffff"
              }

              Text {
                text: root.currentTagline
                font.family: Style.font.family
                font.pixelSize: Style.space(9)
                font.bold: true
                color: "#606b82"

                Behavior on text {
                  SequentialAnimation {
                    NumberAnimation { target: parent; property: "opacity"; to: 0.2; duration: 150 }
                    NumberAnimation { target: parent; property: "opacity"; to: 1.0; duration: 150 }
                  }
                }
              }
            }
          }

          // 2. URL Input with embedded Clipboard icon
          Rectangle {
            width: parent.width
            height: Style.space(36)
            color: "#181c28"
            radius: Style.space(8)
            border.color: urlField.activeFocus ? "#3b445c" : "#242938"
            border.width: 1

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(8)

              // Clipboard icon button (click to paste)
              Text {
                text: "\uf0ea"
                font.family: Style.font.family
                font.pixelSize: Style.space(12)
                color: clipMouse.containsMouse ? "#ffffff" : "#606b82"

                MouseArea {
                  id: clipMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.pasteFromClipboard()
                    urlField.forceActiveFocus()
                  }
                }
              }

              TextField {
                id: urlField
                Layout.fillWidth: true
                background: null
                padding: 0
                font.family: Style.font.family
                font.pixelSize: Style.space(11)
                color: "#ffffff"
                placeholderText: "youtube.com/watch?v=3fK2q9x..."
                placeholderTextColor: "#40495e"
                text: root.inputUrl
                onTextEdited: {
                  root.inputUrl = text
                  if (Downloader.isValidUrl(text)) {
                    root.fetchMetadata(text)
                  }
                }
                onAccepted: {
                  if (root.inputUrl.length > 0) root.startDownload()
                }
                Keys.onDownPressed: function(event) {
                  keyCatcher.forceActiveFocus()
                  event.accepted = true
                }
                Keys.onTabPressed: function(event) {
                  keyCatcher.forceActiveFocus()
                  event.accepted = true
                }
                Keys.onEscapePressed: function(event) {
                  if (text !== "") {
                    text = ""
                    root.inputUrl = ""
                  } else {
                    root.close()
                  }
                  event.accepted = true
                }
              }
            }
          }

          // Video title info (if loading or present)
          Text {
            width: parent.width
            visible: root.metadataLoading || root.videoTitle !== ""
            text: root.metadataLoading ? "Probing stream..." : (root.videoTitle + (root.videoDuration !== "" ? " · " + root.videoDuration : ""))
            color: "#606b82"
            font.family: Style.font.family
            font.pixelSize: Style.space(10)
            font.bold: true
            elide: Text.ElideRight
          }

          // 3. Segmented Tab Switcher: [ AUDIO ] [ VIDEO ]
          Rectangle {
            width: parent.width
            height: Style.space(34)
            color: "#181c28"
            radius: Style.space(8)
            border.color: "#242938"
            border.width: 1

            Row {
              anchors.fill: parent
              anchors.margins: Style.space(3)
              spacing: Style.space(4)

              // Audio Tab
              Rectangle {
                width: (parent.width - Style.space(4)) / 2
                height: parent.height
                radius: Style.space(6)
                color: root.isAudioMode ? "#252b3b" : "transparent"

                Text {
                  anchors.centerIn: parent
                  text: "AUDIO"
                  font.family: Style.font.family
                  font.pixelSize: Style.space(11)
                  font.bold: true
                  color: root.isAudioMode ? "#ffffff" : "#606b82"
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.isAudioMode = true
                    root.dropdownOpen = false
                    keyCatcher.forceActiveFocus()
                  }
                }
              }

              // Video Tab
              Rectangle {
                width: (parent.width - Style.space(4)) / 2
                height: parent.height
                radius: Style.space(6)
                color: !root.isAudioMode ? "#252b3b" : "transparent"

                Text {
                  anchors.centerIn: parent
                  text: "VIDEO"
                  font.family: Style.font.family
                  font.pixelSize: Style.space(11)
                  font.bold: true
                  color: !root.isAudioMode ? "#ffffff" : "#606b82"
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.isAudioMode = false
                    root.dropdownOpen = false
                    keyCatcher.forceActiveFocus()
                  }
                }
              }
            }
          }

          // 4. Quality Dropdown Trigger
          Rectangle {
            width: parent.width
            height: Style.space(34)
            color: "#181c28"
            radius: Style.space(8)
            border.color: root.dropdownOpen ? "#3b445c" : "#242938"
            border.width: 1

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(8)

              Text {
                text: "\uf1de"
                font.family: Style.font.family
                font.pixelSize: Style.space(12)
                color: "#606b82"
              }

              Text {
                Layout.fillWidth: true
                text: root.currentFormat.display
                font.family: Style.font.family
                font.pixelSize: Style.space(11)
                font.bold: true
                color: "#ffffff"
              }

              Text {
                text: root.dropdownOpen ? "\uf077" : "\uf078"
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
                color: "#606b82"
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.dropdownOpen = !root.dropdownOpen
                keyCatcher.forceActiveFocus()
              }
            }
          }

          // 4b. Dropdown Options List (collapsible)
          Column {
            width: parent.width
            visible: root.dropdownOpen
            spacing: Style.space(3)

            Repeater {
              model: root.currentFormats

              Rectangle {
                required property var modelData
                required property int index
                width: cardColumn.width
                height: Style.space(30)
                radius: Style.space(6)
                color: (root.isAudioMode ? root.selectedAudioIndex : root.selectedVideoIndex) === index ? "#252b3b" : "#181c28"
                border.color: (root.isAudioMode ? root.selectedAudioIndex : root.selectedVideoIndex) === index ? "#3b445c" : "#202534"
                border.width: 1

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)

                  Text {
                    text: modelData.display
                    font.family: Style.font.family
                    font.pixelSize: Style.space(11)
                    font.bold: true
                    color: "#ffffff"
                    Layout.fillWidth: true
                  }

                  Text {
                    text: modelData.sublabel
                    font.family: Style.font.family
                    font.pixelSize: Style.space(9)
                    color: "#606b82"
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (root.isAudioMode) root.selectedAudioIndex = index
                    else root.selectedVideoIndex = index
                    root.dropdownOpen = false
                    keyCatcher.forceActiveFocus()
                  }
                }
              }
            }
          }

          // 5. Download Action Button
          Rectangle {
            width: parent.width
            height: Style.space(32)
            radius: Style.space(8)
            color: dlMouse.containsMouse ? "#2f364a" : "#252b3b"
            border.color: "#343d52"
            border.width: 1

            RowLayout {
              anchors.centerIn: parent
              spacing: Style.space(6)

              Text {
                text: "\uf019"
                font.family: Style.font.family
                font.pixelSize: Style.space(11)
                color: "#ffffff"
              }

              Text {
                text: "Fetch " + (root.isAudioMode ? "Audio" : "Video")
                font.family: Style.font.family
                font.pixelSize: Style.space(11)
                font.bold: true
                color: "#ffffff"
              }
            }

            MouseArea {
              id: dlMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.startDownload()
            }
          }

          // 6. STATUS Section (2x2 Grid + Progress Bar)
          Column {
            width: parent.width
            spacing: Style.space(6)

            Text {
              text: "STATUS"
              font.family: Style.font.family
              font.pixelSize: Style.space(9)
              font.bold: true
              color: "#505a72"
            }

            // 2x2 Grid
            Column {
              width: parent.width
              spacing: Style.space(6)

              // Row 1: State & Speed
              Row {
                width: parent.width

                Column {
                  width: parent.width / 2
                  spacing: Style.space(1)
                  Text {
                    text: "State"
                    font.family: Style.font.family
                    font.pixelSize: Style.space(10)
                    color: "#606b82"
                  }
                  Text {
                    text: ytdlp.running ? ytdlp.stateText : (root.inputUrl !== "" ? "Ready" : "Idle")
                    font.family: Style.font.family
                    font.pixelSize: Style.space(13)
                    font.bold: true
                    color: "#ffffff"
                  }
                }

                Column {
                  width: parent.width / 2
                  spacing: Style.space(1)
                  Text {
                    text: "Speed"
                    font.family: Style.font.family
                    font.pixelSize: Style.space(10)
                    color: "#606b82"
                  }
                  Text {
                    text: ytdlp.running && ytdlp.speedText !== "" ? ytdlp.speedText : "—"
                    font.family: Style.font.family
                    font.pixelSize: Style.space(13)
                    font.bold: true
                    color: "#ffffff"
                  }
                }
              }

              // Row 2: Size & ETA
              Row {
                width: parent.width

                Column {
                  width: parent.width / 2
                  spacing: Style.space(1)
                  Text {
                    text: "Size"
                    font.family: Style.font.family
                    font.pixelSize: Style.space(10)
                    color: "#606b82"
                  }
                  Text {
                    text: ytdlp.running && ytdlp.sizeText !== "" ? ytdlp.sizeText : "—"
                    font.family: Style.font.family
                    font.pixelSize: Style.space(13)
                    font.bold: true
                    color: "#ffffff"
                  }
                }

                Column {
                  width: parent.width / 2
                  spacing: Style.space(1)
                  Text {
                    text: "ETA"
                    font.family: Style.font.family
                    font.pixelSize: Style.space(10)
                    color: "#606b82"
                  }
                  Text {
                    text: ytdlp.running && ytdlp.etaText !== "" ? ytdlp.etaText : "—"
                    font.family: Style.font.family
                    font.pixelSize: Style.space(13)
                    font.bold: true
                    color: "#ffffff"
                  }
                }
              }
            }

            // Horizontal Progress Bar
            Rectangle {
              width: parent.width
              height: Style.space(4)
              radius: Style.space(2)
              color: "#242938"

              Rectangle {
                height: parent.height
                radius: parent.radius
                color: "#ffffff"
                width: Math.max(0, Math.min(parent.width, parent.width * (ytdlp.progress / 100)))

                Behavior on width {
                  NumberAnimation { duration: 100 }
                }
              }
            }
          }

          // 7. RECENT Section (with Clear button and Auto-Clear on close)
          Column {
            width: parent.width
            visible: root.recentDownloads.length > 0 || root.queue.length > 0
            spacing: Style.space(6)

            RowLayout {
              width: parent.width

              Text {
                text: "RECENT"
                font.family: Style.font.family
                font.pixelSize: Style.space(9)
                font.bold: true
                color: "#505a72"
                Layout.fillWidth: true
              }

              Text {
                text: "Clear"
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
                color: clearMouse.containsMouse ? "#ffffff" : "#606b82"

                MouseArea {
                  id: clearMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.recentDownloads = []
                    root.queue = []
                  }
                }
              }
            }

            // Queue items
            Repeater {
              model: root.queue

              Rectangle {
                required property var modelData
                required property int index
                width: cardColumn.width
                height: Style.space(34)
                color: "#181c28"
                radius: Style.space(8)
                border.color: "#242938"
                border.width: 1

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(8)

                  Text {
                    text: "\uf110"
                    font.family: Style.font.family
                    font.pixelSize: Style.space(12)
                    color: "#606b82"
                  }

                  Text {
                    text: modelData.title || modelData.url
                    font.family: Style.font.family
                    font.pixelSize: Style.space(11)
                    color: "#ffffff"
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                  }

                  Text {
                    text: "Queued"
                    font.family: Style.font.family
                    font.pixelSize: Style.space(10)
                    color: "#606b82"
                  }
                }
              }
            }

            // Recent Download Item Card
            Repeater {
              model: root.recentDownloads

              Rectangle {
                required property var modelData
                width: cardColumn.width
                height: Style.space(34)
                color: recentMouse.containsMouse ? "#1f2433" : "#181c28"
                radius: Style.space(8)
                border.color: "#242938"
                border.width: 1

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(8)

                  Text {
                    text: modelData.isAudio ? "\uf025" : "\uf03d"
                    font.family: Style.font.family
                    font.pixelSize: Style.space(12)
                    color: "#606b82"
                  }

                  Text {
                    text: modelData.title
                    font.family: Style.font.family
                    font.pixelSize: Style.space(11)
                    color: "#ffffff"
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                  }

                  Text {
                    text: "\uf00c"
                    font.family: Style.font.family
                    font.pixelSize: Style.space(11)
                    color: "#4ade80"
                  }
                }

                MouseArea {
                  id: recentMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: xdgProc.openTarget(modelData.filePath)
                }
              }
            }
          }
        }
      }
    }
  }
}
