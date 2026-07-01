---
name: foxit-screen-recorder
description: Install, launch, and control Foxit Screen Recorder (福昕录屏) via terminal. Use when the user wants to: (1) record their screen, (2) start/stop a screen recording, (3) install Foxit Screen Recorder from the official site, or (4) capture desktop activity. Triggers: 录屏, screen record, 福昕录屏, 录制屏幕, 录制, start recording, stop recording.
---
# Foxit Screen Recorder (福昕录屏)

Install, launch, and manage screen recording sessions from terminal.

## Version Info

- **Latest Version:** 1.7.10501.3064 (as of Jan 2026)
- **Last Updated:** January 2026 (Microsoft Store / Lenovo Store)
- **Features:** HD recording, full-screen/region/game recording, audio/camera capture, scheduled recording, live annotations, video editing/compression

## Quick Start

```powershell
scripts\foxit_rec.ps1
```

Auto-detects via registry, downloads + installs if missing, launches recorder, F7 toggles recording on/off.

## Scripts

| Script | Purpose |
|--------|---------|
| `foxit_rec.ps1` | 安装/启动福昕录屏 + F7 录屏控制 |
| `record_screen.ps1` | 录制任意应用窗口，支持定时、自动输入文字 |
| `download_foxit.ps1` | 仅下载福昕录屏安装程序 |

## foxit_rec.ps1 - Script Flags

| Flag | Description |
|------|-------------|
| *(none)* | Auto-detect, install if needed, launch, F7 starts recording |
| `-LaunchOnly` | Skip install check, launch immediately |
| `-InstallOnly` | Download and install without launching |
| `-Duration <minutes>` | Record for N minutes, then F7 stop and close app |
| `-DurationSeconds <seconds>` | Record for N seconds, then F7 stop and close app (e.g. `-DurationSeconds 10`) |

## record_screen.ps1 - Usage

```powershell
.\record_screen.ps1 -ProcessName "Weixin" -Seconds 20
.\record_screen.ps1 -ProcessName "notepad" -Seconds 20 -TypeText "你好" -TypeDelay 3
.\record_screen.ps1 -ProcessName "notepad" -Seconds 10 -TypeText "你好，世界" -TypeDelay 2
.\record_screen.ps1 -List          # List running processes with visible windows
.\record_screen.ps1 -Fullscreen -Seconds 30
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-ProcessName` | string | yes (unless -Fullscreen) | Target process name (without .exe) |
| `-Seconds` | int | no | Recording duration, default 20s |
| `-TypeText` | string | no | Text to type char-by-char into target window (simulates real typing) |
| `-TypeDelay` | int | no | Seconds after start before typing, default 5 |
| `-Fullscreen` | switch | no | Record entire screen instead of a specific window |
| `-List` | switch | no | List all running processes with visible windows |
| `-Help` | switch | no | Show help |

## Recording Control

- **F7** toggles recording start/stop (global hotkey)
- Script uses Win32 API + `WScript.Shell.AppActivate()` + `SendKeys("{F7}")` to control
- After stop, waits 5s for recording to finalize, then 3s for file write, then closes app

## Installer

Inno Setup installer, supports silent install:

```powershell
foxitrec-installer.exe /verysilent
```

UAC may appear -- user needs to accept once.

## Workflow

### Install
1. Query registry `HKLM:\SOFTWARE\WOW6432Node\...\Uninstall\*` for `InstallLocation`
2. If found, skip to Launch
3. If not found, call `Resolve-Installer`:
   - **(1)** Check TEMP for cached installer -- determines if download is needed
   - **(2)** If not cached, download (~65MB) from official URL via BITS (fallback: Invoke-WebRequest)
   - **(3)** After download, check Desktop for `foxitrec-installer.exe`
     - Desktop is latest version -- **Desktop preferred**
     - No Desktop installer -- use TEMP version
4. Run installer with `/verysilent` (max 2 retries)

### Launch (foxit_rec.ps1)
1. Kill existing FoxitRecordPlus if running
2. Start `FoxitRecordPlus.exe`
3. Wait 3 seconds, `AppActivate`, send **F7** to start recording
4. If `-Duration` or `-DurationSeconds` set:
   - Wait specified time
   - Send **F7** to stop recording
   - Wait 5s, wait 3s for file finalize, force close app
   - Find and report latest recording file path

### record_screen.ps1 Workflow
1. **Check target app is running** -- if not, launch it first (e.g. Weixin via `HKCU:\SOFTWARE\Tencent\Weixin` registry)
2. **Activate target window** -- bring app to foreground
3. **Get window coordinates** -- `GetWindowRect` for screen position
4. **Launch recorder** -- `FoxitRecordPlus.exe -recordrect x y w h` (window mode) or `-recordrect` (fullscreen)
5. **Start recording** -- send F7 via Win32 API
6. **Hide recorder window** -- minimize recorder, restore target app visibility
7. **Wait + optional typing** -- uses absolute wall-clock timing. Types text character by character (random 150-400ms delay per char to simulate real typing). Typing time is included in the recording duration, not added on top.
8. **Stop recording** -- F7 stop, auto-save

**Duration calibration:** Script uses absolute wall-clock timing. Target F7-to-F7 duration equals `-Seconds` with a small `$stopOverhead` adjustment (~0.5s) to account for the time needed to bring Foxit to foreground and send the stop key. The video length matches `-Seconds` within ~1s accuracy. No startup delay compensation needed — Foxit captures from the moment F7 is pressed.

**Important (First Run):** After a fresh install, Foxit must be launched once and then exited BEFORE the first recording. This initializes the registry key `wsOutPath` (output directory) and dismisses the welcome dialog. Without this step, the first recording may not save to the expected path.

**Important:** `record_screen.ps1` requires target process already running. When recording WeChat etc., must first open WeChat then call the script.

### Find Recording
1. Read `HKCU:\SOFTWARE\Foxit Software\Foxit_ScreenRecording` -> `wsOutPath`
2. Fallback to common paths: `Documents\FoxitScreenRecorder`, `C:\Foxit_ScreenRecording`
3. Return latest `.mp4`/`.mkv`/`.avi` by `LastWriteTime`

## Notes

- **Official URL:** `https://file.foxitreader.cn/file/Channel/foxitrec/foxitrec-seoB.exe`
- **Default save path:** `HKCU:\...\Foxit_ScreenRecording` -> `wsOutPath` (e.g. `C:\Foxit_ScreenRecording`)
- Download via BITS (resumable, background)
- SHA256 integrity check on download
- Retry logic (up to 2 attempts) if installation fails

## Recording Modes

- Full screen recording
- Region/window selection
- Game mode
- Audio + camera overlay
- Scheduled/timed recording
- Live annotation/drawing during recording

## Changelog

| Date | Change |
|------|--------|
| 2026-06-23 | **record_screen.ps1**: Fixed recording duration. Replaced broken formula (`$Seconds - 3.0`) with absolute wall-clock target timing. Typing time now counts within duration, not on top. Added `$stopOverhead` parameter for stop-sequence compensation. |
| 2026-06-23 | **record_screen.ps1**: TypeText now types characters one by one (instead of clipboard paste) with random 150-400ms delay per char. |
| 2026-01 | Initial skill documentation. |
