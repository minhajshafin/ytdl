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
  onInputUrlChanged: {
    if (inputUrl.trim() === "") {
      clearMetadata()
    }
  }
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

  readonly property int maxFastMetaBytes: 16384 // 16 KB strict byte ceiling
  readonly property int maxMetaBytes: 8192      // 8 KB strict byte ceiling
  readonly property int maxClipBytes: 2048      // 2 KB max for clipboard URL
  property string fastMetaBuffer: ""
  property int fastMetaBytes: 0
  property string metaBuffer: ""
  property int metaBytes: 0
  property string clipBuffer: ""
  property int clipBytes: 0

  Timer {
    id: fastMetaDeadlineTimer
    interval: 3500 // 3.5s total deadline
    repeat: false
    onTriggered: {
      if (fastMetaProc.running) {
        fastMetaProc.running = false
      }
    }
  }

  Timer {
    id: metaDeadlineTimer
    interval: 6000 // 6.0s total deadline
    repeat: false
    onTriggered: {
      if (metaProc.running) {
        metaProc.running = false
        root.metadataLoading = false
      }
    }
  }

  Timer {
    id: clipDeadlineTimer
    interval: 1500 // 1.5s total deadline for clipboard access
    repeat: false
    onTriggered: {
      if (clipboardProc.running) {
        clipboardProc.running = false
        root.clipBuffer = ""
        root.clipBytes = 0
      }
    }
  }

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
    fastMetaDeadlineTimer.stop()
    metaDeadlineTimer.stop()
    clipDeadlineTimer.stop()
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
      root.clipBuffer = ""
      root.clipBytes = 0
      clipDeadlineTimer.restart()
      clipboardProc.running = true
    }
  }

  function pasteFromClipboard() {
    checkClipboard()
  }

  function clearMetadata() {
    fastMetaDeadlineTimer.stop()
    metaDeadlineTimer.stop()
    if (metaProc.running) metaProc.running = false
    if (fastMetaProc.running) fastMetaProc.running = false
    root.fastMetaBuffer = ""
    root.fastMetaBytes = 0
    root.metaBuffer = ""
    root.metaBytes = 0
    root.metadataLoading = false
    root.videoTitle = ""
    root.videoUploader = ""
    root.videoDuration = ""
    root.videoThumbnail = ""
  }

  function fetchMetadata(url) {
    if (!url || !Downloader.isValidUrl(url)) {
      clearMetadata()
      return
    }
    clearMetadata()
    root.metadataLoading = true

    var ytId = Downloader.extractYoutubeId(url)
    if (ytId) {
      // 1. Instant 0ms thumbnail display
      root.videoThumbnail = "https://i.ytimg.com/vi/" + ytId + "/mqdefault.jpg"
      root.videoTitle = "Loading preview…"
      root.videoUploader = ""
      root.videoDuration = ""

      // 2. Fast 150ms oEmbed query via curl with 16KB max filesize and 3.5s deadline
      root.fastMetaBuffer = ""
      root.fastMetaBytes = 0
      fastMetaDeadlineTimer.restart()
      fastMetaProc.command = ["curl", "-q", "-s", "--max-time", "3", "--max-filesize", "16384", "--", "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=" + ytId + "&format=json"]
      fastMetaProc.running = true
    } else {
      root.videoTitle = ""
      root.videoUploader = ""
      root.videoDuration = ""
      root.videoThumbnail = ""
    }

    // 3. Fast yt-dlp metadata extraction with socket timeout and strict 6s deadline
    root.metaBuffer = ""
    root.metaBytes = 0
    metaDeadlineTimer.restart()
    metaProc.command = [
      "yt-dlp",
      "--ignore-config",
      "--no-plugin-dirs",
      "--no-playlist",
      "--skip-download",
      "--socket-timeout", "5",
      "--print", "%(title)s\t%(uploader)s\t%(duration)s\t%(thumbnail)s",
      "--",
      url
    ]
    metaProc.running = true
  }

  function startDownload() {
    var url = Downloader.cleanUrl(root.inputUrl)
    if (!url) return

    var fmt = root.currentFormat
    var homeDir = Quickshell.env("HOME") || "/tmp"
    var dest = fmt.isAudio ? (homeDir + "/Music") : (homeDir + "/Videos")
    var rawTitle = root.videoTitle !== "" && root.videoTitle !== "Loading preview…" ? root.videoTitle : "YouTube Media"
    var title = String(rawTitle).trim()
    if (title.length > 200) title = title.substring(0, 200)

    var task = {
      url: url,
      format: fmt,
      title: title,
      destination: dest
    }

    if (ytdlp.running) {
      if (root.queue.length >= 10) {
        notifyProc.send("Queue Full", "Maximum 10 queued downloads reached", "dialog-warning")
        return
      }
      var q = root.queue.slice()
      q.push(task)
      root.queue = q
      notifyProc.send("Queued", title + " (" + fmt.label + ")", "media-playback-start")
    } else {
      ytdlp.start(task)
    }

    root.inputUrl = ""
    root.clearMetadata()
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
    stdout: SplitParser {
      onRead: function(chunk) {
        var str = String(chunk || "")
        root.clipBytes += str.length
        if (root.clipBytes > root.maxClipBytes) {
          clipboardProc.running = false
          root.clipBuffer = ""
          return
        }
        root.clipBuffer += str
      }
    }
    onExited: function(exitCode) {
      clipDeadlineTimer.stop()
      if (exitCode === 0 && root.clipBuffer !== "" && root.clipBytes <= root.maxClipBytes) {
        var raw = root.clipBuffer.trim()
        if (raw.length <= root.maxClipBytes && Downloader.isValidUrl(raw)) {
          if (root.inputUrl !== raw) {
            root.inputUrl = raw
            root.fetchMetadata(raw)
          }
        }
      }
      root.clipBuffer = ""
      root.clipBytes = 0
    }
  }

  Process {
    id: fastMetaProc
    stdout: SplitParser {
      onRead: function(chunk) {
        var str = String(chunk || "")
        root.fastMetaBytes += str.length
        if (root.fastMetaBytes > root.maxFastMetaBytes) {
          // Strictly capped: cancel producer immediately
          fastMetaProc.running = false
          root.fastMetaBuffer = ""
          return
        }
        root.fastMetaBuffer += str
      }
    }
    onExited: function(exitCode) {
      fastMetaDeadlineTimer.stop()
      if (exitCode === 0 && root.fastMetaBuffer !== "" && root.fastMetaBytes <= root.maxFastMetaBytes) {
        if (root.inputUrl.trim() !== "" && Downloader.isValidUrl(root.inputUrl)) {
          try {
            var data = JSON.parse(root.fastMetaBuffer.trim())
            if (data && data.title) {
              var t = String(data.title || "").trim()
              root.videoTitle = t.length > 200 ? t.substring(0, 200) : t

              var u = String(data.author_name || "").trim()
              root.videoUploader = u.length > 100 ? u.substring(0, 100) : u

              var th = String(data.thumbnail_url || "").trim()
              if (th.length <= 500 && Downloader.isValidThumbnailUrl(th)) {
                root.videoThumbnail = th
              }
            }
          } catch (e) {}
        }
      }
      root.fastMetaBuffer = ""
      root.fastMetaBytes = 0
    }
  }

  Process {
    id: metaProc
    stdout: SplitParser {
      onRead: function(chunk) {
        var str = String(chunk || "")
        root.metaBytes += str.length
        if (root.metaBytes > root.maxMetaBytes) {
          // Strictly capped: cancel producer immediately
          metaProc.running = false
          root.metaBuffer = ""
          root.metadataLoading = false
          return
        }
        root.metaBuffer += str
      }
    }
    onExited: function(exitCode) {
      metaDeadlineTimer.stop()
      root.metadataLoading = false
      if (exitCode === 0 && root.metaBuffer !== "" && root.metaBytes <= root.maxMetaBytes) {
        if (root.inputUrl.trim() !== "" && Downloader.isValidUrl(root.inputUrl)) {
          var raw = root.metaBuffer.trim()
          if (raw !== "") {
            var parts = raw.split("\t")
            if (parts.length >= 1 && parts[0]) {
              var t = String(parts[0]).trim()
              root.videoTitle = t.length > 200 ? t.substring(0, 200) : t
            }
            if (parts.length >= 2 && parts[1]) {
              var u = String(parts[1]).trim()
              root.videoUploader = u.length > 100 ? u.substring(0, 100) : u
            }
            if (parts.length >= 3 && parts[2]) {
              var d = String(parts[2]).trim()
              if (d.length > 20) d = d.substring(0, 20)
              root.videoDuration = Downloader.formatDuration(d)
            }
            if (parts.length >= 4 && parts[3] && !root.videoThumbnail) {
              var th = String(parts[3]).trim()
              if (th.length <= 500 && Downloader.isValidThumbnailUrl(th)) {
                root.videoThumbnail = th
              }
            }
          }
        }
      }
      root.metaBuffer = ""
      root.metaBytes = 0
    }
  }

  Process {
    id: notifyProc
    function send(title, body, icon) {
      var t = String(title || "YouTube Downloader").trim()
      if (t.length > 100) t = t.substring(0, 100)
      var b = String(body || "").trim()
      if (b.length > 500) b = b.substring(0, 500)
      var ic = String(icon || "video-x-generic").trim()
      if (!ic.match(/^[a-z0-9_-]+$/i)) ic = "video-x-generic"
      command = ["notify-send", "-a", "YouTube Downloader", "-i", ic, "--", t, b]
      running = true
    }
  }

  Process {
    id: xdgProc
    function openTarget(path) {
      if (!path || typeof path !== "string") return
      var p = path.trim()
      // Enforce absolute path starting with /, no control characters, no newlines
      if (p.length > 1 && p.charAt(0) === "/" && p.indexOf("\0") === -1 && p.indexOf("\n") === -1) {
        command = ["xdg-open", p]
        running = true
      }
    }
  }

  YtDlpProcess {
    id: ytdlp
    onFinished: function(task, success, filePath, errorMsg) {
      if (success) {
        var rec = root.recentDownloads.slice()
        var safeTitle = task && task.title ? String(task.title).trim() : "Media"
        if (safeTitle.length > 200) safeTitle = safeTitle.substring(0, 200)
        rec.unshift({
          title: safeTitle,
          filePath: filePath,
          isAudio: task.format.isAudio,
          format: task.format.label
        })
        if (rec.length > 3) rec = rec.slice(0, 3)
        root.recentDownloads = rec

        notifyProc.send("Download Complete", safeTitle + "\nSaved to " + task.destination, task.format.isAudio ? "audio-x-generic" : "video-x-generic")
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
          border.color: (root.inputUrl.trim() !== "" && !Downloader.isValidUrl(root.inputUrl))
            ? Color.urgent
            : (urlField.activeFocus ? root.accentColor : root.insetBorder)
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
                if (text.trim() === "") {
                  root.clearMetadata()
                } else if (Downloader.isValidUrl(text)) {
                  root.fetchMetadata(text)
                } else {
                  root.clearMetadata()
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
                  root.clearMetadata()
                } else {
                  root.close()
                }
                event.accepted = true
              }
            }
          }
        }

        // Invalid URL notice
        Text {
          width: parent.width
          visible: root.inputUrl.trim() !== "" && !Downloader.isValidUrl(root.inputUrl)
          textFormat: Text.PlainText
          text: root.inputUrl.trim().indexOf("http://") === 0
            ? "Insecure link: requires https:// (e.g. https://youtube.com/...)"
            : "Please enter a valid https:// media link (YouTube, SoundCloud, Vimeo, etc.)"
          font.family: Style.font.family
          font.pixelSize: Style.space(11)
          color: Color.urgent
          wrapMode: Text.WordWrap
          leftPadding: Style.space(4)
        }

        // 3. Link Preview Card (Under URL Bar: 16:9 thumbnail + title + channel/duration)
        Rectangle {
          width: parent.width
          height: previewRow.implicitHeight + Style.space(12)
          visible: root.inputUrl.trim() !== "" && Downloader.isValidUrl(root.inputUrl) && (root.metadataLoading || root.videoTitle !== "")
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
                textFormat: Text.PlainText
                text: root.metadataLoading ? "Fetching video info..." : root.videoTitle
                color: root.textMain
                font.family: Style.font.family
                font.pixelSize: Style.space(11)
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
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
                  textFormat: Text.PlainText
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
                  textFormat: Text.PlainText
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
                  textFormat: Text.PlainText
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
                  textFormat: Text.PlainText
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
                  textFormat: Text.PlainText
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
                  textFormat: Text.PlainText
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
