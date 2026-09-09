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

var ALLOWED_DOMAINS = [
  "youtube.com",
  "youtu.be",
  "soundcloud.com",
  "vimeo.com",
  "tiktok.com",
  "twitch.tv",
  "twitter.com",
  "x.com",
  "reddit.com",
  "instagram.com",
  "facebook.com"
];

function isPrivateOrNonPublicHost(host) {
  if (!host || typeof host !== "string") return true;

  // Single-label / unqualified hostnames (e.g. router, nas, intranet)
  if (host.indexOf(".") === -1 && host !== "localhost") {
    return true;
  }

  if (host === "localhost" || host.endsWith(".localhost") ||
      host.endsWith(".local") || host.endsWith(".internal") ||
      host.endsWith(".lan") || host.endsWith(".home.arpa") ||
      host.endsWith(".invalid") || host.endsWith(".test") ||
      host.endsWith(".example")) {
    return true;
  }

  // Reject IPv4 addresses (private, loopback, link-local, multicast, etc.)
  var ipv4Match = host.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (ipv4Match) {
    var o1 = parseInt(ipv4Match[1], 10);
    var o2 = parseInt(ipv4Match[2], 10);
    var o3 = parseInt(ipv4Match[3], 10);
    var o4 = parseInt(ipv4Match[4], 10);

    if (o1 > 255 || o2 > 255 || o3 > 255 || o4 > 255) return true;
    if (o1 === 0 || o1 === 127) return true; // 0.0.0.0/8 and 127.0.0.0/8 (Loopback)
    if (o1 === 10) return true; // 10.0.0.0/8 (Private)
    if (o1 === 172 && o2 >= 16 && o2 <= 31) return true; // 172.16.0.0/12 (Private)
    if (o1 === 192 && o2 === 168) return true; // 192.168.0.0/16 (Private)
    if (o1 === 169 && o2 === 254) return true; // 169.254.0.0/16 (Link-local)
    if (o1 === 100 && o2 >= 64 && o2 <= 127) return true; // 100.64.0.0/10 (Carrier-grade NAT)
    if (o1 >= 224) return true; // Multicast & Reserved
    return true; // Reject raw IP destinations
  }

  // Reject IPv6 addresses
  if (host.indexOf(":") !== -1) {
    return true;
  }

  return false;
}

function parseUrl(urlStr) {
  if (!urlStr || typeof urlStr !== "string") return null;
  var trimmed = urlStr.trim();
  if (trimmed === "") return null;

  // Enforce scheme: strictly require https
  var schemeMatch = trimmed.match(/^(https):\/\/([^\/\?#]+)(?:([\/\?#].*))?$/i);
  if (!schemeMatch) return null;

  var scheme = schemeMatch[1].toLowerCase();
  var authority = schemeMatch[2];
  var path = schemeMatch[3] || "";

  // Reject user credentials (@ in authority)
  if (authority.indexOf("@") !== -1) return null;

  var host = "";
  var port = "";

  if (authority.charAt(0) === "[") {
    var closeBracket = authority.indexOf("]");
    if (closeBracket === -1) return null;
    host = authority.substring(1, closeBracket).toLowerCase();
    var portPart = authority.substring(closeBracket + 1);
    if (portPart.length > 0) {
      if (portPart.charAt(0) !== ":") return null;
      port = portPart.substring(1);
      if (!port.match(/^\d+$/)) return null;
    }
  } else {
    var colonIdx = authority.indexOf(":");
    if (colonIdx !== -1) {
      host = authority.substring(0, colonIdx).toLowerCase();
      port = authority.substring(colonIdx + 1);
      if (!port.match(/^\d+$/)) return null;
    } else {
      host = authority.toLowerCase();
    }
  }

  // Strip trailing root dots
  while (host.length > 1 && host.charAt(host.length - 1) === ".") {
    host = host.substring(0, host.length - 1);
  }

  if (host === "") return null;

  return {
    scheme: scheme,
    host: host,
    port: port,
    path: path
  };
}

function isValidUrl(str) {
  var parsed = parseUrl(str);
  if (!parsed) return false;

  if (isPrivateOrNonPublicHost(parsed.host)) {
    return false;
  }

  // Enforce label-bound suffix allowlisting
  for (var i = 0; i < ALLOWED_DOMAINS.length; i++) {
    var domain = ALLOWED_DOMAINS[i];
    if (parsed.host === domain || parsed.host.endsWith("." + domain)) {
      return true;
    }
  }

  return false;
}

function extractYoutubeId(url) {
  var parsed = parseUrl(url);
  if (!parsed) return "";

  var host = parsed.host;
  var isYoutube = (host === "youtube.com" || host.endsWith(".youtube.com"));
  var isYoutuBe = (host === "youtu.be");

  if (!isYoutube && !isYoutuBe) return "";

  if (isYoutuBe) {
    var ym = parsed.path.match(/^\/([\w-]{11})/i);
    return ym ? ym[1] : "";
  }

  var m = parsed.path.match(/(?:\/(?:embed|v|shorts)\/|watch\?.*[?&]v=|watch\?v=)([\w-]{11})/i);
  return m ? m[1] : "";
}

function getInstantThumbnail(url) {
  var id = extractYoutubeId(url);
  return id ? ("https://i.ytimg.com/vi/" + id + "/mqdefault.jpg") : "";
}

function cleanUrl(str) {
  if (!str || typeof str !== "string") return "";
  var trimmed = str.trim();
  return isValidUrl(trimmed) ? trimmed : "";
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
