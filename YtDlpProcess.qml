import QtQuick
import Quickshell
import Quickshell.Io
import "Downloader.js" as Downloader

Item {
  id: root

  property bool running: proc.running
  property real progress: 0
  property string speedText: ""
  property string etaText: ""
  property string totalText: ""
  property string statusMessage: ""
  property var currentTask: null
  property string savedPath: ""
  property string errorText: ""

  signal finished(var task, bool success, string filePath, string errorMsg)

  function start(task) {
    if (proc.running) return false
    currentTask = task
    progress = 0
    speedText = ""
    etaText = ""
    totalText = ""
    statusMessage = "Starting download..."
    savedPath = ""
    errorText = ""

    var cmd = [
      "yt-dlp",
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
      statusMessage = "Cancelled"
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
          if (p.speed) root.speedText = p.speed
          if (p.eta) root.etaText = p.eta
          if (p.total) root.totalText = p.total
          root.statusMessage = p.percent.toFixed(1) + "%"
          return
        }

        if (str.indexOf("[ExtractAudio]") !== -1) {
          root.statusMessage = "Extracting audio..."
        } else if (str.indexOf("[Merger]") !== -1) {
          root.statusMessage = "Merging formats..."
        } else if (str.indexOf("[download] Destination:") !== -1) {
          root.statusMessage = "Connecting..."
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
        root.statusMessage = "Done"
        root.finished(task, true, root.savedPath, "")
      } else {
        root.statusMessage = "Failed"
        root.finished(task, false, "", root.errorText || ("yt-dlp failed (code " + exitCode + ")"))
      }
    }
  }
}
