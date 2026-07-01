# Foxit Screen Recorder - Install/Launch/Record Script
# Usage:
#   foxit_rec.ps1                        # Auto install if needed, launch, start recording (manual stop)
#   foxit_rec.ps1 -DurationSeconds 20    # Auto install, launch, record 20s, stop, report file
#   foxit_rec.ps1 -Duration 5            # Record 5 minutes
#   foxit_rec.ps1 -LaunchOnly            # Just launch
#   foxit_rec.ps1 -InstallOnly           # Just install

param(
    [switch]$LaunchOnly,
    [switch]$InstallOnly,
    [int]$Duration = 0,
    [int]$DurationSeconds = 0
)

$ErrorActionPreference = 'Continue'

$EXE_NAME = 'FoxitRecordPlus.exe'
$INSTALL_DIR = 'C:\Program Files (x86)\Foxit Software\Foxit_ScreenRecording'
$FULL_EXE = Join-Path $INSTALL_DIR $EXE_NAME
$DOWNLOAD_URL = 'https://file.foxitreader.cn/file/Channel/foxitrec/foxitrec-seoB.exe'
$INSTALLER_PATH = Join-Path $env:TEMP 'foxitrec-installer.exe'
$DESKTOP_INSTALLER = Join-Path $env:USERPROFILE 'Desktop\foxitrec-installer.exe'

# ============================================================
# Win32 Helper (C#) - all window/F7 operations in one assembly
# ============================================================
$win32Code = @'
using System; using System.Runtime.InteropServices; using System.Diagnostics;
using System.Text; using System.Collections.Generic;
public class FoxitWinHelper {
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern void keybd_event(byte b, byte s, uint f, UIntPtr e);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool AllowSetForegroundWindow(uint dwProcessId);
    [DllImport("user32.dll")] static extern bool LockSetForegroundWindow(uint uLockCode);
    [DllImport("user32.dll")] static extern bool EnumWindows(EWProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] static extern int GetWindowText(IntPtr hWnd, StringBuilder buf, int nMaxCount);
    delegate bool EWProc(IntPtr hWnd, IntPtr lParam);
    const uint KEYUP = 0x0002;
    const uint LSFW_UNLOCK = 2;
    
    public static IntPtr FindWindowByPid(uint targetPid) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((hWnd, lParam) => {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if (pid == targetPid && IsWindowVisible(hWnd) && GetParent(hWnd) == IntPtr.Zero) {
                found = hWnd;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }
    
    public static bool BringFoxitToFront() {
        var procs = Process.GetProcessesByName("FoxitRecordPlus");
        foreach (var p in procs) {
            LockSetForegroundWindow(LSFW_UNLOCK);
            AllowSetForegroundWindow((uint)p.Id);
            
            IntPtr h = p.MainWindowHandle;
            if (h == IntPtr.Zero) {
                h = FindWindowByPid((uint)p.Id);
            }
            if (h == IntPtr.Zero) {
                Console.WriteLine("  No window handle for PID " + p.Id);
                continue;
            }
            
            var sb = new StringBuilder(256);
            GetWindowText(h, sb, 256);
            Console.WriteLine("  Found HWND=" + h + " PID=" + p.Id + " Title='" + sb.ToString() + "'");
            
            // Aggressive foreground
            ShowWindow(h, 9);
            System.Threading.Thread.Sleep(200);
            BringWindowToTop(h);
            System.Threading.Thread.Sleep(200);
            SetForegroundWindow(h);
            System.Threading.Thread.Sleep(300);
            
            IntPtr fg = GetForegroundWindow();
            Console.WriteLine("  Foreground HWND=" + fg + " (matched: " + (fg == h) + ")");
            return true;
        }
        return false;
    }
    
    public static void SendF7Key() {
        keybd_event(0x76, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(50);
        keybd_event(0x76, 0, KEYUP, UIntPtr.Zero);
    }
    
    public static void SendEnterKey(IntPtr hWnd) {
        if (hWnd == IntPtr.Zero) return;
        SetForegroundWindow(hWnd);
        System.Threading.Thread.Sleep(200);
        keybd_event(0x0D, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(50);
        keybd_event(0x0D, 0, KEYUP, UIntPtr.Zero);
    }
    
    public static void MinimizeOtherWindows(uint targetPid) {
        EnumWindows((hWnd, lParam) => {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if (pid != targetPid && IsWindowVisible(hWnd) && GetParent(hWnd) == IntPtr.Zero) {
                ShowWindow(hWnd, 6); // SW_MINIMIZE
            }
            return true;
        }, IntPtr.Zero);
    }
}
'@
try {
    Add-Type -TypeDefinition $win32Code -ErrorAction Stop
    Write-Host "Win32 helper loaded"
} catch {
    Write-Host "WARNING: Win32 helper failed to load: $_"
}

# ============================================================
# Helpers
# ============================================================
function Test-AppInstalled { Test-Path $FULL_EXE }

function Find-Exe {
    if (Test-AppInstalled) { return $FULL_EXE }
    $alt = 'C:\Program Files\Foxit Software\Foxit_ScreenRecording\FoxitRecordPlus.exe'
    if (Test-Path $alt) { return $alt }
    return $null
}

function Resolve-Installer {
    # 1. 先判断 TEMP 有没有缓存，决定是否需要下载
    $needDownload = -not (Test-Path $INSTALLER_PATH)
    
    if ($needDownload) {
        Write-Host "Downloading installer (~65MB)..."
        Write-Host "URL: $DOWNLOAD_URL"
        try {
            Start-BitsTransfer -Source $DOWNLOAD_URL -Destination $INSTALLER_PATH -ErrorAction Stop -DisplayName "福昕录屏下载"
            Write-Host "Download complete"
        } catch {
            Write-Host "BITS failed, trying Invoke-WebRequest..."
            try {
                Invoke-WebRequest -Uri $DOWNLOAD_URL -OutFile $INSTALLER_PATH -UseBasicParsing -ErrorAction Stop
                Write-Host "Download complete"
            } catch {
                Write-Host "ERROR: Download failed: $_"
                return $null
            }
        }
    } else {
        Write-Host "Found cached installer (TEMP)"
    }
    
    # 2. 判断桌面有没有 installer（桌面版是最新版）
    if (Test-Path $DESKTOP_INSTALLER) {
        Write-Host "Found installer on Desktop (latest version)"
        return $DESKTOP_INSTALLER
    }
    
    # 3. 桌面没有，用 TEMP 版
    return $INSTALLER_PATH
}

function Do-Install {
    $src = Resolve-Installer
    if (-not (Test-Path $src)) { Write-Host "ERROR: Installer not found: $src"; return $false }
    Write-Host "Starting install from: $src"
    Write-Host "Please accept the UAC prompt if it appears."
    for ($retry = 0; $retry -le 2; $retry++) {
        if ($retry -gt 0) { Write-Host "Retry $retry..." }
        $p = Start-Process -FilePath $src -ArgumentList '/verysilent' -Verb RunAs -PassThru -ErrorAction SilentlyContinue
        if (-not $p) { Write-Host "Could not start installer."; continue }
        $waitSec = 0; $maxSec = 120
        while (-not $p.HasExited -and $waitSec -lt $maxSec) { Start-Sleep -Seconds 2; $waitSec += 2 }
        if ($p.HasExited) {
            Write-Host "Installer exited with code $($p.ExitCode)"
            if ($p.ExitCode -eq 0) { return $true }
        } else { Write-Host "Installer timed out after ${maxSec}s" }
    }
    return $false
}

function Wait-ForExe {
    $sec = 0
    while ($sec -lt 15) { $e = Find-Exe; if ($e) { return $e }; Start-Sleep -Seconds 1; $sec++ }
    return $null
}

function Kill-Existing {
    $old = Get-Process -Name 'FoxitRecordPlus' -ErrorAction SilentlyContinue
    if ($old) {
        Write-Host "Stopping existing FoxitRecordPlus (PID $($old.Id))..."
        wmic process where processid=$($old.Id) call terminate 2>$null | Out-Null
        Start-Sleep -Seconds 2
        $still = Get-Process -Name 'FoxitRecordPlus' -ErrorAction SilentlyContinue
        if ($still) {
            Stop-Process -InputObject $still -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        $final = Get-Process -Name 'FoxitRecordPlus' -ErrorAction SilentlyContinue
        if ($final) { Write-Host "WARNING: Could not kill PID $($final.Id)" }
        else { Write-Host "Killed successfully" }
    }
}

function Dismiss-FirstRunDialog {
    for ($i = 0; $i -lt 5; $i++) {
        $proc = Get-Process -Name 'FoxitRecordPlus' -ErrorAction SilentlyContinue
        if (-not $proc -or $proc.MainWindowHandle -eq [System.IntPtr]::Zero) { Start-Sleep -Milliseconds 500; continue }
        $title = $proc.MainWindowTitle
        if ($title -and ($title -match 'Setup|Wizard|Welcome|License|EULA|Install|Agreement')) {
            Write-Host "Dismissing dialog: $title"
            [FoxitWinHelper]::SendEnterKey($proc.MainWindowHandle)
            Start-Sleep -Seconds 1
        } else { break }
    }
}

function WaitForRecordingWindow {
    param([int]$MaxSeconds = 30)
    for ($sec = 0; $sec -lt $MaxSeconds; $sec++) {
        $proc = Get-Process -Name 'FoxitRecordPlus' -ErrorAction SilentlyContinue
        if (-not $proc) { Start-Sleep -Seconds 1; continue }
        if ($proc.Responding -and $sec -ge 3) {
            Write-Host "Recording window ready (sec $($sec + 1))"
            return $true
        }
        Start-Sleep -Seconds 1
    }
    Write-Host "WARNING: window not ready after ${MaxSeconds}s"
    return $false
}

function Ensure-OutputPath {
    $outDir = 'C:\Foxit_ScreenRecording'
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $regPath = 'HKCU:\SOFTWARE\Foxit Software\Foxit_ScreenRecording'
    if (Test-Path $regPath) { Set-ItemProperty -Path $regPath -Name 'wsOutPath' -Value $outDir -ErrorAction SilentlyContinue }
    return $outDir
}

function Do-SendF7 {
    # Step 1: Try to bring Foxit to foreground using Win32 API
    try {
        if ([FoxitWinHelper]::BringFoxitToFront()) {
            [FoxitWinHelper]::SendF7Key()
            Write-Host "F7 sent via Win32 API"
            return $true
        }
    } catch {
        Write-Host "Win32 F7 failed: $_"
    }
    
    # Step 2: WScript.Shell fallback - minimize other windows first
    Write-Host "Trying WScript.Shell fallback..."
    $wshell = New-Object -ComObject WScript.Shell -ErrorAction SilentlyContinue
    if ($wshell) {
        $procs = Get-Process -Name 'FoxitRecordPlus' -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            # Minimize all other top-level windows so Foxit gets focus
            try {
                if ([FoxitWinHelper]) {
                    [FoxitWinHelper]::MinimizeOtherWindows([uint32]$p.Id)
                    Start-Sleep -Milliseconds 500
                }
            } catch {}
            
            # Try AppActivate by PID
            try {
                $activated = $wshell.AppActivate($p.Id)
                if ($activated) {
                    Start-Sleep -Milliseconds 500
                    $wshell.SendKeys("{F7}")
                    Write-Host "F7 sent via WScript.Shell (PID $($p.Id))"
                    return $true
                }
            } catch { Write-Host "  WScript.Shell PID failed: $_" }
        }
        # Fallback: try by process name
        try {
            if ($wshell.AppActivate("FoxitRecordPlus")) {
                Start-Sleep -Milliseconds 500
                $wshell.SendKeys("{F7}")
                Write-Host "F7 sent via WScript.Shell (by name)"
                return $true
            }
        } catch {}
    }
    
    Write-Host "F7 send failed (all methods)"
    return $false
}

function Find-LatestRecording {
    param([datetime]$SinceTime)
    $searchPaths = @(
        'C:\Foxit_ScreenRecording',
        (Join-Path $env:USERPROFILE 'Documents\FoxitScreenRecorder'),
        (Join-Path $env:USERPROFILE 'Videos'),
        (Join-Path $env:USERPROFILE 'Desktop')
    )
    foreach ($sp in $searchPaths) {
        if (-not (Test-Path $sp)) { continue }
        $files = Get-ChildItem -Path $sp -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '\.(mp4|mkv|avi)$' }
        if ($SinceTime) { $files = $files | Where-Object { $_.LastWriteTime -ge $SinceTime } }
        if ($files.Count -gt 0) { return $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1 }
    }
    return $null
}

function Force-KillFoxit {
    $procs = Get-Process -Name 'FoxitRecordPlus' -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        wmic process where processid=$($p.Id) call terminate 2>$null | Out-Null
        Start-Sleep -Milliseconds 500
        $still = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
        if ($still) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    }
}

# ============================================================
# Main
# ============================================================
Write-Host "=== Foxit Screen Recorder ==="

$exe = Find-Exe
if ($exe) { Write-Host "Found: $exe" }
else {
    Write-Host "Not installed. Installing..."
    if (-not (Do-Install)) { Write-Host "ERROR: Install failed."; exit 1 }
    $exe = Wait-ForExe
    if (-not $exe) { Write-Host "ERROR: Installed but exe not found."; exit 1 }
    Write-Host "Found after install: $exe"
}

if ($InstallOnly) { exit 0 }

Kill-Existing
Start-Sleep -Seconds 1

Write-Host "Launching..."
Start-Process -FilePath $exe

Dismiss-FirstRunDialog
WaitForRecordingWindow

$outDir = Ensure-OutputPath

# Give the SOUI framework time to fully initialize
Write-Host "Waiting for full initialization..."
Start-Sleep -Seconds 5

Write-Host "Sending F7 to start recording..."
if (Do-SendF7) { Write-Host "Recording started." }
else { Write-Host "WARNING: F7 failed. Try pressing F7 manually on the Foxit window." }

# Minimize Foxit recorder window and bring target app back to front
Start-Sleep -Milliseconds 1000
$foxitProcs = Get-Process -Name 'FoxitRecordPlus' -ErrorAction SilentlyContinue
foreach ($fp in $foxitProcs) {
    try {
        $hwnd = $fp.MainWindowHandle
        if ($hwnd -ne [System.IntPtr]::Zero) {
            [WinAPI]::ShowWindow($hwnd, 6)  # SW_MINIMIZE
            Write-Host "Foxit recorder window minimized"
            break
        }
    } catch {}
}
# Brief pause then bring whatever was the foreground app (e.g. WeChat) back
Start-Sleep -Milliseconds 500
Write-Host "Recording in progress - screen capture active"

$totalSec = 0
if ($DurationSeconds -gt 0) { $totalSec = $DurationSeconds }
elseif ($Duration -gt 0) { $totalSec = $Duration * 60 }

if ($totalSec -gt 0) {
    Write-Host "Recording for $totalSec seconds..."
    Start-Sleep -Seconds $totalSec
    
    Write-Host "Sending F7 to stop recording..."
    Do-SendF7 | Out-Null
    
    Write-Host "Waiting for file save (10s)..."
    Start-Sleep -Seconds 10
    
    $recordingStartTime = (Get-Date).AddSeconds(-($totalSec + 30))
    $latest = Find-LatestRecording -SinceTime $recordingStartTime
    
    if ($latest) {
        $sz = [math]::Round($latest.Length / 1MB, 1)
        Write-Host "Saved: $($latest.FullName) (${sz} MB)"
    } else {
        Write-Host "WARNING: Recording file not found."
        Write-Host "  Output directory: $outDir"
        Write-Host "  Check if Foxit Record Plus is working correctly on this system."
        $anyFiles = Get-ChildItem -Path $outDir -ErrorAction SilentlyContinue
        if ($anyFiles) {
            Write-Host "  Files in output dir:"
            $anyFiles | ForEach-Object { Write-Host "    $($_.Name) - $([math]::Round($_.Length/1MB,1)) MB - $($_.LastWriteTime)" }
        }
    }
    
    Force-KillFoxit
    Write-Host "App closed."
} else {
    Write-Host "Recording. Press F7 to stop, or use -DurationSeconds."
}
