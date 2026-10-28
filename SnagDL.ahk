#Requires AutoHotkey v2.0
#SingleInstance Force

;@Ahk2Exe-SetName SnagDL
;@Ahk2Exe-SetDescription SnagDL
;@Ahk2Exe-SetVersion 1.0.1
;@Ahk2Exe-SetMainIcon SnagDL.ico

YtDlpPath := A_ScriptDir "\yt-dlp.exe"
FfmpegPath := A_ScriptDir "\ffmpeg.exe"
FfprobePath := A_ScriptDir "\ffprobe.exe"
NodePath := A_ScriptDir "\node.exe"
LogPath := A_ScriptDir "\last_download.log"
ProbeOutPath := A_Temp "\SnagDL-probe.txt"
DefaultOutDir := GetDownloadsDir()

if !DirExist(DefaultOutDir)
    DirCreate(DefaultOutDir)

GetDownloadsDir() {
    ; The Downloads folder can be relocated, so read the Known Folder path first.
    try {
        path := RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders"
            , "{374DE290-123F-4565-9164-39C4925E467B}")
        if path != ""
            return path
    }
    return EnvGet("USERPROFILE") "\Downloads"
}

CurrentPID := 0
UpdatePID := 0
ToolsPID := 0
ProbePID := 0
IsConverting := false

; The Node.js that yt-dlp solves YouTube's JS challenges with: NodePath, "node"
; for one on PATH, or "" when neither is usable. Set by CheckTools.
NodeExe := ""

; Host of the URL being downloaded, for failure hints. Captured at start, since
; the URL box stays editable while a download runs.
DownloadSite := ""

; Set while a kill is in flight, so the poll that sees the process gone reports
; a cancellation instead of reading the truncated log as a failure.
Cancelling := false

; Probe results. Formats holds one Map per stream; the rest is video-level info.
Formats := []
ProbeTitle := ""
ProbeDuration := 0
ProbeUploader := ""
ManualSubs := []
AutoSubs := []

; Values behind the resolution list, aligned with its item order. The list is
; rebuilt from the probe, so the entries are always real options.
ResValues := [0, 2160, 1440, 1080, 720, 480, 360]
ThumbPath := ""

; Mode list entries, named once since several functions branch on them.
ModeMp4 := "MP4 video (plays anywhere)"
ModeBest := "Best-quality video"
ModeAudio := "Audio only"

; A fixed conversion bitrate - transparent for a lossy source, and it keeps the
; audio size estimate a plain bitrate x duration.
AudioKbps := 192

; Status line is composed from the current activity plus the tool inventory,
; so the two share a row instead of each taking one.
CurrentStatus := "Idle"
ToolsNote := ""
LogVisible := false
BaseClientH := 0

MainGui := Gui("+Resize", "SnagDL")
MainGui.SetFont("s10", "Segoe UI")
MainGui.OnEvent("Close", (*) => (ClearThumb(), ExitApp()))
MainGui.OnEvent("Size", GuiResize)

MainGui.AddText("xm y14 w66", "Video URL:")
UrlEdit := MainGui.AddEdit("x+6 yp-3 w506")
FetchBtn := MainGui.AddButton("x+8 yp-1 w100 h26", "Fetch info")
FetchBtn.OnEvent("Click", StartProbe)

ThumbPic := MainGui.AddPicture("xm y+10 w128 h72 +Border")
TitleText := MainGui.AddText("x+10 yp w548", "No video loaded")
DetailText := MainGui.AddText("xp y+4 w548 cGray", "Paste a URL and press Fetch info.")

; The text block is shorter than the thumbnail, so the next row is placed
; against the picture rather than against the last control added.
ThumbPic.GetPos(, &thumbY, , &thumbH)
MainGui.AddText("xm y" (thumbY + thumbH + 14) " w66", "Save to:")
OutEdit := MainGui.AddEdit("x+6 yp-3 w528", DefaultOutDir)
BrowseBtn := MainGui.AddButton("x+8 yp-1 w70 h26", "Browse...")
BrowseBtn.OnEvent("Click", BrowseFolder)

; ---------- Options ----------
MainGui.AddText("xm y+14 w38", "Mode:")
ModeDDL := MainGui.AddDropDownList("x+4 yp-4 w190 Choose1", [ModeMp4, ModeBest, ModeAudio])
ModeDDL.OnEvent("Change", ModeChanged)

MainGui.AddText("x+14 yp+4 w56", "Max res:")
ResDDL := MainGui.AddDropDownList("x+4 yp-4 w180 Choose1", [
    "Best available", "2160p", "1440p", "1080p", "720p", "480p", "360p"
])
ResDDL.OnEvent("Change", (*) => RecalcEstimate())

MainGui.AddText("x+14 yp+4 w42", "Audio:")
AudFmtDDL := MainGui.AddDropDownList("x+4 yp-4 w140 Choose1", [
    "mp3", "m4a", "opus", "best (no convert)"
])
AudFmtDDL.OnEvent("Change", (*) => RecalcEstimate())

SubsChk := MainGui.AddCheckBox("xm y+12", "Subtitles")
SubsChk.OnEvent("Click", (*) => SubLangDDL.Enabled := SubsChk.Value ? true : false)
SubLangDDL := MainGui.AddDropDownList("x+6 yp-4 w140", ["(press Fetch info)"])
SubLangDDL.Enabled := false

PlaylistChk := MainGui.AddCheckBox("x+18 yp+4", "Whole playlist")
SponsorChk := MainGui.AddCheckBox("x+18 yp", "SponsorBlock")

MainGui.AddText("xm y+14 w76", "Clip section:")
SectionEdit := MainGui.AddEdit("x+4 yp-4 w120")
MainGui.AddText("x+8 yp+4 w100 cGray", "e.g. 1:30-4:00")

MainGui.AddText("x+18 yp w84", "Cookies from:")
CookieDDL := MainGui.AddDropDownList("x+4 yp-4 w110 Choose1", [
    "None", "chrome", "edge", "firefox", "brave"
])

; ---------- Actions ----------
EstText := MainGui.AddText("xm y+12 w688", "Estimated size: press Fetch info")

DownloadBtn := MainGui.AddButton("xm y+8 w110 h32", "Download")
DownloadBtn.OnEvent("Click", StartDownload)

; Live only while a download is running - there is nothing else to cancel.
CancelBtn := MainGui.AddButton("x+10 yp w88 h32", "Cancel")
CancelBtn.OnEvent("Click", CancelDownload)
CancelBtn.Enabled := false

OpenFolderBtn := MainGui.AddButton("x+10 yp w110 h32", "Open Folder")
OpenFolderBtn.OnEvent("Click", (*) => Run("explorer.exe `"" OutEdit.Text "`""))

UpdateBtn := MainGui.AddButton("x+10 yp w116 h32", "Update yt-dlp")
UpdateBtn.OnEvent("Click", UpdateYtDlp)

GetToolsBtn := MainGui.AddButton("x+10 yp w100 h32", "Get Tools")
GetToolsBtn.OnEvent("Click", GetTools)

; Status and the tool inventory share one line; the log is folded away until
; it is wanted, which is usually only when something has gone wrong.
StatusText := MainGui.AddText("xm y+10 w570", "Idle")
LogToggleBtn := MainGui.AddButton("x+8 yp-4 w110 h24", "Show log")
LogToggleBtn.OnEvent("Click", (*) => ToggleLog())

ProgressBar := MainGui.AddProgress("xm y+8 w688 h20 Range0-100", 0)
ProgressText := MainGui.AddText("xm y+4 w688 cGray", "")

LogEdit := MainGui.AddEdit("xm y+8 w688 h190 ReadOnly VScroll -Wrap Hidden")

ModeChanged()
ProgressText.GetPos(, &ptY, , &ptH)
BaseClientH := ptY + ptH + 10
; The option rows are the widest fixed-width rows, so the window may not shrink
; below the width that keeps all of them reachable.
MainGui.Opt("+MinSize700x" BaseClientH)
MainGui.Show("w708 h" BaseClientH)
CheckTools()

GuiResize(GuiObj, MinMax, Width, Height) {
    if MinMax = -1
        return
    w := Width - 20
    UrlEdit.Move(, , w - 190)
    FetchBtn.Move(Width - 118)
    TitleText.Move(, , w - 148)
    DetailText.Move(, , w - 148)
    OutEdit.Move(, , w - 168)
    BrowseBtn.Move(Width - 88)
    EstText.Move(, , w)
    StatusText.Move(, , w - 130)
    LogToggleBtn.Move(Width - 128)
    ProgressBar.Move(, , w)
    ProgressText.Move(, , w)
    if LogVisible {
        LogEdit.GetPos(, &logY)
        LogEdit.Move(, , w, Height - logY - 10)
    }
}

; Folding the log away is what keeps the resting window short; the window grows
; by exactly the log's height rather than the log stealing from other rows.
ToggleLog(show := "") {
    global LogVisible
    LogVisible := (show = "") ? !LogVisible : show
    LogToggleBtn.Text := LogVisible ? "Hide log" : "Show log"
    LogEdit.Visible := LogVisible
    MainGui.GetClientPos(, , &cw)
    MainGui.Show("w" cw " h" (LogVisible ? BaseClientH + 198 : BaseClientH))
}

SetStatus(msg := "") {
    global CurrentStatus
    if msg != ""
        CurrentStatus := msg
    StatusText.Text := ToolsNote = "" ? CurrentStatus : CurrentStatus "   -   " ToolsNote
}

BrowseFolder(*) {
    folder := DirSelect("*" OutEdit.Text, 3, "Choose download folder")
    if folder != ""
        OutEdit.Text := folder
}

; Only the controls that affect the current mode stay live, so the form cannot
; describe a download yt-dlp would not actually perform.
ModeChanged(*) {
    isAudio := ModeDDL.Text = ModeAudio

    ResDDL.Enabled := !isAudio
    AudFmtDDL.Enabled := isAudio
    SubsChk.Enabled := !isAudio && (ManualSubs.Length || AutoSubs.Length)
    if isAudio
        SubsChk.Value := 0
    SubLangDDL.Enabled := SubsChk.Enabled && SubsChk.Value
    RecalcEstimate()
}

; ============================ Probe ============================

StartProbe(*) {
    global ProbePID, ThumbPath

    if !FileExist(YtDlpPath) {
        MsgBox("yt-dlp.exe is missing. Press Get Tools to fetch it.", "SnagDL", "Icon!")
        return
    }

    url := Trim(UrlEdit.Text)
    if url = "" {
        MsgBox("Enter a video URL first.", "SnagDL", "Icon!")
        return
    }

    if ProbePID && ProcessExist(ProbePID) {
        MsgBox("Already fetching info.", "SnagDL", "Icon!")
        return
    }

    scriptPath := WriteProbeScript()
    if scriptPath = ""
        return

    if FileExist(ProbeOutPath)
        FileDelete(ProbeOutPath)

    ; A fresh filename each time - GDI+ keeps the loaded image open, so the
    ; previous thumbnail cannot be overwritten in place.
    try ThumbPic.Value := ""
    ClearThumb()
    ThumbPath := A_Temp "\SnagDL-thumb-" A_TickCount ".jpg"

    cmd := 'cmd.exe /c ""powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "' scriptPath '"'
        . ' -Exe "' YtDlpPath '" -Url "' url '" -Out "' ProbeOutPath '"'
        . ' -Js "' JsRuntimeSpec() '"'
        . ' -Thumb "' ThumbPath '" > nul 2>&1"'

    try {
        Run(cmd, , "Hide", &pid)
    } catch as err {
        MsgBox("Failed to start the probe: " err.Message, "SnagDL", "IconX")
        return
    }

    ProbePID := pid
    FetchBtn.Enabled := false
    TitleText.Text := "Fetching info..."
    DetailText.Text := ""
    SetStatus("Fetching video info...")
    EstText.Text := "Estimated size: -"
    StartMarquee()
    SetTimer(PollProbe, 400)
}

PollProbe() {
    global ProbePID

    if ProcessExist(ProbePID)
        return

    SetTimer(PollProbe, 0)
    StopMarquee()
    ProbePID := 0
    FetchBtn.Enabled := true

    if !FileExist(ProbeOutPath) {
        TitleText.Text := "The probe produced no output - is PowerShell blocked?"
        SetStatus("Fetch failed")
        return
    }

    try
        text := FileRead(ProbeOutPath, "UTF-8")
    catch as err {
        TitleText.Text := "Could not read the probe output: " err.Message
        SetStatus("Fetch failed")
        return
    }

    ParseProbe(text)
}

ParseProbe(text) {
    global Formats, ProbeTitle, ProbeDuration, ProbeUploader, ManualSubs, AutoSubs

    Formats := []
    ManualSubs := []
    AutoSubs := []
    ProbeTitle := ""
    ProbeDuration := 0
    ProbeUploader := ""
    errMsg := ""
    thumbFile := ""

    Loop Parse text, "`n", "`r" {
        line := A_LoopField
        if line = ""
            continue
        parts := StrSplit(line, "|")
        switch parts[1] {
            case "TITLE":
                ProbeTitle := parts.Length > 1 ? parts[2] : ""
            case "DURATION":
                ProbeDuration := (parts.Length > 1 && IsNumber(parts[2])) ? Number(parts[2]) : 0
            case "UPLOADER":
                ProbeUploader := parts.Length > 1 ? parts[2] : ""
            case "SUB":
                if parts.Length > 1
                    ManualSubs.Push(parts[2])
            case "ASUB":
                if parts.Length > 1
                    AutoSubs.Push(parts[2])
            case "THUMB":
                if parts.Length > 1 && FileExist(parts[2])
                    thumbFile := parts[2]
            case "PROBE-ERR":
                errMsg := parts.Length > 1 ? parts[2] : "unknown error"
            case "FMT":
                ; FMT|id|ext|height|fps|vcodec|acodec|size|exact|kind|bitrate
                if parts.Length < 10
                    continue
                Formats.Push(Map(
                    "id", parts[2], "ext", parts[3],
                    "height", Integer(parts[4]), "fps", Integer(parts[5]),
                    "vcodec", parts[6], "acodec", parts[7],
                    "size", Integer(parts[8]), "exact", parts[9] = "1",
                    "kind", parts[10],
                    "bitrate", parts.Length >= 11 ? Integer(parts[11]) : 0))
        }
    }

    if errMsg != "" {
        TitleText.Text := "Fetch failed"
        DetailText.Text := errMsg
        SetStatus("Fetch failed")
        EstText.Text := "Estimated size: -"
        return
    }

    if thumbFile != ""
        ThumbPic.Value := thumbFile

    TitleText.Text := ProbeTitle
    detail := ProbeUploader
    if ProbeDuration > 0
        detail .= (detail = "" ? "" : "  -  ") FormatDuration(ProbeDuration)
    DetailText.Text := detail
    SetStatus("Info loaded")

    PopulateResList()
    PopulateSubList()
    ModeChanged()
}

ClearThumb() {
    global ThumbPath
    if ThumbPath != "" && FileExist(ThumbPath) {
        try FileDelete(ThumbPath)
    }
    ThumbPath := ""
}

; ---------- Lists rebuilt from the probe ----------

; Only heights the video actually offers, each labelled with the cheapest
; stream at that height so the cost of a step up is visible before choosing.
PopulateResList() {
    global ResValues
    heights := []
    cheapest := Map()
    for f in Formats {
        if f["kind"] = "audio" || !f["height"]
            continue
        h := f["height"]
        if !cheapest.Has(h) {
            heights.Push(h)
            cheapest[h] := f["size"]
        } else if f["size"] > 0 && (cheapest[h] = 0 || f["size"] < cheapest[h])
            cheapest[h] := f["size"]
    }
    SortNumsDesc(heights)

    items := ["Best available"]
    ResValues := [0]
    for h in heights {
        label := h "p"
        if cheapest[h] > 0
            label .= "  -  from " HumanSize(cheapest[h])
        items.Push(label)
        ResValues.Push(h)
    }
    ResDDL.Delete()
    ResDDL.Add(items)
    ResDDL.Choose(1)
}

CodecFamily(vcodec) {
    v := StrLower(vcodec)
    if InStr(v, "avc") || InStr(v, "h264")
        return "h264"
    if InStr(v, "vp09") || InStr(v, "vp9")
        return "vp9"
    if InStr(v, "av01") || InStr(v, "av1")
        return "av01"
    if InStr(v, "hev") || InStr(v, "hvc") || InStr(v, "h265")
        return "h265"
    if InStr(v, "vp8")
        return "vp8"
    return v
}

SortNumsDesc(nums) {
    Loop nums.Length - 1 {
        i := A_Index + 1
        cur := nums[i]
        j := i - 1
        while j >= 1 && nums[j] < cur {
            nums[j + 1] := nums[j]
            j--
        }
        nums[j + 1] := cur
    }
}

PopulateSubList() {
    SubLangDDL.Delete()
    items := []
    for lang in ManualSubs
        items.Push(lang)
    ; A video can carry 150+ auto tracks, so they sit below a divider.
    if AutoSubs.Length {
        items.Push("--- auto-generated ---")
        for lang in AutoSubs
            items.Push(lang " (auto)")
    }
    if !items.Length
        items.Push("(none available)")
    SubLangDDL.Add(items)

    pick := 1
    for i, v in items {
        if v = "en" || v = "en (auto)" {
            pick := i
            break
        }
    }
    SubLangDDL.Choose(pick)
}

; ============================ Estimate ============================

; The list is rebuilt per video, so the label is no longer a reliable key -
; the selected index maps into the value array instead.
ResCap() {
    if ModeDDL.Text = ModeAudio
        return 0
    i := ResDDL.Value
    return (i >= 1 && i <= ResValues.Length) ? ResValues[i] : 0
}

; yt-dlp's real selector is richer than this, so every figure is a close guide
; rather than a contract - which is why inexact sizes carry a leading "~".
PickVideo() {
    cap := ResCap()
    ; MP4 mode sorts h264 first; with no h264 at all it falls back, as yt-dlp would.
    best := ModeDDL.Text = ModeMp4 ? PickVideoFiltered(cap, "h264") : ""
    if best = ""
        best := PickVideoFiltered(cap, "")
    return best
}

PickVideoFiltered(cap, want) {
    best := ""
    for f in Formats {
        if f["kind"] = "audio"
            continue
        if cap > 0 && f["height"] > cap
            continue
        if want != "" && CodecFamily(f["vcodec"]) != want
            continue
        if best = "" || f["height"] > best["height"]
            || (f["height"] = best["height"] && f["size"] > best["size"])
            best := f
    }
    return best
}

PickAudio() {
    ; MP4 mode sorts m4a first, so the estimate follows it there.
    best := ModeDDL.Text = ModeMp4 ? PickAudioFiltered("m4a") : ""
    if best = ""
        best := PickAudioFiltered("")
    return best
}

PickAudioFiltered(ext) {
    best := ""
    for f in Formats {
        if f["kind"] != "audio"
            continue
        if ext != "" && f["ext"] != ext
            continue
        if best = "" || f["size"] > best["size"]
            best := f
    }
    return best
}

RecalcEstimate() {
    if !Formats.Length {
        EstText.Text := "Estimated size: press Fetch info"
        return
    }

    if ModeDDL.Text = ModeAudio {
        EstText.Text := "Estimated size: " AudioEstimate()
        return
    }

    v := PickVideo()
    a := PickAudio()
    if v = "" {
        EstText.Text := "Estimated size: no matching video format"
        return
    }
    if v["kind"] = "both" || a = "" {
        EstText.Text := "Estimated size: " SizeLabel(v["size"], v["exact"]) "  (" v["height"] "p)"
        return
    }
    total := v["size"] + a["size"]
    EstText.Text := "Estimated size: " SizeLabel(total, v["exact"] && a["exact"])
        . "  (" v["height"] "p " v["vcodec"] " " HumanSize(v["size"])
        . " + audio " HumanSize(a["size"]) ")"
}

AudioEstimate() {
    if AudFmtDDL.Text = "best (no convert)" {
        a := PickAudio()
        return a = ""
            ? "no audio stream found"
            : SizeLabel(a["size"], a["exact"]) "  (" a["ext"] " " a["acodec"] ", copied)"
    }
    if ProbeDuration <= 0
        return "unknown (no duration reported)"
    ; Re-encoded audio is bitrate x duration; the source stream size is not it.
    bytes := Integer(AudioKbps * 1000 * ProbeDuration / 8)
    return "~" HumanSize(bytes) "  (" AudFmtDDL.Text " " AudioKbps "k x "
        . FormatDuration(ProbeDuration) ", re-encoded)"
}

SizeLabel(bytes, exact) {
    if bytes <= 0
        return "unknown"
    return (exact ? "" : "~") HumanSize(bytes)
}

HumanSize(bytes) {
    if bytes >= 1073741824
        return Round(bytes / 1073741824, 2) " GB"
    if bytes >= 1048576
        return Round(bytes / 1048576, 1) " MB"
    if bytes >= 1024
        return Round(bytes / 1024, 1) " KB"
    return bytes " B"
}

FormatDuration(sec) {
    sec := Integer(sec)
    h := sec // 3600
    m := Mod(sec, 3600) // 60
    s := Mod(sec, 60)
    if h > 0
        return Format("{1}:{2:02}:{3:02}", h, m, s)
    return Format("{1}:{2:02}", m, s)
}

; ============================ Download ============================

BuildDownloadArgs() {
    args := '--js-runtimes "' JsRuntimeSpec() '" -N 4'
    args .= PlaylistChk.Value ? " --yes-playlist" : " --no-playlist"

    if ModeDDL.Text = ModeAudio {
        if AudFmtDDL.Text = "best (no convert)"
            args .= ' -f "ba/b"'
        else {
            ; Cover art is the point of a thumbnail on audio. An unconverted
            ; stream is often webm, which cannot carry one, so it goes without.
            args .= " -x --audio-format " AudFmtDDL.Text " --audio-quality " AudioKbps "K"
            args .= " --embed-thumbnail"
        }
    } else {
        cap := ResCap()
        args .= cap > 0
            ? ' -f "bv*[height<=' cap ']+ba/b[height<=' cap ']/bv*+ba/b"'
            : ' -f "bv*+ba/b"'
        ; -S expresses a preference, so a video without h264 or m4a degrades
        ; instead of failing.
        if ModeDDL.Text = ModeMp4
            args .= ' -S "vcodec:h264,ext:mp4:m4a" --merge-output-format mp4'
    }

    if SubsChk.Enabled && SubsChk.Value && ModeDDL.Text != ModeAudio {
        lang := Trim(SubLangDDL.Text)
        if lang != "" && !InStr(lang, "---") && SubStr(lang, 1, 1) != "(" {
            isAuto := InStr(lang, "(auto)") > 0
            code := Trim(StrReplace(lang, "(auto)", ""))
            args .= ' --sub-langs "' code '"'
            args .= isAuto ? " --write-auto-subs" : " --write-subs"
            args .= " --embed-subs"
        }
    }

    args .= " --embed-metadata --embed-chapters"
    if SponsorChk.Value
        args .= " --sponsorblock-remove default"
    if CookieDDL.Text != "None"
        args .= " --cookies-from-browser " CookieDDL.Text

    section := Trim(SectionEdit.Text)
    if section != ""
        args .= ' --download-sections "*' section '"'

    return args
}

StartDownload(*) {
    global CurrentPID, IsConverting, Cancelling, DownloadSite

    if !FileExist(YtDlpPath) {
        MsgBox("yt-dlp.exe is missing. Press Get Tools to fetch it.", "SnagDL", "Icon!")
        return
    }

    ; Metadata is always embedded, so every download goes through ffmpeg.
    if !FileExist(FfmpegPath) {
        MsgBox("ffmpeg.exe is missing. Press Get Tools to fetch it.", "SnagDL", "Icon!")
        return
    }

    url := Trim(UrlEdit.Text)
    if url = "" {
        MsgBox("Enter a video URL first.", "SnagDL", "Icon!")
        return
    }

    outDir := Trim(OutEdit.Text)
    if outDir = "" || !DirExist(outDir) {
        MsgBox("Choose a valid output folder first.", "SnagDL", "Icon!")
        return
    }

    if CurrentPID && ProcessExist(CurrentPID) {
        MsgBox("A download is already running.", "SnagDL", "Icon!")
        return
    }

    if FileExist(LogPath)
        FileDelete(LogPath)

    outTemplate := PlaylistChk.Value
        ? outDir "\%(playlist_title)s\%(playlist_index)s - %(title)s.%(ext)s"
        : outDir "\%(title)s.%(ext)s"

    cmd := 'cmd.exe /c ""' YtDlpPath '" ' BuildDownloadArgs()
        . ' -o "' outTemplate '" "' url '" > "' LogPath '" 2>&1"'

    try {
        Run(cmd, , "Hide", &pid)
    } catch as err {
        MsgBox("Failed to start yt-dlp: " err.Message, "SnagDL", "IconX")
        return
    }

    CurrentPID := pid
    DownloadSite := SiteName(url)
    Cancelling := false
    CancelBtn.Enabled := true
    SetStatus("Downloading...")
    LogEdit.Text := ""
    ProgressBar.Value := 0
    ProgressText.Text := ""
    if IsConverting {
        IsConverting := false
        StopMarquee()
    }
    SetTimer(PollDownload, 500)
}

; cmd.exe is what Run started, but yt-dlp.exe is its child and holds the socket,
; so the whole tree has to go - closing the parent alone leaves it downloading.
CancelDownload(*) {
    global Cancelling

    if !(CurrentPID && ProcessExist(CurrentPID)) {
        CancelBtn.Enabled := false
        return
    }

    Cancelling := true
    CancelBtn.Enabled := false
    SetStatus("Cancelling...")
    ProgressText.Text := "Stopping yt-dlp..."

    try {
        RunWait('taskkill.exe /PID ' CurrentPID ' /T /F', , "Hide")
    } catch as err {
        Cancelling := false
        CancelBtn.Enabled := true
        SetStatus("Downloading...")
        MsgBox("Could not stop yt-dlp: " err.Message, "SnagDL", "IconX")
    }
}

PollDownload() {
    global CurrentPID, IsConverting, Cancelling

    if FileExist(LogPath) {
        try {
            content := FileRead(LogPath)
            LogEdit.Text := content
            SendMessage(0x0115, 7, 0, LogEdit)

            scanText := StrLen(content) > 4000 ? SubStr(content, -4000) : content

            lastPercent := "", lastLine := "", lastDownloadPos := 0
            startPos := 1
            while (foundPos := RegExMatch(scanText, "([\d.]+)%\s+of[^\r\n]*", &m, startPos)) {
                lastPercent := m[1]
                lastLine := m[0]
                lastDownloadPos := foundPos
                startPos := foundPos + StrLen(m[0])
            }

            lastPPLine := "", lastPPPos := 0
            startPos := 1
            while (foundPos := RegExMatch(scanText, "im)^\[(Merger|ExtractAudio|Metadata|EmbedThumbnail|EmbedSubtitle|SponsorBlock|ModifyChapters|Fixup\w*|VideoConvertor|ffmpeg|ThumbnailsConvertor)\][^\r\n]*", &m, startPos)) {
                lastPPLine := m[0]
                lastPPPos := foundPos
                startPos := foundPos + StrLen(m[0])
            }

            converting := lastPPPos > 0 && lastPPPos > lastDownloadPos

            if converting && !IsConverting {
                IsConverting := true
                StartMarquee()
            } else if !converting && IsConverting {
                IsConverting := false
                StopMarquee()
            }

            if Cancelling {
                ; The status already says Cancelling - do not let a stale log
                ; line put a percentage back over it.
            } else if converting {
                ProgressText.Text := Trim(lastPPLine)
                SetStatus("Converting...")
            } else if lastPercent != "" {
                ProgressBar.Value := Round(Number(lastPercent))
                ProgressText.Text := Trim(lastLine)
                SetStatus("Downloading... " Round(Number(lastPercent)) "%")
            }
        } catch {
            ; log file may be mid-write, retry next tick
        }
    }

    if !ProcessExist(CurrentPID) {
        SetTimer(PollDownload, 0)
        if IsConverting {
            IsConverting := false
            StopMarquee()
        }
        CancelBtn.Enabled := false
        CurrentPID := 0

        ; A killed run leaves a half-written log, so it is not judged on content.
        if Cancelling {
            Cancelling := false
            ProgressBar.Value := 0
            ProgressText.Text := "Cancelled - a .part file may be left behind, "
                . "and downloading again picks up from it."
            SetStatus("Cancelled")
            return
        }

        logText := FileExist(LogPath) ? FileRead(LogPath) : ""
        if InStr(logText, "ERROR") {
            SetStatus("Failed")
            ProgressText.Text := FailureHint(logText, DownloadSite)
            ToggleLog(true)
        } else {
            ProgressBar.Value := 100
            ProgressText.Text := "Complete"
            SetStatus("Done")
        }
    }
}

StartMarquee() {
    WinSetStyle("+0x08", ProgressBar.Hwnd)
    SendMessage(0x040A, 1, 30, , ProgressBar)
}

StopMarquee() {
    SendMessage(0x040A, 0, 0, , ProgressBar)
    WinSetStyle("-0x08", ProgressBar.Hwnd)
}

UpdateYtDlp(*) {
    global UpdatePID

    ; -U rewrites yt-dlp.exe in place, which Windows blocks while it is running.
    if CurrentPID && ProcessExist(CurrentPID) {
        MsgBox("Finish the current download first - yt-dlp.exe is locked while it runs.", "SnagDL", "Icon!")
        return
    }

    if ProbePID && ProcessExist(ProbePID) {
        MsgBox("Wait for Fetch info to finish - yt-dlp.exe is locked while it runs.", "SnagDL", "Icon!")
        return
    }

    if UpdatePID && ProcessExist(UpdatePID) {
        MsgBox("An update is already running.", "SnagDL", "Icon!")
        return
    }

    ; Extractor fixes for YouTube reach nightly well before stable.
    channel := "nightly"

    if FileExist(LogPath)
        FileDelete(LogPath)

    cmd := 'cmd.exe /c ""' YtDlpPath '" --update-to ' channel ' > "' LogPath '" 2>&1"'

    try {
        Run(cmd, , "Hide", &pid)
    } catch as err {
        MsgBox("Failed to start the updater: " err.Message, "SnagDL", "IconX")
        return
    }

    UpdatePID := pid
    SetStatus("Updating (" channel ")...")
    LogEdit.Text := ""
    ProgressBar.Value := 0
    ProgressText.Text := ""
    SetTimer(PollUpdate, 500)
}

PollUpdate() {
    global UpdatePID

    if FileExist(LogPath) {
        try {
            LogEdit.Text := FileRead(LogPath)
            SendMessage(0x0115, 7, 0, LogEdit)
        } catch {
            ; log file may be mid-write, retry next tick
        }
    }

    if !ProcessExist(UpdatePID) {
        SetTimer(PollUpdate, 0)
        logText := FileExist(LogPath) ? FileRead(LogPath) : ""
        if InStr(logText, "ERROR") || InStr(logText, "Unable to") {
            SetStatus("Update failed")
            ToggleLog(true)
            ProgressText.Text := "Close any running yt-dlp.exe, then try again."
        } else if InStr(logText, "is up to date") {
            SetStatus("Already up to date")
            ProgressText.Text := ""
        } else {
            ProgressBar.Value := 100
            SetStatus("Updated")
            ProgressText.Text := "Restart is not needed - the next download uses the new build."
        }
        UpdatePID := 0
    }
}

; The bare host of a URL ("vimeo.com"), or "The site" when there is none to read.
SiteName(url) {
    if RegExMatch(url, "i)^(?:[a-z][\w+.-]*://)?(?:[^@/]*@)?(?:www\.|m\.)?([^/:?#\s]+\.[^/:?#\s]+)", &m)
        return StrLower(m[1])
    return "The site"
}

FailureHint(logText, site) {
    if InStr(logText, "HTTP Error 403")
        return site " blocked the stream - press Update yt-dlp, then try again."
    if InStr(logText, "No supported JavaScript runtime")
        return "No JS runtime found - press Get Tools to fetch Node.js."
    if InStr(logText, "Requested format is not available")
        return "This video does not offer that format - press Fetch info to see what it has."
    if InStr(logText, "Sign in to confirm")
        return site " is asking for sign-in - set Cookies from to your browser."
    if InStr(logText, "Unsupported URL") || InStr(logText, "is not a valid URL")
        return "That URL is not one yt-dlp can handle."
    if InStr(logText, "Private video") || InStr(logText, "Video unavailable")
        return "The video is private, removed, or region-locked."
    if InStr(logText, "ffmpeg not found") || InStr(logText, "ffmpeg is not installed")
        return "ffmpeg is missing - press Get Tools."
    if InStr(logText, "could not find") && InStr(logText, "cookies")
        return "Those browser cookies could not be read - close the browser, or pick None."
    return "See the log below for details."
}

CheckTools() {
    missing := []
    if !FileExist(YtDlpPath)
        missing.Push("yt-dlp.exe")
    if !FileExist(FfmpegPath)
        missing.Push("ffmpeg.exe")
    if !FileExist(FfprobePath)
        missing.Push("ffprobe.exe")

    global NodeExe := FindNode()
    if NodeExe = ""
        missing.Push("Node.js")

    global ToolsNote
    if missing.Length
        ToolsNote := "missing " JoinList(missing) ", press Get Tools"
    else
        ToolsNote := "tools ready"
    SetStatus()

    return missing
}

; A node.exe beside the script wins, since Get Tools put it there. Otherwise one
; on PATH counts only if it is new enough - yt-dlp's solver needs Node 22.
FindNode() {
    if FileExist(NodePath)
        return NodePath
    out := A_Temp "\SnagDL-node-version.txt"
    try {
        RunWait(A_ComSpec ' /c node --version > "' out '" 2>nul', , "Hide")
        ver := FileRead(out)
        FileDelete(out)
    } catch
        return ""
    if RegExMatch(ver, "^v(\d+)\.", &m) && Integer(m[1]) >= 22
        return "node"
    return ""
}

; With no usable Node, plain "node" still lets yt-dlp look for one itself, and
; sites that need no JS download as normal.
JsRuntimeSpec() {
    return (NodeExe = "" || NodeExe = "node") ? "node" : "node:" NodeExe
}

JoinList(items) {
    out := ""
    for i, v in items
        out .= (i > 1 ? ", " : "") v
    return out
}

GetTools(*) {
    global ToolsPID, ToolsNote

    if ToolsPID && ProcessExist(ToolsPID) {
        MsgBox("Tools are already downloading.", "SnagDL", "Icon!")
        return
    }

    ; All of these hold yt-dlp.exe open, so none may run while we replace it.
    if (CurrentPID && ProcessExist(CurrentPID)) || (UpdatePID && ProcessExist(UpdatePID))
        || (ProbePID && ProcessExist(ProbePID)) {
        MsgBox("Finish the current download, update, or fetch first.", "SnagDL", "Icon!")
        return
    }

    missing := CheckTools()
    if !missing.Length {
        MsgBox("All the tools are already present.", "SnagDL", "Iconi")
        return
    }

    flags := ""
    if !FileExist(YtDlpPath)
        flags .= " -Ytdlp"
    ; ffmpeg and ffprobe come out of the same archive, so one flag covers both.
    if !FileExist(FfmpegPath) || !FileExist(FfprobePath)
        flags .= " -Ffmpeg"
    if NodeExe = ""
        flags .= " -Node"

    scriptPath := WriteToolsScript()
    if scriptPath = ""
        return

    if FileExist(LogPath)
        FileDelete(LogPath)

    cmd := 'cmd.exe /c ""powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "' scriptPath '"'
        . ' -Dir "' A_ScriptDir '"' flags ' > "' LogPath '" 2>&1"'

    try {
        Run(cmd, , "Hide", &pid)
    } catch as err {
        MsgBox("Failed to start the tool downloader: " err.Message, "SnagDL", "IconX")
        return
    }

    ToolsPID := pid
    ToolsNote := "fetching " JoinList(missing)
    SetStatus("Downloading tools...")
    LogEdit.Text := ""
    ProgressBar.Value := 0
    ProgressText.Text := "ffmpeg and Node.js are large downloads - this can take several minutes."
    StartMarquee()
    SetTimer(PollTools, 500)
}

PollTools() {
    global ToolsPID

    if FileExist(LogPath) {
        try {
            LogEdit.Text := FileRead(LogPath)
            SendMessage(0x0115, 7, 0, LogEdit)
        } catch {
            ; log file may be mid-write, retry next tick
        }
    }

    if !ProcessExist(ToolsPID) {
        SetTimer(PollTools, 0)
        StopMarquee()
        logText := FileExist(LogPath) ? FileRead(LogPath) : ""
        if InStr(logText, "TOOLS-OK") {
            ProgressBar.Value := 100
            SetStatus("Tools ready")
            ProgressText.Text := ""
        } else {
            ProgressBar.Value := 0
            SetStatus("Tool download failed")
            ToggleLog(true)
            ProgressText.Text := "Check the connection, and that antivirus has not quarantined yt-dlp.exe."
        }
        CheckTools()
        ToolsPID := 0
    }
}

; ============================ Helper scripts ============================
; These live here rather than beside the .ahk so a lone copy of this script can
; still fetch its own tools and read format lists. Both are kept free of double
; quotes and backticks so they need no escaping.

ProbeScriptText() {
    lines := [
        "param(",
        "    [Parameter(Mandatory = $true)][string]$Exe,",
        "    [Parameter(Mandatory = $true)][string]$Url,",
        "    [Parameter(Mandatory = $true)][string]$Out,",
        "    [string]$Js = 'node',",
        "    [string]$Thumb = ''",
        ")",
        "",
        "$ErrorActionPreference = 'Stop'",
        "$ProgressPreference = 'SilentlyContinue'",
        "$sb = New-Object System.Text.StringBuilder",
        "function Emit($s) { [void]$sb.AppendLine($s) }",
        "function Clean($s) { if ($null -eq $s) { return '' }; return ($s -replace '[\r\n\|]', ' ') }",
        "",
        "try {",
        "    $a = @('--js-runtimes', $Js, '--no-playlist', '-J')",
        "    $raw = & $Exe @a $Url 2>$null",
        "    if ($LASTEXITCODE -ne 0 -or -not $raw) { throw 'yt-dlp could not read that URL' }",
        "    $d = ($raw -join '') | ConvertFrom-Json",
        "    Emit ('TITLE|' + (Clean $d.title))",
        "    Emit ('DURATION|' + $d.duration)",
        "    Emit ('UPLOADER|' + (Clean $d.uploader))",
        "    # HLS copies of direct streams only carry size estimates, so they are",
        "    # dropped - unless HLS is all the site offers.",
        "    $fs = @($d.formats | Where-Object { $_.protocol -notmatch 'm3u8' })",
        "    if ($fs.Count -eq 0) { $fs = @($d.formats) }",
        "    foreach ($f in $fs) {",
        "        if ($null -eq $f.format_id) { continue }",
        "        $vc = if ($f.vcodec) { $f.vcodec } else { 'none' }",
        "        $ac = if ($f.acodec) { $f.acodec } else { 'none' }",
        "        if ($vc -eq 'none' -and $ac -eq 'none') { continue }",
        "        $size = 0; $exact = 0",
        "        if ($f.filesize) { $size = [int64]$f.filesize; $exact = 1 }",
        "        elseif ($f.filesize_approx) { $size = [int64]$f.filesize_approx }",
        "        $kind = if ($vc -ne 'none' -and $ac -ne 'none') { 'both' }",
        "                elseif ($vc -ne 'none') { 'video' } else { 'audio' }",
        "        $h = if ($f.height) { [int]$f.height } else { 0 }",
        "        $fps = if ($f.fps) { [int]$f.fps } else { 0 }",
        "        $br = if ($f.abr) { [int]$f.abr } elseif ($f.tbr) { [int]$f.tbr } else { 0 }",
        "        Emit ('FMT|' + $f.format_id + '|' + $f.ext + '|' + $h + '|' + $fps + '|' +",
        "              ($vc -split '\.')[0] + '|' + ($ac -split '\.')[0] + '|' +",
        "              $size + '|' + $exact + '|' + $kind + '|' + $br)",
        "    }",
        "    if ($d.subtitles) {",
        "        foreach ($k in $d.subtitles.PSObject.Properties.Name) { Emit ('SUB|' + $k) }",
        "    }",
        "    if ($d.automatic_captions) {",
        "        foreach ($k in $d.automatic_captions.PSObject.Properties.Name) { Emit ('ASUB|' + $k) }",
        "    }",
        "    if ($Thumb) {",
        "        # The Picture control is GDI+, which cannot decode webp, so hunt",
        "        # down the largest jpg rather than taking the default thumbnail.",
        "        $turl = ''",
        "        if ($d.thumbnails) {",
        "            $jpgs = @($d.thumbnails | Where-Object { $_.url -match '\.jpg' })",
        "            if ($jpgs.Count -gt 0) {",
        "                $pick = $jpgs | Sort-Object { if ($_.width) { [int]$_.width } else { 0 } } |",
        "                        Select-Object -Last 1",
        "                $turl = $pick.url",
        "            }",
        "        }",
        "        if (-not $turl -and $d.thumbnail -match '\.jpg') { $turl = $d.thumbnail }",
        "        if ($turl) {",
        "            try {",
        "                Invoke-WebRequest -Uri $turl -OutFile $Thumb -UseBasicParsing",
        "                Emit ('THUMB|' + $Thumb)",
        "            } catch {}",
        "        }",
        "    }",
        "    Emit 'PROBE-OK'",
        "}",
        "catch { Emit ('PROBE-ERR|' + (Clean $_.Exception.Message)) }",
        "[IO.File]::WriteAllText($Out, $sb.ToString(), (New-Object Text.UTF8Encoding $false))"
    ]
    return JoinLines(lines)
}

ToolsScriptText() {
    lines := [
        "param(",
        "    [Parameter(Mandatory = $true)][string]$Dir,",
        "    [switch]$Ytdlp,",
        "    [switch]$Ffmpeg,",
        "    [switch]$Node",
        ")",
        "",
        "$ErrorActionPreference = 'Stop'",
        "$ProgressPreference = 'SilentlyContinue'",
        "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12",
        "",
        "$YtdlpUrl = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe'",
        "$FfmpegUrl = 'https://github.com/BtbN/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-win64-gpl.zip'",
        "$NodeDist = 'https://nodejs.org/dist/'",
        "",
        "try {",
        "    if ($Ytdlp) {",
        "        Write-Output 'Downloading yt-dlp.exe ...'",
        "        Invoke-WebRequest -Uri $YtdlpUrl -OutFile (Join-Path $Dir 'yt-dlp.exe')",
        "        Write-Output 'yt-dlp.exe ready.'",
        "    }",
        "    if ($Ffmpeg) {",
        "        $tmp = Join-Path $env:TEMP ('ffmpeg_' + [guid]::NewGuid().ToString('N'))",
        "        New-Item -ItemType Directory -Path $tmp | Out-Null",
        "        try {",
        "            $zip = Join-Path $tmp 'ffmpeg.zip'",
        "            Write-Output 'Downloading ffmpeg (about 150 MB, this takes a while) ...'",
        "            Invoke-WebRequest -Uri $FfmpegUrl -OutFile $zip",
        "            Write-Output 'Extracting ...'",
        "            Expand-Archive -Path $zip -DestinationPath $tmp -Force",
        "            foreach ($name in 'ffmpeg.exe', 'ffprobe.exe') {",
        "                $src = Get-ChildItem -Path $tmp -Filter $name -Recurse -File | Select-Object -First 1",
        "                if (-not $src) { throw ($name + ' was not found inside the archive') }",
        "                Copy-Item -LiteralPath $src.FullName -Destination (Join-Path $Dir $name) -Force",
        "                Write-Output ($name + ' ready.')",
        "            }",
        "        }",
        "        finally {",
        "            try { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction Stop } catch {}",
        "        }",
        "    }",
        "    if ($Node) {",
        "        # Node only publishes versioned zips, so the newest LTS is looked up first.",
        "        # The index is piped from a variable - 5.1 would pass the array as one object.",
        "        $index = Invoke-RestMethod -Uri ($NodeDist + 'index.json')",
        "        $rel = $index | Where-Object { $_.lts -and $_.files -contains 'win-x64-zip' } | Select-Object -First 1",
        "        if (-not $rel) { throw 'no Node.js LTS release was found' }",
        "        $tmp = Join-Path $env:TEMP ('node_' + [guid]::NewGuid().ToString('N'))",
        "        New-Item -ItemType Directory -Path $tmp | Out-Null",
        "        try {",
        "            $zip = Join-Path $tmp 'node.zip'",
        "            Write-Output ('Downloading Node.js ' + $rel.version + ' ...')",
        "            Invoke-WebRequest -Uri ($NodeDist + $rel.version + '/node-' + $rel.version + '-win-x64.zip') -OutFile $zip",
        "            # Only node.exe is needed, and the archive holds thousands of npm",
        "            # files that Expand-Archive would crawl through one by one.",
        "            Write-Output 'Extracting node.exe ...'",
        "            Add-Type -AssemblyName System.IO.Compression.FileSystem",
        "            $z = [IO.Compression.ZipFile]::OpenRead($zip)",
        "            try {",
        "                $entry = $z.Entries | Where-Object { $_.Name -eq 'node.exe' } | Select-Object -First 1",
        "                if (-not $entry) { throw 'node.exe was not found inside the archive' }",
        "                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $Dir 'node.exe'), $true)",
        "            }",
        "            finally { $z.Dispose() }",
        "            Write-Output 'node.exe ready.'",
        "        }",
        "        finally {",
        "            try { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction Stop } catch {}",
        "        }",
        "    }",
        "    Write-Output 'TOOLS-OK'",
        "}",
        "catch {",
        "    Write-Output ('ERROR: ' + $_.Exception.Message)",
        "    exit 1",
        "}"
    ]
    return JoinLines(lines)
}

JoinLines(lines) {
    out := ""
    for line in lines
        out .= line "`n"
    return out
}

WriteProbeScript() {
    return WriteHelperScript(A_Temp "\SnagDL-probe.ps1", ProbeScriptText())
}

WriteToolsScript() {
    return WriteHelperScript(A_Temp "\SnagDL-get-tools.ps1", ToolsScriptText())
}

WriteHelperScript(path, text) {
    try {
        if FileExist(path)
            FileDelete(path)
        FileAppend(text, path, "UTF-8")
    } catch as err {
        MsgBox("Could not write the helper script to " path ":`n" err.Message, "SnagDL", "IconX")
        return ""
    }
    return path
}
