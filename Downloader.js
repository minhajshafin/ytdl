.pragma library

var FORMATS = [
  {
    id: "audio-mp3",
    key: "1",
    label: "MP3 Audio",
    sublabel: "320k",
    isAudio: true,
    ext: "mp3",
    args: ["-x", "--audio-format", "mp3", "--audio-quality", "0"]
  },
  {
    id: "audio-m4a",
    key: "2",
    label: "M4A Audio",
    sublabel: "AAC Best",
    isAudio: true,
    ext: "m4a",
    args: ["-x", "--audio-format", "m4a"]
  },
  {
    id: "best-video",
    key: "3",
    label: "Best Video",
    sublabel: "MP4 Max",
    isAudio: false,
    ext: "mp4",
    args: ["-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best", "--merge-output-format", "mp4"]
  },
  {
    id: "1080p",
    key: "4",
    label: "1080p Video",
    sublabel: "FHD MP4",
    isAudio: false,
    ext: "mp4",
    args: ["-f", "bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/bestvideo[height<=1080]+bestaudio/best[height<=1080]", "--merge-output-format", "mp4"]
  },
  {
    id: "720p",
    key: "5",
    label: "720p Video",
    sublabel: "HD MP4",
    isAudio: false,
    ext: "mp4",
    args: ["-f", "bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/bestvideo[height<=720]+bestaudio/best[height<=720]", "--merge-output-format", "mp4"]
  }
];

function isValidUrl(str) {
  if (!str || typeof str !== "string") return false;
  var trimmed = str.trim();
  if (!trimmed.match(/^https?:\/\//i)) return false;
  return (
    trimmed.indexOf("youtube.com") !== -1 ||
    trimmed.indexOf("youtu.be") !== -1 ||
    trimmed.indexOf("soundcloud.com") !== -1 ||
    trimmed.indexOf("vimeo.com") !== -1 ||
    trimmed.indexOf("tiktok.com") !== -1 ||
    trimmed.indexOf("twitch.tv") !== -1 ||
    trimmed.indexOf("twitter.com") !== -1 ||
    trimmed.indexOf("x.com") !== -1 ||
    trimmed.indexOf("reddit.com") !== -1 ||
    trimmed.indexOf("instagram.com") !== -1 ||
    trimmed.indexOf("facebook.com") !== -1
  );
}

function cleanUrl(str) {
  if (!str || typeof str !== "string") return "";
  return str.trim();
}

function parseProgress(line) {
  if (!line || typeof line !== "string") return null;
  var str = line.trim();

  // Pattern: DOWNLOAD_PROGRESS: 45.2%| 2.50MiB/s| 00:03| 12.34MiB
  if (str.indexOf("DOWNLOAD_PROGRESS:") === 0) {
    var raw = str.substring(18);
    var parts = raw.split("|");
    var percentStr = (parts[0] || "").replace("%", "").trim();
    var percent = parseFloat(percentStr);
    return {
      percent: isNaN(percent) ? 0 : Math.max(0, Math.min(100, percent)),
      speed: (parts[1] || "").trim(),
      eta: (parts[2] || "").trim(),
      total: (parts[3] || "").trim()
    };
  }

  // Fallback: [download]  45.2% of 10.00MiB at 2.50MiB/s ETA 00:03
  var m = str.match(/\[download\]\s+([\d\.]+)%\s+of\s+~?([^\s]+)\s+at\s+([^\s]+)\s+ETA\s+([^\s]+)/);
  if (m) {
    return {
      percent: Math.max(0, Math.min(100, parseFloat(m[1]))),
      total: m[2],
      speed: m[3],
      eta: m[4]
    };
  }

  var m100 = str.match(/\[download\]\s+100%/);
  if (m100) {
    return {
      percent: 100,
      total: "",
      speed: "",
      eta: "00:00"
    };
  }

  return null;
}

function formatDuration(sec) {
  var s = parseInt(sec, 10);
  if (isNaN(s) || s <= 0) return "";
  var h = Math.floor(s / 3600);
  var m = Math.floor((s % 3600) / 60);
  var remSec = s % 60;
  if (h > 0) {
    return h + ":" + (m < 10 ? "0" : "") + m + ":" + (remSec < 10 ? "0" : "") + remSec;
  }
  return m + ":" + (remSec < 10 ? "0" : "") + remSec;
}
