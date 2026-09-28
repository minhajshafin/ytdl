# YouTube Downloader (`billy.ytdl`)

A fast, mouse and keyboard-centric YouTube audio and video downloader for the **Omarchy** top bar, powered by `yt-dlp`.

---

## 📥 Installation

Install dependencies and add the plugin to your Omarchy bar in one command:

```bash
sudo pacman -S --needed yt-dlp ffmpeg wl-clipboard python-mutagen && omarchy plugin add https://github.com/minhajshafin/ytdl.git --enable
```

> **Plugin Only** (if dependencies are already installed):
> ```bash
> omarchy plugin add https://github.com/minhajshafin/ytdl.git --enable
> ```

### Updates & Removal

- **Update**: `omarchy plugin update billy.ytdl`
- **Remove**: `omarchy plugin remove billy.ytdl`

---

## ⚡ Features

- **Audio & Video Formats**: Download in Opus, M4A, MP3, FLAC, or MP4 (1080p, 4K/Best, 720p, 480p).
- **Metadata & Cover Art**: Automatically embeds video thumbnails as front cover art and writes track tags.
- **Instant Preview**: Zero-delay thumbnail display and ~150ms oEmbed title lookup on paste.
- **Multi-Stream Speed**: 4 parallel DASH/HLS fragment downloads with 1MB I/O buffer.
- **Native Theming**: Automatically matches active Omarchy desktop color palette.

---

## ⌨️ Controls & Keybindings

- **Left-Click bar icon**: Toggle panel.
- **Right-Click bar icon** or **`p` / `v`**: Paste URL from clipboard.
- **`Enter`**: Start download.
- **`Tab` / `Shift+Tab`**: Switch between Audio and Video modes.
- **`1`–`4`**: Quick-select format quality.
- **`Esc`**: Clear URL field or close panel.

To bind a global hotkey (e.g. `SUPER + ALT + Y`), add this to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + Y", "YouTube Downloader", "omarchy-shell shell toggle billy.ytdl")
```

---

## 📁 Downloads

- **Audio tracks**: Saved to `~/Music`
- **Video files**: Saved to `~/Videos`

---

## 📄 License

MIT
