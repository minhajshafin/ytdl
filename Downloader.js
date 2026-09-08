var AUDIO_FORMATS = [
  {
    id: "opus",
    label: "opus · best",
    display: "opus · best",
    sublabel: "Modern Opus Stream",
    isAudio: true,
    ext: "opus",
    args: ["-x", "--audio-format", "opus", "--embed-thumbnail", "--embed-metadata"]
  },
  {
    id: "m4a",
    label: "m4a · audio",
    display: "m4a · audio",
    sublabel: "AAC Best Quality",
    isAudio: true,
    ext: "m4a",
    args: ["-x", "--audio-format", "m4a", "--embed-thumbnail", "--embed-metadata"]
  },
  {
    id: "mp3",
    label: "mp3 · 320k",
    display: "mp3 · 320k",
    sublabel: "High Quality MP3",
    isAudio: true,
    ext: "mp3",
    args: ["-x", "--audio-format", "mp3", "--audio-quality", "0", "--embed-thumbnail", "--embed-metadata"]
  },
  {
    id: "flac",
    label: "flac · lossless",
    display: "flac · lossless",
    sublabel: "Lossless Audio",
    isAudio: true,
    ext: "flac",
    args: ["-x", "--audio-format", "flac", "--embed-thumbnail", "--embed-metadata"]
  }
];

var VIDEO_FORMATS = [
  {
    id: "1080p",
    label: "1080p · mp4",
    display: "1080p · mp4",
    sublabel: "Full HD 1080p",
    isAudio: false,
    ext: "mp4",
    args: ["-f", "bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/bestvideo[height<=1080]+bestaudio/best[height<=1080]", "--merge-output-format", "mp4"]
  },
  {
    id: "best",
    label: "best · max",
    display: "best · max quality",
    sublabel: "Highest Available (4K/1440p)",
    isAudio: false,
    ext: "mp4",
    args: ["-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best", "--merge-output-format", "mp4"]
  },
  {
    id: "720p",
    label: "720p · mp4",
    display: "720p · mp4",
    sublabel: "HD 720p",
    isAudio: false,
    ext: "mp4",
    args: ["-f", "bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/bestvideo[height<=720]+bestaudio/best[height<=720]", "--merge-output-format", "mp4"]
  },
  {
    id: "480p",
    label: "480p · mp4",
    display: "480p · mp4",
    sublabel: "Standard 480p",
    isAudio: false,
    ext: "mp4",
    args: ["-f", "bestvideo[height<=480][ext=mp4]+bestaudio[ext=m4a]/bestvideo[height<=480]+bestaudio/best[height<=480]", "--merge-output-format", "mp4"]
  }
];

var TAGLINES = [
  "SIPPING STREAMS",
  "PIRATING PIXELS",
  "YOINKING BYTES",
  "HOARDING MP4S",
  "BORROWING FRAMES",
  "SIPHONING SOUND",
  "NICKING PACKETS",
  "SCRAPING SERVERS",
  "FEEDING FIBER",
  "DIGITAL KLEPTOMANIA"
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

function extractYoutubeId(url) {
  if (!url || typeof url !== "string") return "";
  var m = url.match(/(?:youtu\.be\/|youtube\.com\/(?:embed\/|v\/|shorts\/|watch\?v=|watch\?.+&v=))([\w-]{11})/i);
  return m ? m[1] : "";
}

function getInstantThumbnail(url) {
  var id = extractYoutubeId(url);
  return id ? ("https://i.ytimg.com/vi/" + id + "/mqdefault.jpg") : "";
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
  var m = str.match(/\[download\]\s+([\d.]+)%\s+of\s+~?([^\s]+)\s+at\s+([^\s]+)\s+ETA\s+([^\s]+)/);
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
      eta: "0s"
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
