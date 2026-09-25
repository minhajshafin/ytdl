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
  property var diagnosticLines: []
  property int diagnosticCharCount: 0
  property int activePgid: 0

  signal finished(var task, bool success, string filePath, string errorMsg)

  Process {
    id: killTermProc
    function killGroup(pgid) {
      if (!pgid || pgid <= 1) return
      command = ["kill", "-TERM", "--", "-" + pgid]
      running = true
    }
  }

  Process {
    id: killKillProc
    function killGroup(pgid) {
      if (!pgid || pgid <= 1) return
      command = ["kill", "-KILL", "--", "-" + pgid]
      running = true
    }
  }

  Timer {
    id: killEscalationTimer
    interval: 1000
    repeat: false
    property int targetPgid: 0
    onTriggered: {
      if (targetPgid > 1) {
        killKillProc.killGroup(targetPgid)
        targetPgid = 0
      }
    }
  }

  Component.onDestruction: {
    var pgid = root.activePgid
    root.activePgid = 0
    killEscalationTimer.stop()
    if (pgid > 1) {
      proc.running = false
      killTermProc.killGroup(pgid)
    }
  }

  function appendDiagnostic(rawLine) {
    if (!rawLine) return
    var str = String(rawLine).trim()
    if (str === "") return

    // Cap single line length
    if (str.length > 512) {
      str = str.substring(0, 512) + "…"
    }

    var lines = root.diagnosticLines.slice()
    lines.push(str)
    var totalChars = root.diagnosticCharCount + str.length

    // Strictly bounded buffer: max 15 lines and max 2048 chars
    while (lines.length > 15 || totalChars > 2048) {
      var removed = lines.shift()
      totalChars -= (removed ? removed.length : 0)
    }

    root.diagnosticLines = lines
    root.diagnosticCharCount = Math.max(0, totalChars)
  }

  function getDiagnosticSummary() {
    if (!root.diagnosticLines || root.diagnosticLines.length === 0) return ""

    for (var i = root.diagnosticLines.length - 1; i >= 0; i--) {
      var l = root.diagnosticLines[i]
      if (l.indexOf("ERROR:") !== -1) {
        return l
      }
    }

    return root.diagnosticLines[root.diagnosticLines.length - 1]
  }

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
    diagnosticLines = []
    diagnosticCharCount = 0
    activePgid = 0

    var homeDir = Quickshell.env("HOME") || "/tmp"
    var defaultDest = (task.format && task.format.isAudio) ? (homeDir + "/Music") : (homeDir + "/Videos")

    stdoutLineBuffer = ""
    stderrLineBuffer = ""
    totalStderrBytes = 0

    var cmd = [
      "setsid",
      "yt-dlp",
      "--ignore-config",
      "--no-plugin-dirs",
      "--no-playlist",
      "-N", "4",
      "--buffer-size", "1024k",
      "--progress",
      "--newline",
      "--no-colors",
      "--no-mtime",
      "--progress-template", "DOWNLOAD_PROGRESS:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(progress._total_bytes_estimate_str)s",
      "--print", "after_move:SAVED_PATH:%(filepath)s",
      "-P", task.destination || defaultDest,
      "-o", "%(title)s.%(ext)s"
    ]

    if (task.format && task.format.args) {
      for (var i = 0; i < task.format.args.length; i++) {
        cmd.push(task.format.args[i])
      }
    }

    cmd.push("--")
    cmd.push(task.url)
    proc.command = cmd
    proc.running = true
    return true
  }

  function cancel() {
    var pgid = root.activePgid
    root.activePgid = 0

    stdoutLineBuffer = ""
    stderrLineBuffer = ""
    totalStderrBytes = 0

    if (proc.running) {
      stateText = "Cancelled"
      proc.running = false
    }

    if (pgid > 1) {
      killTermProc.killGroup(pgid)
      killEscalationTimer.targetPgid = pgid
      killEscalationTimer.restart()
    }

    diagnosticLines = []
    diagnosticCharCount = 0

    if (currentTask) {
      var t = currentTask
      currentTask = null
      finished(t, false, "", "Cancelled by user")
    }
  }

  property string stdoutLineBuffer: ""
  property string stderrLineBuffer: ""
  readonly property int maxLineLength: 2048
  property int totalStderrBytes: 0

  function processStdoutLine(line) {
    if (!line) return
    var str = String(line).trim()
    if (str === "") return

    if (str.indexOf("SAVED_PATH:") === 0) {
      var sp = str.substring(11).trim()
      if (sp.length > 0 && sp.length <= 1024 && sp.charAt(0) === "/" && !/[\r\n\0]/.test(sp)) {
        root.savedPath = sp
      }
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

  function handleStdoutChunk(chunk) {
    if (!chunk) return
    var str = String(chunk)
    var combined = root.stdoutLineBuffer + str
    var newlineIdx = combined.indexOf("\n")

    if (newlineIdx === -1) {
      if (combined.length > root.maxLineLength) {
        root.processStdoutLine(combined.substring(0, root.maxLineLength))
        root.stdoutLineBuffer = ""
      } else {
        root.stdoutLineBuffer = combined
      }
      return
    }

    var lines = combined.split("\n")
    var remainder = lines.pop()
    if (remainder.length > root.maxLineLength) {
      root.processStdoutLine(remainder.substring(0, root.maxLineLength))
      root.stdoutLineBuffer = ""
    } else {
      root.stdoutLineBuffer = remainder
    }

    for (var i = 0; i < lines.length; i++) {
      var l = lines[i]
      if (l.length > root.maxLineLength) {
        l = l.substring(0, root.maxLineLength)
      }
      root.processStdoutLine(l)
    }
  }

  function handleStderrChunk(chunk) {
    if (!chunk) return
    var str = String(chunk)
    root.totalStderrBytes += str.length
    if (root.totalStderrBytes > 32768) return

    var combined = root.stderrLineBuffer + str
    var newlineIdx = combined.indexOf("\n")

    if (newlineIdx === -1) {
      if (combined.length > 512) {
        root.appendDiagnostic(combined.substring(0, 512))
        root.stderrLineBuffer = ""
      } else {
        root.stderrLineBuffer = combined
      }
      return
    }

    var lines = combined.split("\n")
    var remainder = lines.pop()
    if (remainder.length > 512) {
      root.appendDiagnostic(remainder.substring(0, 512))
      root.stderrLineBuffer = ""
    } else {
      root.stderrLineBuffer = remainder
    }

    for (var i = 0; i < lines.length; i++) {
      var l = lines[i]
      if (l.length > 512) {
        l = l.substring(0, 512)
      }
      root.appendDiagnostic(l)
    }
  }

  Process {
    id: proc

    onStarted: {
      var pid = parseInt(proc.processId, 10) || 0
      if (pid > 1) {
        root.activePgid = pid
      }
    }
    onProcessIdChanged: {
      var pid = parseInt(proc.processId, 10) || 0
      if (pid > 1) {
        root.activePgid = pid
      }
    }

    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        root.handleStdoutChunk(chunk)
      }
    }

    stderr: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        root.handleStderrChunk(chunk)
      }
    }

    onExited: function(exitCode) {
      killEscalationTimer.stop()
      killEscalationTimer.targetPgid = 0
      root.activePgid = 0

      if (root.stdoutLineBuffer !== "") {
        root.processStdoutLine(root.stdoutLineBuffer.substring(0, root.maxLineLength))
        root.stdoutLineBuffer = ""
      }
      if (root.stderrLineBuffer !== "") {
        root.appendDiagnostic(root.stderrLineBuffer.substring(0, 512))
        root.stderrLineBuffer = ""
      }
      root.totalStderrBytes = 0

      var task = root.currentTask
      root.currentTask = null
      if (!task) return

      if (exitCode === 0) {
        root.progress = 100
        root.stateText = "Done"
        root.finished(task, true, root.savedPath, "")
      } else {
        root.stateText = "Failed"
        var diag = root.getDiagnosticSummary()
        root.errorText = diag
        root.finished(task, false, "", diag || ("yt-dlp failed (code " + exitCode + ")"))
      }
    }
  }
}
