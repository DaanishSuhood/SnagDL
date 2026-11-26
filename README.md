# SnagDL

**SnagDL** is a single-file AutoHotkey v2 front-end for
[yt-dlp](https://github.com/yt-dlp/yt-dlp) on Windows.

It shows you what a video offers before you commit to a download, and estimates the output size as
you change the settings. It also fetches and updates its own copies of `yt-dlp.exe`, `ffmpeg.exe`,
and Node.js, so there is nothing to install by hand, and it updates itself from this repo's releases.

Script: [`SnagDL.ahk`](SnagDL.ahk), or from the
[latest release](https://github.com/DaanishSuhood/SnagDL/releases/latest) either the installer
`SnagDL-Setup-<version>.exe` or the portable `SnagDL.exe`. Neither needs an AutoHotkey install.

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

## Installing

1. Download `SnagDL-Setup-<version>.exe` from the
   [latest release](https://github.com/DaanishSuhood/SnagDL/releases/latest).
2. Run it. It installs for your user account only, so there is no UAC prompt.
3. Choose the install folder, which defaults to `%LOCALAPPDATA%\Programs\SnagDL`. Keep or untick
   **Create a Start menu shortcut** and **Create a desktop shortcut**; both are ticked by default.
4. On the last page, tick **Launch SnagDL** to start it right away.

**No install needed?** The release also has a portable `SnagDL.exe`. Put it in its own folder, since
the tools it fetches are saved beside it. Or run `SnagDL.ahk` directly with AutoHotkey v2.

To upgrade, let SnagDL do it (see [Updating SnagDL](#updating-snagdl)), or run a newer setup over the
existing install; there's no need to uninstall first, and the tools already fetched are kept.

**Uninstalling:** go to **Settings → Apps → Installed apps → SnagDL → Uninstall**. This removes the
program, both shortcuts, and the yt-dlp, ffmpeg and Node.js copies that **Get Tools** fetched.
Your downloaded videos are never touched.

> **"Windows protected your PC" warning:** SnagDL isn't code-signed, so SmartScreen may warn about
> it. Click **More info → Run anyway** to continue. To check that your download is the genuine file,
> compare it with the release's `SHA256SUMS.txt`: in PowerShell, run
> `Get-FileHash .\SnagDL-Setup-<version>.exe` and check that the hash matches.

The installer is per-user on purpose: SnagDL saves its tools and log beside its own exe, so it has to
live somewhere you can write to, which `Program Files` is not.

---

## Getting started

1. Start SnagDL from the Start menu or desktop.
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

Fetch info uses the **Cookies from** setting, as the download does: with **None** it reads no cookies,
and with a browser picked it signs in as you, so age-restricted videos and YouTube's bot check work
here too. If it fails, the line under the title gives the hint from [Troubleshooting](#troubleshooting),
or yt-dlp's own error message.

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
| **Cookies from** | `--cookies-from-browser` for age-gated or members-only videos. The first pick in each run asks for confirmation, since yt-dlp then downloads as your logged-in account. Firefox works best: Chrome, Edge and Brave must be fully closed, and Chrome's cookies often cannot be decrypted on Windows at all |

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
- **Update SnagDL** — checks for a newer SnagDL release and offers to install it; see
  [Updating SnagDL](#updating-snagdl).
- **Show log** — folds the full yt-dlp output in and out. The window grows by exactly the log's
  height rather than the log stealing space from other rows, which is what keeps it short at rest.
  It opens by itself whenever something fails.

During post-processing (merging, converting, embedding) the progress bar switches to a marquee, since
yt-dlp reports no percentage for those stages.

---

## Updating SnagDL

Every time SnagDL starts, it asks the GitHub API for the
[latest release](https://github.com/DaanishSuhood/SnagDL/releases/latest) (drafts and pre-releases
are skipped). If that release is newer, it asks whether to update, and the status line shows
`SnagDL <version> available`. It never asks in the middle of a download; press **Update SnagDL** later
instead. That button also runs the check by hand.

Saying yes:

1. SnagDL downloads the release file that matches how it was installed, plus `SHA256SUMS.txt`, and
   checks the file's hash. A missing or mismatched checksum stops the update, and nothing is changed.
2. Only then does SnagDL close and hand over to a helper, which:
   - **Installed copy**: runs `SnagDL-Setup-<version>.exe /SILENT`. It upgrades in place, keeping the
     folder, the shortcut choices, and the fetched tools.
   - **Portable copy**: moves the old `SnagDL.exe` aside, copies the new one in, and deletes the old
     one. If the copy fails, the old exe is put back.
3. The helper starts the new SnagDL. If anything failed, it starts the old copy again and shows the
   error.

A copy counts as installed when the installer's uninstall entry points at the folder it is running
from; anything else is treated as portable. Running `SnagDL.ahk` as a script only offers to open the
release page, since a script has no exe to swap (`git pull` updates a checkout).

The update is refused while a download, **Fetch info**, **Update yt-dlp**, or **Get Tools** is running,
since SnagDL has to close.

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
| `%TEMP%\SnagDL-update-check.ps1` / `.txt` | The update check and its result, rewritten at every start |
| `%TEMP%\SnagDL-self-update.ps1` | The self-updater, written when an update starts |
| `%TEMP%\SnagDL-self-update.log` | Output of the last self-update. Check here if an update failed |
| `%TEMP%\SnagDL-self-update\` | The downloaded update, deleted once it is applied |

Output filenames are `%(title)s.%(ext)s`, or for a playlist
`%(playlist_title)s\%(playlist_index)s - %(title)s.%(ext)s`.

---

## Troubleshooting

The status line and the hint under the progress bar name the likely cause on failure; for
**Fetch info**, the hint goes under the title. The mapping:

| Log contains | Hint | What to do |
| --- | --- | --- |
| `HTTP Error 429` / `Too Many Requests` / `rate-limited` | The site is limiting requests from this network | Wait a while (often up to an hour), or set **Cookies from** to your browser. Retrying straight away tends to make the limit last longer |
| `HTTP Error 403` | The site (named by its host, e.g. `vimeo.com`) blocked the stream | **Update yt-dlp**, then try again |
| `No supported JavaScript runtime` | No JS runtime found | **Get Tools** |
| `Requested format is not available` | Video does not offer that format | **Fetch info** to see what it actually has |
| `Sign in to confirm` | The site wants a sign-in (including YouTube's *not a bot* check) | Set **Cookies from** to your browser. If it is already set, log in to the site in that browser, or wait a while |
| `Unsupported URL` | yt-dlp cannot handle that URL | — |
| `Private video` / `Video unavailable` | Private, removed, or region-locked | — |
| `ffmpeg not found` | ffmpeg missing | **Get Tools** |
| `Failed to decrypt with DPAPI` | The browser's cookies are encrypted so yt-dlp cannot read them | Log in with Firefox and pick it, or set Cookies from to None |
| `Could not copy Chrome cookie database` | The browser (Chrome, Edge or Brave) is still open | Close it completely, including from the system tray |
| `could not find … cookies database` | No cookies for that browser | Check it is installed and logged in to the site |
| other cookie read failure | Cookies could not be read | Close the browser, or set Cookies from to None |

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

Everything is one `.ahk` file — the PowerShell helpers (probe, tool downloader, update check,
self-updater) are written out to `%TEMP%` at runtime, so a lone copy of the script can still fetch
its own tools and read format lists.

- **Probe** — PowerShell runs `yt-dlp -J`, then flattens the JSON into pipe-delimited lines
  (`TITLE|`, `DURATION|`, `FMT|id|ext|height|fps|vcodec|acodec|size|exact|kind|bitrate`, `SUB|`,
  `ASUB|`, `THUMB|`, `PROBE-ERR|`, and `PROBE-LOG|` for each line yt-dlp wrote to stderr when it
  failed) which the GUI parses. It also downloads the largest **jpg**
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

## Building a release

Needs [AutoHotkey v2](https://www.autohotkey.com/) (for Ahk2Exe) and
[Inno Setup 6](https://jrsoftware.org/isinfo.php) (`winget install --id JRSoftware.InnoSetup -e`). Then:

```powershell
.\publish.ps1                 # artifacts\publish\SnagDL.exe + artifacts\installer\SnagDL-Setup-<version>.exe
.\publish.ps1 -SkipInstaller  # only the .exe
```

Either way it also writes `artifacts\SHA256SUMS.txt` to attach to the release. The installer is built
from [`installer\SnagDL.iss`](installer/SnagDL.iss). The version comes from the
`AppVersion := "x.y.z"` line at the top of `SnagDL.ahk`, so bump it there before a release. Ahk2Exe
stamps the exe from that same line, and `publish.ps1` checks that the two agree.

**Update SnagDL depends on the release layout**, so every release needs:

| What | Why |
| --- | --- |
| Tag `v<version>`, matching `AppVersion` | Compared with the running version |
| A published, non-pre-release release | `releases/latest` ignores drafts and pre-releases |
| `SnagDL.exe` | What portable copies download |
| `SnagDL-Setup-<version>.exe` | What installed copies download |
| `SHA256SUMS.txt` listing both | An update whose file is not listed, or does not match, is refused |

```powershell
gh release create v1.1.0 artifacts\publish\SnagDL.exe artifacts\installer\SnagDL-Setup-1.1.0.exe artifacts\SHA256SUMS.txt
```

Copies older than the first release with **Update SnagDL** (1.0.0 and earlier) cannot update themselves.
Their users need to download that release once by hand.

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
- Settings are not saved between runs, so the update check at start-up cannot be turned off.
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
