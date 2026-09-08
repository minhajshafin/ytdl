# YouTube Downloader (`billy.ytdl`)

A mouse and keyboard-centric YouTube (and media) audio/video downloader plugin for the Omarchy Quattro top bar using `yt-dlp`.

## Features

- **Top Bar Integration**: Compact YouTube widget in the Omarchy bar with an animated active download indicator.
- **Auto-Clipboard Detection**: Automatically detects, validates, and pre-populates YouTube/media URLs copied to your clipboard when opening the panel.
- **Instant Format Presets**: Fast 1-click / 1-key presets without waiting for slow network probes:
  - `[1]` Best Video (MP4)
  - `[2]` 1080p Video (MP4)
  - `[3]` 720p Video (MP4)
  - `[4]` Audio MP3 (320k)
  - `[5]` Audio M4A (AAC)
- **Metadata Preview**: Asynchronously displays video title, channel, duration, and thumbnail in the background.
- **Smart Directory Defaults**: Automatically saves videos to `~/Videos` and audio to `~/Music`.
- **Keyboard-Centric Navigation**:
  - Global summon shortcut: `SUPER + ALT + Y`
  - In-panel shortcuts: `Enter` to download, `Esc` to close/clear, `1`–`5` to switch formats, `p`/`v` to paste.
- **Queue & History**: Download queuing and recent downloads list with direct "Open" and "Folder" actions.
- **Desktop Notifications**: Sends notifications on download completion with file details.

## Installation

Link or copy the plugin to your Omarchy plugins directory:

```bash
ln -s /home/billy/Projects/ytdl ~/.config/omarchy/plugins/billy.ytdl
```

Enable and place it on your top bar:

```bash
omarchy plugin enable billy.ytdl
omarchy bar put billy.ytdl --after omarchy.system-update
omarchy-shell shell rescanPlugins
```

## Global Keybinding

Add to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + Y", "YouTube Downloader", "omarchy-shell shell toggle billy.ytdl")
```

## License

MIT
