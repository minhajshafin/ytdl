import QtQuick
import Quickshell
import Quickshell.Io
import "Downloader.js" as Downloader

Item {
  id: root

  property bool running: proc.running
  property real progress: 0
  property string stateText: "Idle"
  property string speedText: ""
  property string sizeText: ""
  property string etaText: ""
  property var currentTask: null
  property string savedPath: ""
  property string errorText: ""

  signal finished(var task, bool success, string filePath, string errorMsg)

  function formatEta(raw) {
    if (!raw || raw === "N/A" || raw === "NA") return ""
    var str = String(raw).trim()
    var parts = str.split(":")
    if (parts.length === 2) {
      var m = parseInt(parts[0], 10)
      var s = parseInt(parts[1], 10)
      if (m === 0) return s + "s"
      return m + "m " + s + "s"
    }
    if (parts.length === 3) {
      var h = parseInt(parts[0], 10)
      var m2 = parseInt(parts[1], 10)
      var s2 = parseInt(parts[2], 10)
      return h + "h " + m2 + "m"
    }
    return str
  }

  function start(task) {
    if (proc.running) return false
    currentTask = task
    progress = 0
    stateText = "Connecting"
    speedText = ""
    sizeText = ""
    etaText = ""
    savedPath = ""
    errorText = ""

    var cmd = [
      "yt-dlp",
      "--no-playlist",
      "-N", "4",
      "--buffer-size", "1024k",
      "--progress",
      "--newline",
      "--no-colors",
      "--no-mtime",
      "--progress-template", "DOWNLOAD_PROGRESS:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(progress._total_bytes_estimate_str)s",
      "--print", "after_move:SAVED_PATH:%(filepath)s",
      "-P", task.destination || (task.format && task.format.isAudio ? (Quickshell.env("HOME") + "/Music") : (Quickshell.env("HOME") + "/Videos")),
      "-o", "%(title)s.%(ext)s"
    ]

    if (task.format && task.format.args) {
      for (var i = 0; i < task.format.args.length; i++) {
        cmd.push(task.format.args[i])
      }
    }

    cmd.push(task.url)
    proc.command = cmd
    proc.running = true
    return true
  }

  function cancel() {
    if (proc.running) {
      stateText = "Cancelled"
      proc.running = false
      if (currentTask) {
        var t = currentTask
        currentTask = null
        finished(t, false, "", "Cancelled by user")
      }
    }
  }

  Process {
    id: proc

    stdout: SplitParser {
      onRead: function(line) {
        var str = String(line || "").trim()
        if (str.indexOf("SAVED_PATH:") === 0) {
          root.savedPath = str.substring(11).trim()
          return
        }

        var p = Downloader.parseProgress(str)
        if (p) {
          root.progress = p.percent
          root.stateText = "Downloading"
          if (p.speed && p.speed !== "Unknown B/s") root.speedText = p.speed
          if (p.eta) root.etaText = root.formatEta(p.eta)
          if (p.total && p.total !== "N/A" && p.total !== "NA") root.sizeText = p.total
          return
        }

        if (str.indexOf("[ExtractAudio]") !== -1) {
          root.stateText = "Extracting"
        } else if (str.indexOf("[Merger]") !== -1) {
          root.stateText = "Merging"
        } else if (str.indexOf("[download] Destination:") !== -1) {
          root.stateText = "Downloading"
        }
      }
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var err = String(text || "").trim()
        if (err !== "") root.errorText = err
      }
    }

    onExited: function(exitCode) {
      var task = root.currentTask
      root.currentTask = null
      if (!task) return

      if (exitCode === 0) {
        root.progress = 100
        root.stateText = "Done"
        root.finished(task, true, root.savedPath, "")
      } else {
        root.stateText = "Failed"
        root.finished(task, false, "", root.errorText || ("yt-dlp failed (code " + exitCode + ")"))
      }
    }
  }
}
