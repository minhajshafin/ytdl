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
  ipcTarget: "billy.ytdl"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  property string inputUrl: ""
  property int selectedFormatIndex: 0
  property var formats: Downloader.FORMATS

  property string videoTitle: ""
  property string videoUploader: ""
  property string videoDuration: ""
  property string videoThumbnail: ""
  property bool metadataLoading: false

  property var queue: []
  property var recentDownloads: []
  readonly property bool isDownloading: ytdlp.running

  function open() {
    root.controller.show()
    checkClipboard()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (opened) close()
    else open()
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
    root.videoUploader = ""
    root.videoDuration = ""
    root.videoThumbnail = ""
    metaProc.command = ["yt-dlp", "--dump-json", "--no-playlist", "--skip-download", url]
    metaProc.running = true
  }

  function startDownload() {
    var url = Downloader.cleanUrl(root.inputUrl)
    if (!url) return

    var fmt = root.formats[root.selectedFormatIndex] || root.formats[0]
    var homeDir = Quickshell.env("HOME") || "/home/billy"
    var dest = fmt.isAudio ? (homeDir + "/Music") : (homeDir + "/Videos")
    var title = root.videoTitle !== "" ? root.videoTitle : "YouTube Media"

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
      notifyProc.send("Queued Download", title + " (" + fmt.label + ")", "media-playback-start")
    } else {
      ytdlp.start(task)
    }

    root.inputUrl = ""
    root.videoTitle = ""
    root.videoUploader = ""
    root.videoDuration = ""
    root.videoThumbnail = ""
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
            root.videoUploader = meta.uploader || meta.channel || ""
            root.videoDuration = meta.duration_string || Downloader.formatDuration(meta.duration)
            root.videoThumbnail = meta.thumbnail || ""
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
      command = ["notify-send", "-a", "YouTube Downloader", "-i", icon || "video-x-generic", title, body]
      running = true
    }
  }

  Process {
    id: xdgProc
    function openTarget(path) {
      command = ["xdg-open", path]
      running = true
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
          dirPath: task.destination,
          formatLabel: task.format.label,
          isAudio: task.format.isAudio,
          time: Qt.formatTime(new Date(), "hh:mm AP")
        })
        if (rec.length > 5) rec = rec.slice(0, 5)
        root.recentDownloads = rec

        notifyProc.send("Download Complete", (task.title || "Media") + "\nSaved to " + task.destination, task.format.isAudio ? "audio-x-generic" : "video-x-generic")
      } else {
        notifyProc.send("Download Failed", errorMsg || "Download could not be completed", "dialog-error")
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
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: urlField.activeFocus
      onCloseRequested: root.close()
      onActivateRequested: root.startDownload()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "1") root.selectedFormatIndex = 0
        else if (t === "2") root.selectedFormatIndex = 1
        else if (t === "3") root.selectedFormatIndex = 2
        else if (t === "4") root.selectedFormatIndex = 3
        else if (t === "5") root.selectedFormatIndex = 4
        else if (t === "c" || t === "C") ytdlp.cancel()
        else if (t === "p" || t === "P" || t === "v" || t === "V") {
          root.pasteFromClipboard()
          urlField.forceActiveFocus()
        }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: panelColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: panelColumn
          width: panelFlick.width
          spacing: Style.space(12)

          // 1. Header
          PanelHero {
            id: hero
            width: parent.width
            title: "YouTube Downloader"
            meta: ytdlp.running
              ? ("Downloading: " + ytdlp.speedText + (ytdlp.etaText !== "" ? " • ETA " + ytdlp.etaText : ""))
              : "Paste a link or select a format (1-5)"
            foreground: Color.foreground
            fontFamily: Style.font.family
            iconComponent: Component {
              Image {
                source: Qt.resolvedUrl("assets/youtube.svg")
                sourceSize.width: Style.space(24)
                sourceSize.height: Style.space(24)
                width: Style.space(24)
                height: Style.space(24)
                smooth: true
              }
            }
          }

          // 2. Input Box Row
          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: urlField
              Layout.fillWidth: true
              placeholderText: "Paste YouTube link (https://...)"
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
              Keys.onEscapePressed: {
                if (text !== "") {
                  text = ""
                  root.inputUrl = ""
                } else {
                  root.close()
                }
              }
            }

            Button {
              text: "Paste"
              iconText: "\uf0ea"
              bordered: true
              onClicked: {
                root.pasteFromClipboard()
                urlField.forceActiveFocus()
              }
            }
          }

          // 3. Metadata Preview Card
          Rectangle {
            width: parent.width
            height: metaRow.implicitHeight + Style.space(16)
            visible: root.metadataLoading || root.videoTitle !== ""
            color: Qt.rgba(1, 1, 1, 0.04)
            radius: Style.cornerRadius
            border.color: Qt.rgba(1, 1, 1, 0.1)
            border.width: 1

            RowLayout {
              id: metaRow
              anchors.fill: parent
              anchors.margins: Style.space(8)
              spacing: Style.space(10)

              Rectangle {
                width: Style.space(48)
                height: Style.space(36)
                radius: Style.space(4)
                color: Qt.rgba(1, 1, 1, 0.08)
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
                  font.pixelSize: Style.font.title
                  color: Color.muted
                }
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(2)

                Text {
                  Layout.fillWidth: true
                  text: root.metadataLoading ? "Fetching video info..." : root.videoTitle
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  Layout.fillWidth: true
                  visible: !root.metadataLoading && (root.videoUploader !== "" || root.videoDuration !== "")
                  text: (root.videoUploader !== "" ? root.videoUploader : "") + (root.videoDuration !== "" ? " • " + root.videoDuration : "")
                  color: Color.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }
          }

          // 4. Format Selection Header
          PanelSectionHeader {
            text: "FORMAT (Keys 1-5)"
          }

          // Format buttons
          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.formats

              Button {
                required property var modelData
                required property int index
                text: "[" + modelData.key + "] " + modelData.label
                selected: root.selectedFormatIndex === index
                accent: Color.accent
                bordered: true
                onClicked: root.selectedFormatIndex = index
              }
            }
          }

          // 5. Download Button
          Button {
            width: parent.width
            text: "Download " + (root.formats[root.selectedFormatIndex] ? root.formats[root.selectedFormatIndex].label : "")
            iconText: "\uf019"
            selected: true
            bordered: true
            accent: Color.accent
            onClicked: root.startDownload()
          }

          // 6. Active Download Section
          Column {
            width: parent.width
            visible: ytdlp.running
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "ACTIVE DOWNLOAD"
            }

            Rectangle {
              width: parent.width
              height: activeCol.implicitHeight + Style.space(16)
              color: Qt.rgba(1, 1, 1, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(1, 1, 1, 0.1)
              border.width: 1

              Column {
                id: activeCol
                anchors.fill: parent
                anchors.margins: Style.space(8)
                spacing: Style.space(8)

                RowLayout {
                  width: parent.width

                  Text {
                    Layout.fillWidth: true
                    text: ytdlp.currentTask ? ytdlp.currentTask.title : "Downloading..."
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Button {
                    text: "Cancel"
                    bordered: true
                    onClicked: ytdlp.cancel()
                  }
                }

                // Progress Bar
                Rectangle {
                  width: parent.width
                  height: Style.space(6)
                  radius: Style.space(3)
                  color: Qt.rgba(1, 1, 1, 0.1)

                  Rectangle {
                    height: parent.height
                    radius: parent.radius
                    color: Color.accent
                    width: Math.max(0, Math.min(parent.width, parent.width * (ytdlp.progress / 100)))

                    Behavior on width {
                      NumberAnimation { duration: 150 }
                    }
                  }
                }

                RowLayout {
                  width: parent.width

                  Text {
                    text: ytdlp.progress.toFixed(1) + "%"
                    color: Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    Layout.fillWidth: true
                    text: (ytdlp.speedText !== "" ? (" @ " + ytdlp.speedText) : "") + (ytdlp.totalText !== "" ? (" of " + ytdlp.totalText) : "")
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }

                  Text {
                    visible: ytdlp.etaText !== ""
                    text: "ETA " + ytdlp.etaText
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          // 7. Queue Section
          Column {
            width: parent.width
            visible: root.queue.length > 0
            spacing: Style.space(4)

            PanelSectionHeader {
              text: "QUEUE (" + root.queue.length + ")"
            }

            Repeater {
              model: root.queue

              Rectangle {
                required property var modelData
                required property int index
                width: parent.width
                height: queueRow.implicitHeight + Style.space(8)
                color: Qt.rgba(1, 1, 1, 0.03)
                radius: Style.cornerRadius

                RowLayout {
                  id: queueRow
                  anchors.fill: parent
                  anchors.margins: Style.space(4)

                  Text {
                    text: "#" + (index + 1)
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    Layout.fillWidth: true
                    text: modelData.title || modelData.url
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }

                  Text {
                    text: modelData.format.label
                    color: Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          // 8. Recent Downloads Section
          Column {
            width: parent.width
            visible: root.recentDownloads.length > 0
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "RECENT DOWNLOADS"
            }

            Repeater {
              model: root.recentDownloads

              Rectangle {
                required property var modelData
                width: parent.width
                height: recentRow.implicitHeight + Style.space(12)
                color: Qt.rgba(1, 1, 1, 0.04)
                radius: Style.cornerRadius
                border.color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1

                RowLayout {
                  id: recentRow
                  anchors.fill: parent
                  anchors.margins: Style.space(6)
                  spacing: Style.space(8)

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(2)

                    Text {
                      Layout.fillWidth: true
                      text: modelData.title
                      color: Color.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                    }

                    Text {
                      Layout.fillWidth: true
                      text: modelData.formatLabel + " • " + modelData.time
                      color: Color.muted
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  Button {
                    text: "Open"
                    iconText: "\uf04b"
                    bordered: true
                    visible: modelData.filePath !== ""
                    onClicked: xdgProc.openTarget(modelData.filePath)
                  }

                  Button {
                    text: "Folder"
                    iconText: "\uf07b"
                    bordered: true
                    onClicked: xdgProc.openTarget(modelData.dirPath)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
