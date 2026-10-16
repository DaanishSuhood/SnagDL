# SnagDL

**SnagDL** is a single-file AutoHotkey v2 front-end for
[yt-dlp](https://github.com/yt-dlp/yt-dlp) on Windows.

It shows you what a video offers before you commit to a download, and estimates the output size as
you change the settings. It also fetches and updates its own copies of `yt-dlp.exe`, `ffmpeg.exe`,
and Node.js, so there is nothing to install by hand.

Script: [`SnagDL.ahk`](SnagDL.ahk), or the compiled `SnagDL.exe` from the
[latest release](https://github.com/DaanishSuhood/SnagDL/releases/latest), which needs no AutoHotkey install.

---

## Requirements

| Needed | Why | How to get it |
| --- | --- | --- |
| **AutoHotkey v2.0+** | Runs the script (`#Requires AutoHotkey v2.0`) | [autohotkey.com](https://www.autohotkey.com/) |
| **Windows PowerShell** | The info probe and the tool downloader are PowerShell helper scripts | Built into Windows |
| `yt-dlp.exe` | The actual downloader | **Get Tools** button |
| `ffmpeg.exe` + `ffprobe.exe` | Merging, converting, embedding | **Get Tools** button |
| **Node.js 22+** | YouTube needs a JavaScript runtime for its JS challenges | **Get Tools** button, or an existing install on `PATH` |

`--js-runtimes` is a recent yt-dlp option. If **Get Tools** fetched yt-dlp for you it will be new
enough; a years-old copy sitting in the folder will not be.

### Where the tools live

The executables are expected **in the same folder as the script**, not on `PATH`:

```
AutoHotkey\
├── SnagDL.ahk
├── SnagDL.exe          <- compiled build of SnagDL.ahk (optional)
├── yt-dlp.exe          <- fetched by Get Tools
├── ffmpeg.exe          <- fetched by Get Tools
├── ffprobe.exe         <- fetched by Get Tools
├── node.exe            <- fetched by Get Tools, only if no Node 22+ is on PATH
└── last_download.log   <- written on every run
```

Node is the exception: a Node.js 22 or later already on `PATH` is used as is, and **Get Tools** only
downloads the portable `node.exe` (the current LTS, from nodejs.org) when there is none. A `node.exe`
beside the script always takes priority over the one on `PATH`.

The status line always tells you which tools are missing.

---

## Getting started

1. Run `SnagDL.ahk`, or download `SnagDL.exe` from
   [Releases](https://github.com/DaanishSuhood/SnagDL/releases/latest) and put it in its own folder.
2. Press **Get Tools** and wait. ffmpeg is a ~150 MB download, so this takes a few minutes the first
   time. It only ever downloads what is actually missing.
3. Paste a URL into **Video URL** and press **Fetch info**.
4. Pick a mode, check the estimated size, press **Download**.

**Save to** defaults to your real Downloads folder (read from the registry, so a relocated Downloads
folder is respected).

---

## The window

### Top: URL and video info

**Fetch info** runs yt-dlp in JSON mode and fills in the thumbnail, title, uploader, and duration.

Fetching is optional — you can download without it — but the size estimates, the resolution list,
and the subtitle languages all come from this step.

A playlist URL is probed with `--no-playlist`, so the info and estimate describe the **first video
only**, even with **Whole playlist** ticked.

### Options

| Control | Notes |
| --- | --- |
| **Mode** | See the mode table below |
| **Max res** | Rebuilt from the probe, so it lists only heights this video actually has, each labelled with the cheapest stream at that height (`1080p - from 42.1 MB`) |
| **Audio** | `mp3`, `m4a`, `opus` (converted at 192k), or `best (no convert)` to keep the original stream untouched |
| **Subtitles** + language | `--sub-langs`, `--write-subs` or `--write-auto-subs`, `--embed-subs` |
| **Whole playlist** | `--yes-playlist` |
| **SponsorBlock** | `--sponsorblock-remove default` |
| **Clip section** | `--download-sections` — type just `1:30-4:00` |
| **Cookies from** | `--cookies-from-browser` for age-gated or members-only videos. Close the browser first — a locked cookie database cannot be read |

The subtitle language list is built from the probe, with manual tracks first and the (often 150+)
auto-generated ones below a divider. English is preselected when present. Subtitles are unavailable
in **Audio only** mode.

Always applied, with no control: `--embed-metadata --embed-chapters`, and `-N 4` (four fragments
at once).

### Modes

| Mode | What it does | Live controls |
| --- | --- | --- |
| **MP4 video (plays anywhere)** | Best pair at or below **Max res**, preferring h264 video and m4a audio (`-S "vcodec:h264,ext:mp4:m4a"`), merged into mp4 | Max res |
| **Best-quality video** | Best pair at or below **Max res**, in whatever container yt-dlp picks (often webm or mkv) | Max res |
| **Audio only** | Extracts audio, converting unless `best (no convert)`. Converted audio gets the thumbnail embedded as cover art | Audio |

The h264 preference is a *preference*, so a video without h264 degrades instead of failing. h264
usually tops out at 1080p, so MP4 mode trades 4K for playing everywhere.

Controls that do not apply to the current mode are greyed out, so the form can never describe a
download yt-dlp would not actually perform.

### Bottom: actions

- **Download** — starts yt-dlp; the progress bar and the line under it track it live.
- **Cancel** — stops a running download. Greyed out when nothing is downloading. yt-dlp usually
  leaves a `.part` file behind, and downloading the same video again picks up from it rather than
  starting over.
- **Open Folder** — opens **Save to** in Explorer.
- **Update yt-dlp** — `--update-to nightly`, because YouTube extractor fixes land there well before
  stable. No restart needed.
- **Get Tools** — downloads only the missing tools.
- **Show log** — folds the full yt-dlp output in and out. The window grows by exactly the log's
  height rather than the log stealing space from other rows, which is what keeps it short at rest.
  It opens by itself whenever something fails.

During post-processing (merging, converting, embedding) the progress bar switches to a marquee, since
yt-dlp reports no percentage for those stages.

---

## Size estimates

Sizes come from the probe, not from a trial download, so treat them as a close guide:

- **`~` prefix** — the size was `filesize_approx`, not an exact `filesize`. No prefix means exact.
- **Audio conversion** is estimated as *192k × duration*, not from the source stream size,
  because the output is re-encoded.
- HLS copies of streams are left out of the probe when a site also offers direct streams, since
  their sizes are only ever estimates.
- yt-dlp's real format selector is richer than the one modelled here, so the stream it finally picks
  can differ from the one that produced the estimate.

---

## Files it writes

| Path | Purpose |
| --- | --- |
| `<script folder>\last_download.log` | Full stdout+stderr of the last download, update, or tool fetch. Overwritten each time |
| `%TEMP%\SnagDL-probe.ps1` | The probe helper, rewritten on each fetch |
| `%TEMP%\SnagDL-get-tools.ps1` | The tool downloader, rewritten on each Get Tools |
| `%TEMP%\SnagDL-probe.txt` | The probe's pipe-delimited output |
| `%TEMP%\SnagDL-node-version.txt` | `node --version` output, read and deleted during the tool check |
| `%TEMP%\SnagDL-thumb-<ticks>.jpg` | Cached thumbnail, deleted on the next fetch and on exit |

Output filenames are `%(title)s.%(ext)s`, or for a playlist
`%(playlist_title)s\%(playlist_index)s - %(title)s.%(ext)s`.

---

## Troubleshooting

The status line and the hint under the progress bar name the likely cause on failure. The mapping:

| Log contains | Hint | What to do |
| --- | --- | --- |
| `HTTP Error 403` | The site (named by its host, e.g. `vimeo.com`) blocked the stream | **Update yt-dlp**, then try again |
| `No supported JavaScript runtime` | No JS runtime found | **Get Tools** |
| `Requested format is not available` | Video does not offer that format | **Fetch info** to see what it actually has |
| `Sign in to confirm` | The site wants a sign-in | Set **Cookies from** to your browser |
| `Unsupported URL` | yt-dlp cannot handle that URL | — |
| `Private video` / `Video unavailable` | Private, removed, or region-locked | — |
| `ffmpeg not found` | ffmpeg missing | **Get Tools** |
| cookie read failure | Cookies could not be read | Close the browser, or set Cookies from to None |

Other things worth knowing:

- **"The probe produced no output"** — PowerShell is blocked or restricted on this machine. The
  helper runs with `-ExecutionPolicy Bypass`, but an enforced machine policy still wins.
- **Update or Get Tools refuses to run** — Windows locks `yt-dlp.exe` while it is running, so
  finish any download or fetch first.
- **Tool download failed** — check the connection, and that antivirus has not quarantined
  `yt-dlp.exe`. It is a common false positive.
- **Node.js shows as missing even though it is installed** — it is older than 22, the minimum
  yt-dlp supports. **Get Tools** fetches a portable copy beside the script without touching the
  installed one.

---

## How it works

Everything is one `.ahk` file — the two PowerShell helpers are written out to `%TEMP%` at runtime, so
a lone copy of the script can still fetch its own tools and read format lists.

- **Probe** — PowerShell runs `yt-dlp -J`, then flattens the JSON into pipe-delimited lines
  (`TITLE|`, `DURATION|`, `FMT|id|ext|height|fps|vcodec|acodec|size|exact|kind|bitrate`, `SUB|`,
  `ASUB|`, `THUMB|`, `PROBE-ERR|`) which the GUI parses. It also downloads the largest **jpg**
  thumbnail, because AutoHotkey's Picture control is GDI+ and cannot decode webp.
- **Download** — yt-dlp runs hidden through `cmd.exe` with output redirected to `last_download.log`.
  A 500 ms timer re-reads the tail of that log, scrapes the last percentage and the last
  post-processor line, and decides from their positions whether it is still downloading or has moved
  on to converting.
- **JS runtime** — every yt-dlp call passes `--js-runtimes node`, or `--js-runtimes node:<path>` when
  the `node.exe` beside the script is the one in use.
- **Process tracking** — each background job (download, update, probe, tools) is tracked by PID, so
  the buttons can refuse to start a second one or to overwrite a locked `yt-dlp.exe`.

---

## Limitations

- **Cancel covers downloads only.** A running **Fetch info**, **Update yt-dlp**, or **Get Tools**
  has to finish on its own.
- **Closing the window does not stop a running download** — use **Cancel** first. yt-dlp runs as an
  independent process, so closing the GUI just leaves it running.
- `#SingleInstance Force`, so launching the script again replaces the running copy. That orphans a
  download in progress, for the same reason.
- The portable `node.exe` is not updated by **Update yt-dlp**. Delete it and press **Get Tools** to
  fetch the current LTS.
- Settings are not saved between runs.
- No global hotkeys; it is a GUI application only.
- Windows only.

---

## Legal

`yt-dlp`, `ffmpeg`, and Node.js are third-party tools under their own licences (Unlicense, GPL/LGPL,
and MIT respectively). **Get Tools** downloads them from the official
[yt-dlp](https://github.com/yt-dlp/yt-dlp/releases),
[BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds/releases), and
[nodejs.org](https://nodejs.org/dist/) release pages. Respect the terms of service and copyright of
whatever you download.

SnagDL itself is released under the [MIT License](LICENSE).
