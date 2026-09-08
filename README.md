# YouTube Downloader (`billy.ytdl`)

A mouse and keyboard-centric YouTube (and web media) audio and video downloader plugin for the **Omarchy Quattro** top bar, powered by `yt-dlp`.

Designed to seamlessly match Omarchy's native aesthetic with dynamic theme reactivity, instant link previews, album cover art embedding, and multi-stream download acceleration.

---

## ✨ Features

- **Top Bar Integration**:
  - Sleek, monochrome circular play icon matching the exact visual weight of native Omarchy status widgets.
  - Pulsing accent activity dot indicator during active background downloads.
  - Left-click to toggle the panel; right-click to instantly paste from clipboard.

- **Audio & Video Modes**:
  - **Audio (Default)**:
    - **`opus · best`** (Default) — Native YouTube stream copy with zero quality loss.
    - **`m4a · audio`** — High-compatibility AAC stream.
    - **`mp3 · 320k`** — High-bitrate MP3 encoding.
    - **`flac · lossless`** — Uncompressed lossless audio.
  - **Video**:
    - **`1080p · mp4`** (Default) — Crisp Full HD video muxed into MP4.
    - **`best · max`** — Maximum available resolution (4K / 1440p).
    - **`720p · mp4`** — Standard HD.
    - **`480p · mp4`** — Compact standard definition.

- **Song Thumbnail & Cover Art Embedding**:
  - Automatically embeds the YouTube video thumbnail as front cover art (`attached pic`) into downloaded audio files (`.opus`, `.m4a`, `.mp3`, `.flac`).
  - Writes full track metadata (artist/channel name, track title, release date, description, and chapters).
  - Album art immediately displays in your music player, file manager, Omarchy lock screen, and top bar media widget.

- **Sub-Second Instant Link Preview**:
  - **0 ms Thumbnail**: Extracts YouTube video IDs instantly on paste/typing to load cover art immediately.
  - **~150 ms oEmbed Resolution**: Queries YouTube's lightweight oEmbed endpoint to resolve video title and author without waiting for heavy Python runtimes.
  - Streamlined background duration query without blocking the user interface.

- **Multi-Stream Download Throughput**:
  - Concurrent fragment downloading (`-N 4`) pulls DASH/HLS segments across 4 parallel network connections.
  - Enlarged 1MB I/O buffer (`--buffer-size 1024k`) for smooth disk writes.
  - Playlist guard (`--no-playlist`) prevents accidental downloads of full playlists when pasting links with `&list=...`.

- **Omarchy Native Design & Dynamic Theming**:
  - Styled after Omarchy's native Bluetooth and QuickSettings panels with a clean single-border card, tight header alignment, and subtle `PanelSeparator` divider.
  - Features rotating download satire taglines (*"YOINKING BYTES"*, *"PIRATING PIXELS"*, *"SIPPING STREAMS"*, etc.).
  - 100% reactive to Omarchy desktop theme colors (`Color.popups.background`, `Color.popups.border`, `Color.popups.text`, `Color.muted`, `Color.accent`) across Solitude, Tokyo Night, Hackerman, and light/dark modes.

- **Keyboard & Mouse Centric**:
  - Global hotkey: `SUPER + ALT + Y`.
  - Auto-paste detection: Automatically reads valid YouTube URLs from clipboard on panel open.
  - `Enter` to start download, `Esc` to close panel or clear URL.
  - `Tab` / `Shift+Tab` to toggle between Audio and Video modes.
  - `Up` / `Down` or `Space` to open and navigate the format dropdown; `1`–`4` for instant format selection.
  - `p` or `v` to paste from clipboard; dedicated click-to-paste icon in the URL bar.
  - Auto-clearing recent downloads on panel dismissal.

---

## 📥 Installation

1. Clone or link the repository to your Omarchy plugins directory:

   ```bash
   ln -s /home/billy/Projects/ytdl ~/.config/omarchy/plugins/billy.ytdl
   ```

2. Ensure runtime dependencies are installed:

   ```bash
   # Core dependencies
   sudo pacman -S yt-dlp ffmpeg wl-clipboard

   # Metadata & thumbnail embedding support
   pip install --user mutagen
   ```

3. Enable and place the widget on your Omarchy bar:

   ```bash
   omarchy plugin enable billy.ytdl
   omarchy bar put billy.ytdl --after omarchy.system-update
   omarchy restart shell
   ```

### Removal

To disable and remove the plugin:

```bash
omarchy bar remove billy.ytdl
omarchy plugin disable billy.ytdl
rm -rf ~/.config/omarchy/plugins/billy.ytdl
omarchy restart shell
```

---

## ⌨️ Global Keybinding

To toggle the downloader from anywhere with `SUPER + ALT + Y`, add the following to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + Y", "YouTube Downloader", "omarchy-shell shell toggle billy.ytdl")
```

---

## 📁 Default Download Locations

- **Audio tracks**: Saved to `~/Music` (`%(title)s.%(ext)s`)
- **Video files**: Saved to `~/Videos` (`%(title)s.%(ext)s`)

---

## 📄 License

MIT
