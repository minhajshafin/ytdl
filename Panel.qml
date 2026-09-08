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
  ipcTarget: ""
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  property string inputUrl: ""
  property int selectedFormatIndex: 0
  property var formats: Downloader.FORMATS

  property string videoTitle: ""
  property string videoUploader: ""
  property string videoDuration: ""
  property bool metadataLoading: false

  property var queue: []
  readonly property bool isDownloading: ytdlp.running

  function open() {
    root.controller.show()
    checkClipboard()
    Qt.callLater(function() {
      if (root.inputUrl === "") urlField.forceActiveFocus()
      else keyCatcher.forceActiveFocus()
    })
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

  YtDlpProcess {
    id: ytdlp
    onFinished: function(task, success, filePath, errorMsg) {
      if (success) {
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
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: urlField.activeFocus
      onCloseRequested: root.close()
      onActivateRequested: root.startDownload()
      onTabRequested: function(direction) {
        if (direction > 0) urlField.forceActiveFocus()
        else root.switchPanel(direction)
      }
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) {
          root.selectedFormatIndex = (root.selectedFormatIndex + dx + root.formats.length) % root.formats.length
        } else if (dy > 0) {
          root.selectedFormatIndex = (root.selectedFormatIndex + 1) % root.formats.length
        } else if (dy < 0) {
          root.selectedFormatIndex = (root.selectedFormatIndex - 1 + root.formats.length) % root.formats.length
        }
      }
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

      Keys.onUpPressed: function(event) {
        root.selectedFormatIndex = (root.selectedFormatIndex - 1 + root.formats.length) % root.formats.length
        event.accepted = true
      }
      Keys.onDownPressed: function(event) {
        root.selectedFormatIndex = (root.selectedFormatIndex + 1) % root.formats.length
        event.accepted = true
      }
      Keys.onLeftPressed: function(event) {
        root.selectedFormatIndex = (root.selectedFormatIndex - 1 + root.formats.length) % root.formats.length
        event.accepted = true
      }
      Keys.onRightPressed: function(event) {
        root.selectedFormatIndex = (root.selectedFormatIndex + 1) % root.formats.length
        event.accepted = true
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

        Column {
          id: panelColumn
          width: panelFlick.width
          spacing: Style.space(10)

          // 1. Minimal Header
          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "\uf16a"
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              color: Color.foreground
            }

            Text {
              Layout.fillWidth: true
              text: "YouTube Downloader"
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              color: Color.foreground
            }

            Text {
              visible: ytdlp.running
              text: ytdlp.progress.toFixed(0) + "%"
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              color: Color.accent
            }
          }

          // 2. URL Input
          RowLayout {
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: urlField
              Layout.fillWidth: true
              placeholderText: "Paste media URL..."
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
                root.selectedFormatIndex = (root.selectedFormatIndex + 1) % root.formats.length
                event.accepted = true
              }
              Keys.onUpPressed: function(event) {
                keyCatcher.forceActiveFocus()
                root.selectedFormatIndex = (root.selectedFormatIndex - 1 + root.formats.length) % root.formats.length
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

          // 3. Metadata Preview (minimal text label)
          Column {
            width: parent.width
            visible: root.metadataLoading || root.videoTitle !== ""
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: root.metadataLoading ? "Fetching video info..." : root.videoTitle
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              visible: !root.metadataLoading && (root.videoUploader !== "" || root.videoDuration !== "")
              text: (root.videoUploader !== "" ? root.videoUploader : "") + (root.videoDuration !== "" ? " • " + root.videoDuration : "")
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          // 4. Formats (Audio 1st, then Video)
          Column {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.formats

              Button {
                required property var modelData
                required property int index
                width: parent.width
                text: "[" + modelData.key + "] " + modelData.label + " (" + modelData.sublabel + ")"
                iconText: modelData.isAudio ? "\uf025" : "\uf03d"
                selected: root.selectedFormatIndex === index
                accent: Color.accent
                bordered: true
                onClicked: {
                  root.selectedFormatIndex = index
                  keyCatcher.forceActiveFocus()
                }
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

          // 6. Active Progress (visible when downloading)
          Column {
            width: parent.width
            visible: ytdlp.running
            spacing: Style.space(6)

            Rectangle {
              id: progressBarBg
              width: parent.width
              height: Style.space(6)
              radius: Style.space(3)
              color: Qt.rgba(1, 1, 1, 0.1)

              Rectangle {
                id: progressBarFill
                height: parent.height
                radius: parent.radius
                color: Color.accent
                width: Math.max(0, Math.min(progressBarBg.width, progressBarBg.width * (ytdlp.progress / 100)))

                Behavior on width {
                  NumberAnimation { duration: 100 }
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
                text: (ytdlp.speedText !== "" ? (" @ " + ytdlp.speedText) : "") + (ytdlp.etaText !== "" ? (" • ETA " + ytdlp.etaText) : "")
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              Button {
                text: "Cancel"
                bordered: true
                onClicked: ytdlp.cancel()
              }
            }
          }

          // 7. Queue (if multiple downloads queued)
          Column {
            width: parent.width
            visible: root.queue.length > 0
            spacing: Style.space(2)

            Text {
              text: "QUEUED (" + root.queue.length + ")"
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Repeater {
              model: root.queue

              RowLayout {
                required property var modelData
                required property int index
                width: parent.width

                Text {
                  text: "#" + (index + 1) + " " + (modelData.title || modelData.url)
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  Layout.fillWidth: true
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
      }
    }
  }
}
