import QtQuick
import QtQuick.Controls
import QtQuick.Effects
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
  property string videoUploader: ""
  property string videoDuration: ""
  property string videoThumbnail: ""
  property bool metadataLoading: false

  property var queue: []
  property var recentDownloads: []
  readonly property bool isDownloading: ytdlp.running

  // Dynamic Theme Colors
  readonly property color insetBg: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
  readonly property color insetBorder: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
  readonly property color activePillBg: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)
  readonly property color textMain: Color.popups.text
  readonly property color textMuted: Color.muted
  readonly property color accentColor: Color.accent

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

  Component.onDestruction: {
    if (ytdlp.running) ytdlp.cancel()
    if (metaProc.running) metaProc.running = false
    if (fastMetaProc.running) fastMetaProc.running = false
    if (clipboardProc.running) clipboardProc.running = false
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
    if (fastMetaProc.running) fastMetaProc.running = false
    root.metadataLoading = true

    var ytId = Downloader.extractYoutubeId(url)
    if (ytId) {
      // 1. Instant 0ms thumbnail display
      root.videoThumbnail = "https://i.ytimg.com/vi/" + ytId + "/mqdefault.jpg"
      root.videoTitle = "Loading preview…"
      root.videoUploader = ""
      root.videoDuration = ""

      // 2. Fast 150ms oEmbed query via curl
      fastMetaProc.command = ["curl", "-s", "--max-time", "3", "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=" + ytId + "&format=json"]
      fastMetaProc.running = true
    } else {
      root.videoTitle = ""
      root.videoUploader = ""
      root.videoDuration = ""
      root.videoThumbnail = ""
    }

    // 3. Fast yt-dlp metadata extraction (tab-separated --print instead of heavy 50KB JSON)
    metaProc.command = ["yt-dlp", "--print", "%(title)s\t%(uploader)s\t%(duration)s\t%(thumbnail)s", "--no-playlist", "--skip-download", url]
    metaProc.running = true
  }

  function startDownload() {
    var url = Downloader.cleanUrl(root.inputUrl)
    if (!url) return

    var fmt = root.currentFormat
    var homeDir = Quickshell.env("HOME") || "/home/billy"
    var dest = fmt.isAudio ? (homeDir + "/Music") : (homeDir + "/Videos")
    var title = root.videoTitle !== "" && root.videoTitle !== "Loading preview…" ? root.videoTitle : "YouTube Media"

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
    root.videoUploader = ""
    root.videoDuration = ""
    root.videoThumbnail = ""
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
    id: fastMetaProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "").trim())
          if (data && data.title) {
            root.videoTitle = data.title
            root.videoUploader = data.author_name || ""
            if (data.thumbnail_url) root.videoThumbnail = data.thumbnail_url
          }
        } catch (e) {}
      }
    }
  }

  Process {
    id: metaProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.metadataLoading = false
        var raw = String(text || "").trim()
        if (raw !== "") {
          var parts = raw.split("\t")
          if (parts.length >= 1 && parts[0]) root.videoTitle = parts[0]
          if (parts.length >= 2 && parts[1]) root.videoUploader = parts[1]
          if (parts.length >= 3 && parts[2]) root.videoDuration = Downloader.formatDuration(parts[2])
          if (parts.length >= 4 && parts[3] && !root.videoThumbnail) root.videoThumbnail = parts[3]
        }
      }
    }
    onExited: function(exitCode) {
      root.metadataLoading = false
    }
  }

  Process {
    id: notifyProc
    function send(title, body, icon) {
      command = ["notify-send", "-a", "YouTube Downloader", "-i", icon || "video-x-generic", title, body]
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
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(cardColumn.implicitHeight, Style.space(620))

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

      Column {
        id: cardColumn
        width: parent.width
        spacing: Style.space(12)

        // 1. Header (Hero: Icon · Title & Subtitle) modeled on the Bluetooth panel
        Item {
          id: heroHeader
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Item {
            id: heroIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.font.display
            height: Style.font.display
            implicitWidth: width
            implicitHeight: height

            Image {
              id: headerIconImg
              anchors.fill: parent
              source: Qt.resolvedUrl("assets/app.svg")
              sourceSize.width: Style.space(48)
              sourceSize.height: Style.space(48)
              fillMode: Image.PreserveAspectFit
              visible: false
              layer.enabled: true
            }

            MultiEffect {
              anchors.fill: headerIconImg
              source: headerIconImg
              colorization: 1.0
              colorizationColor: root.textMain
            }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "YouTube Downloader"
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              color: root.textMain
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              id: heroTagline
              text: root.currentTagline.toUpperCase()
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              color: root.textMuted
              elide: Text.ElideRight
              width: parent.width

              Behavior on text {
                SequentialAnimation {
                  NumberAnimation { target: heroTagline; property: "opacity"; to: 0.2; duration: 150 }
                  NumberAnimation { target: heroTagline; property: "opacity"; to: 1.0; duration: 150 }
                }
              }
            }
          }
        }

        // Straight line under the title section like the bluetooth shell
        PanelSeparator {
          foreground: root.textMain
        }

        // 2. URL Input Bar with embedded Clipboard Icon
        Rectangle {
          width: parent.width
          height: Style.space(38)
          color: root.insetBg
          radius: Style.space(10)
          border.color: urlField.activeFocus ? root.accentColor : root.insetBorder
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)

            // Paste Icon (Click to paste)
            Text {
              text: "\u{F0192}"
              font.family: Style.font.family
              font.pixelSize: Style.space(14)
              color: clipMouse.containsMouse ? root.textMain : root.textMuted

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
              font.pixelSize: Style.space(12)
              color: root.textMain
              placeholderText: "youtube.com/watch?v=3fK2q9x..."
              placeholderTextColor: Qt.darker(root.textMuted, 1.2)
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

        // 3. Link Preview Card (Under URL Bar: 16:9 thumbnail + title + channel/duration)
        Rectangle {
          width: parent.width
          height: previewRow.implicitHeight + Style.space(12)
          visible: root.metadataLoading || root.videoTitle !== ""
          color: root.insetBg
          radius: Style.space(8)
          border.color: root.insetBorder
          border.width: 1

          RowLayout {
            id: previewRow
            anchors.fill: parent
            anchors.margins: Style.space(6)
            spacing: Style.space(10)

            // 16:9 Mini Thumbnail
            Rectangle {
              width: Style.space(56)
              height: Style.space(32)
              radius: Style.space(4)
              color: Qt.rgba(0, 0, 0, 0.3)
              clip: true

              Image {
                visible: root.videoThumbnail !== ""
                anchors.fill: parent
                source: root.videoThumbnail
                fillMode: Image.PreserveAspectCrop
              }

              Text {
                visible: root.videoThumbnail === ""
                anchors.centerIn: parent
                text: root.metadataLoading ? "\uf110" : "\uf16a"
                font.family: Style.font.family
                font.pixelSize: Style.space(14)
                color: root.textMuted
              }
            }

            // Metadata Text
            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(1)

              Text {
                Layout.fillWidth: true
                text: root.metadataLoading ? "Fetching video info..." : root.videoTitle
                color: root.textMain
                font.family: Style.font.family
                font.pixelSize: Style.space(11)
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                Layout.fillWidth: true
                visible: !root.metadataLoading && (root.videoUploader !== "" || root.videoDuration !== "")
                text: (root.videoUploader !== "" ? root.videoUploader : "") + (root.videoDuration !== "" ? " · " + root.videoDuration : "")
                color: root.textMuted
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
                elide: Text.ElideRight
              }
            }
          }
        }

        // 4. Segmented Tab Switcher: [ AUDIO ] [ VIDEO ]
        Rectangle {
          width: parent.width
          height: Style.space(34)
          color: root.insetBg
          radius: Style.space(10)
          border.color: root.insetBorder
          border.width: 1

          Row {
            anchors.fill: parent
            anchors.margins: Style.space(3)
            spacing: Style.space(4)

            // Audio Tab
            Rectangle {
              width: (parent.width - Style.space(4)) / 2
              height: parent.height
              radius: Style.space(7)
              color: root.isAudioMode ? root.activePillBg : "transparent"

              Text {
                anchors.centerIn: parent
                text: "AUDIO"
                font.family: Style.font.family
                font.pixelSize: Style.space(11)
                font.bold: true
                color: root.isAudioMode ? root.textMain : root.textMuted
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
              radius: Style.space(7)
              color: !root.isAudioMode ? root.activePillBg : "transparent"

              Text {
                anchors.centerIn: parent
                text: "VIDEO"
                font.family: Style.font.family
                font.pixelSize: Style.space(11)
                font.bold: true
                color: !root.isAudioMode ? root.textMain : root.textMuted
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

        // 5. Quality Dropdown Trigger
        Rectangle {
          width: parent.width
          height: Style.space(36)
          color: root.insetBg
          radius: Style.space(10)
          border.color: root.dropdownOpen ? root.accentColor : root.insetBorder
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(8)

            Text {
              text: "\uf1de"
              font.family: Style.font.family
              font.pixelSize: Style.space(13)
              color: root.textMuted
            }

            Text {
              Layout.fillWidth: true
              text: root.currentFormat.display
              font.family: Style.font.family
              font.pixelSize: Style.space(12)
              color: root.textMain
            }

            Text {
              text: root.dropdownOpen ? "\uf077" : "\uf078"
              font.family: Style.font.family
              font.pixelSize: Style.space(13)
              color: root.textMuted
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

        // 5b. Dropdown Options List
        Column {
          width: parent.width
          visible: root.dropdownOpen
          spacing: Style.space(4)

          Repeater {
            model: root.currentFormats

            Rectangle {
              required property var modelData
              required property int index
              width: cardColumn.width
              height: Style.space(32)
              radius: Style.space(7)
              color: (root.isAudioMode ? root.selectedAudioIndex : root.selectedVideoIndex) === index
                ? root.activePillBg
                : (optMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : root.insetBg)
              border.color: (root.isAudioMode ? root.selectedAudioIndex : root.selectedVideoIndex) === index
                ? root.accentColor
                : root.insetBorder
              border.width: 1

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)

                Text {
                  text: modelData.display
                  font.family: Style.font.family
                  font.pixelSize: Style.space(12)
                  color: root.textMain
                  Layout.fillWidth: true
                }

                Text {
                  text: modelData.sublabel
                  font.family: Style.font.family
                  font.pixelSize: Style.space(10)
                  color: root.textMuted
                }
              }

              MouseArea {
                id: optMouse
                anchors.fill: parent
                hoverEnabled: true
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

        // 6. Download Action Button (matches ytdl.html DOWNLOAD row)
        Rectangle {
          width: parent.width
          height: Style.space(38)
          radius: Style.space(10)
          color: dlMouse.containsMouse ? Qt.lighter(root.activePillBg, 1.2) : root.activePillBg
          border.color: dlMouse.containsMouse ? root.accentColor : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.18)
          border.width: 1

          RowLayout {
            anchors.centerIn: parent
            spacing: Style.space(8)

            Text {
              text: "\uf019"
              font.family: Style.font.family
              font.pixelSize: Style.space(14)
              color: root.textMain
            }

            Text {
              text: "DOWNLOAD"
              font.family: Style.font.family
              font.pixelSize: Style.space(12)
              font.bold: true
              color: root.textMain
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

        // 7. STATUS Section (Visible ONLY when downloading)
        Column {
          width: parent.width
          visible: ytdlp.running
          spacing: Style.space(8)

          Text {
            text: "STATUS"
            font.family: Style.font.family
            font.pixelSize: Style.space(10)
            font.bold: true
            color: root.textMuted
          }

          // 2x2 Grid (State, Speed, Size, ETA)
          Column {
            width: parent.width
            spacing: Style.space(10)

            // Row 1: State & Speed
            Row {
              width: parent.width

              Column {
                width: parent.width / 2
                spacing: Style.space(2)
                Text {
                  text: "State"
                  font.family: Style.font.family
                  font.pixelSize: Style.space(10)
                  color: root.textMuted
                }
                Text {
                  text: ytdlp.stateText
                  font.family: Style.font.family
                  font.pixelSize: Style.space(13)
                  color: root.textMain
                }
              }

              Column {
                width: parent.width / 2
                spacing: Style.space(2)
                Text {
                  text: "Speed"
                  font.family: Style.font.family
                  font.pixelSize: Style.space(10)
                  color: root.textMuted
                }
                Text {
                  text: ytdlp.speedText !== "" ? ytdlp.speedText : "—"
                  font.family: Style.font.family
                  font.pixelSize: Style.space(13)
                  color: root.textMain
                }
              }
            }

            // Row 2: Size & ETA
            Row {
              width: parent.width

              Column {
                width: parent.width / 2
                spacing: Style.space(2)
                Text {
                  text: "Size"
                  font.family: Style.font.family
                  font.pixelSize: Style.space(10)
                  color: root.textMuted
                }
                Text {
                  text: ytdlp.sizeText !== "" ? ytdlp.sizeText : "—"
                  font.family: Style.font.family
                  font.pixelSize: Style.space(13)
                  color: root.textMain
                }
              }

              Column {
                width: parent.width / 2
                spacing: Style.space(2)
                Text {
                  text: "ETA"
                  font.family: Style.font.family
                  font.pixelSize: Style.space(10)
                  color: root.textMuted
                }
                Text {
                  text: ytdlp.etaText !== "" ? ytdlp.etaText : "—"
                  font.family: Style.font.family
                  font.pixelSize: Style.space(13)
                  color: root.textMain
                }
              }
            }
          }

          // Slim Horizontal Progress Bar
          Rectangle {
            width: parent.width
            height: Style.space(4)
            radius: Style.space(2)
            color: root.insetBorder

            Rectangle {
              height: parent.height
              radius: parent.radius
              color: root.accentColor
              width: Math.max(0, Math.min(parent.width, parent.width * (ytdlp.progress / 100)))

              Behavior on width {
                NumberAnimation { duration: 100 }
              }
            }
          }
        }

        // 8. RECENT Section (Visible when completed items exist in this session)
        Column {
          width: parent.width
          visible: root.recentDownloads.length > 0 || root.queue.length > 0
          spacing: Style.space(8)

          RowLayout {
            width: parent.width

            Text {
              text: "RECENT"
              font.family: Style.font.family
              font.pixelSize: Style.space(10)
              font.bold: true
              color: root.textMuted
              Layout.fillWidth: true
            }

            Text {
              text: "Clear"
              font.family: Style.font.family
              font.pixelSize: Style.space(10)
              color: clearMouse.containsMouse ? root.textMain : root.textMuted

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

          // Queue Items
          Repeater {
            model: root.queue

            Rectangle {
              required property var modelData
              required property int index
              width: cardColumn.width
              height: Style.space(34)
              color: root.insetBg
              radius: Style.space(9)
              border.color: root.insetBorder
              border.width: 1

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(8)

                Text {
                  text: "\uf110"
                  font.family: Style.font.family
                  font.pixelSize: Style.space(13)
                  color: root.textMuted
                }

                Text {
                  text: modelData.title || modelData.url
                  font.family: Style.font.family
                  font.pixelSize: Style.space(12)
                  color: root.textMain
                  Layout.fillWidth: true
                  elide: Text.ElideRight
                }

                Text {
                  text: "Queued"
                  font.family: Style.font.family
                  font.pixelSize: Style.space(10)
                  color: root.textMuted
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
              color: recentMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : root.insetBg
              radius: Style.space(9)
              border.color: root.insetBorder
              border.width: 1

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(8)

                Text {
                  text: modelData.isAudio ? "\uf025" : "\uf03d"
                  font.family: Style.font.family
                  font.pixelSize: Style.space(13)
                  color: root.textMuted
                }

                Text {
                  text: modelData.title
                  font.family: Style.font.family
                  font.pixelSize: Style.space(12)
                  color: root.textMain
                  Layout.fillWidth: true
                  elide: Text.ElideRight
                }

                Text {
                  text: "\uf00c"
                  font.family: Style.font.family
                  font.pixelSize: Style.space(13)
                  color: root.accentColor
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
