# record_screen.ps1 - Generic screen recorder with optional text input
# Uses Foxit Screen Recorder to capture a target application window
#
# Usage:
#   .\record_screen.ps1 -ProcessName "notepad" -Seconds 20
#   .\record_screen.ps1 -ProcessName "notepad" -Seconds 20 -TypeText "Hello World" -TypeDelay 5
#   .\record_screen.ps1 -ProcessName "notepad" -Seconds 10 -TypeText "你好，世界" -TypeDelay 2
#   .\record_screen.ps1 -List          # List all running processes with windows
#   .\record_screen.ps1 -Help
#
# Changes:
#   2026-06-23: TypeText now types characters ONE BY ONE (instead of clipboard paste)
#               to simulate real typing. Each character has a random 150-400ms delay.
#               First-run note: Foxit must be launched once and exited before recording
#               to initialize registry (wsOutPath) and dismiss welcome dialog.
#   2026-06-23: Fixed recording duration. Replaced backwards formula ($Seconds - 3.0) with
#               absolute wall-clock target F7-to-F7 = $Seconds (no startup compensation needed;
#               Foxit captures from the moment F7 is pressed).
#               Also accounts for typing time in the loop so it doesn't extend the duration.

param(
    [string]$ProcessName,
    [int]$Seconds = 20,
    [string]$TypeText,
    [int]$TypeDelay = 5,
    [switch]$Fullscreen,
    [switch]$List,
    [switch]$Help
)

if ($Help) {
    Write-Host @"

record_screen.ps1 - Record any application window OR full screen

Parameters:
  -ProcessName <name>   Process name of the app to record (without .exe)
  -Seconds <n>          Recording duration in seconds (default: 20)
  -TypeText <text>      Text to type into the target app during recording
  -TypeDelay <sec>      Seconds after recording starts before typing (default: 5)
  -Fullscreen           Record entire screen instead of a specific window
  -List                 List running processes with visible windows
  -Help                 Show this help

Examples:
  .\record_screen.ps1 -ProcessName "Weixin" -Seconds 20
  .\record_screen.ps1 -ProcessName "notepad" -Seconds 20 -TypeText "Hello World"
  .\record_screen.ps1 -Fullscreen -Seconds 30
  .\record_screen.ps1 -List

"@
    exit 0
}

if ($List) {
    Write-Host "`nRunning processes with visible windows:`n"
    Get-Process | Where-Object { $_.MainWindowHandle -ne [System.IntPtr]::Zero -and $_.MainWindowTitle } |
        Select-Object ProcessName, Id, MainWindowTitle |
        Format-Table -AutoSize
    exit 0
}

if (-not $ProcessName -and -not $Fullscreen) {
    Write-Host "ERROR: -ProcessName is required for window recording, or use -Fullscreen for full screen recording. Use -List to see available processes or -Help for usage."
    exit 1
}

$mode = if ($Fullscreen) { "fullscreen" } else { "window" }

# Win32 Helper
$win32Code = @'
using System; using System.Runtime.InteropServices; using System.Diagnostics;
public class RecHelper {
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern void keybd_event(byte b, byte s, uint f, UIntPtr e);
    [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] static extern bool AllowSetForegroundWindow(uint pid);
    [DllImport("user32.dll")] static extern bool LockSetForegroundWindow(uint code);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    const uint KEYUP = 0x0002;
    const uint LSFW_UNLOCK = 2;
    
    public struct RECT {
        public int Left, Top, Right, Bottom;
        public int Width { get { return Right - Left; } }
        public int Height { get { return Bottom - Top; } }
    }
    
    public static bool BringToForeground(string procName) {
        var procs = Process.GetProcessesByName(procName);
        foreach (var p in procs) {
            LockSetForegroundWindow(LSFW_UNLOCK);
            AllowSetForegroundWindow((uint)p.Id);
            IntPtr h = p.MainWindowHandle;
            if (h == IntPtr.Zero) continue;
            ShowWindow(h, 9);
            System.Threading.Thread.Sleep(200);
            BringWindowToTop(h);
            System.Threading.Thread.Sleep(200);
            SetForegroundWindow(h);
            System.Threading.Thread.Sleep(300);
            return true;
        }
        return false;
    }
    
    public static void Minimize(string procName) {
        var procs = Process.GetProcessesByName(procName);
        foreach (var p in procs) {
            IntPtr h = p.MainWindowHandle;
            if (h != IntPtr.Zero) { ShowWindow(h, 6); }
        }
    }
    
    public static void SendF7() {
        keybd_event(0x76, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(50);
        keybd_event(0x76, 0, KEYUP, UIntPtr.Zero);
    }
    
    public static RECT GetWindowRectByProcess(string procName) {
        RECT rect = new RECT();
        var procs = Process.GetProcessesByName(procName);
        foreach (var p in procs) {
            IntPtr h = p.MainWindowHandle;
            if (h == IntPtr.Zero) continue;
            if (GetWindowRect(h, out rect)) {
                return rect;
            }
        }
        return rect;
    }
}
'@

try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -TypeDefinition $win32Code -ErrorAction Stop
    Write-Host "Helper loaded"
} catch {
    Write-Host "ERROR: $_"
    exit 1
}

# Resolve output directory
$outDir = "C:\Foxit_ScreenRecording"
$regPath = "HKCU:\SOFTWARE\Foxit Software\Foxit_ScreenRecording"
if (Test-Path $regPath) {
    $regOut = (Get-ItemProperty $regPath -Name "wsOutPath" -ErrorAction SilentlyContinue).wsOutPath
    if ($regOut -and (Test-Path $regOut)) { $outDir = $regOut }
}

# Step 1: Mode-specific preparation
if ($mode -eq "window") {
    Write-Host "`n=== Step 1: Activate '$ProcessName' ==="
    $target = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if (-not $target) {
        Write-Host "ERROR: Process '$ProcessName' not found. Use -List to see running processes."
        exit 1
    }
    [RecHelper]::BringToForeground($ProcessName)
    Write-Host "$ProcessName on screen"
    Start-Sleep -Seconds 1
} else {
    Write-Host "`n=== Step 1: Fullscreen recording mode ==="
}

# Step 2: Get target window size (only for window mode)
$x = 0; $y = 0; $w = 0; $h = 0
if ($mode -eq "window") {
    Write-Host "`n=== Step 2: Get window size of '$ProcessName' ==="
    $winRect = [RecHelper]::GetWindowRectByProcess($ProcessName)
    if ($winRect.Width -gt 0 -and $winRect.Height -gt 0) {
        $x = $winRect.Left; $y = $winRect.Top; $w = $winRect.Width; $h = $winRect.Height
        Write-Host "Window rect: x=$x y=$y w=$w h=$h"
    } else {
        Write-Host "WARNING: Could not get window rect. Falling back to fullscreen."
        $mode = "fullscreen"
    }
} else {
    Write-Host "=== Step 2: Fullscreen mode (no window rect needed) ==="
}

# Step 3: Launch Foxit with -recordrect
Write-Host "`n=== Step 3: Launch Foxit Recorder ==="
$foxitExe = "C:\Program Files (x86)\Foxit Software\Foxit_ScreenRecording\FoxitRecordPlus.exe"
if (-not (Test-Path $foxitExe)) { Write-Host "ERROR: Foxit not installed"; exit 1 }

Get-Process -Name "FoxitRecordPlus" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

$launchArgs = @("-recordrect")
if ($mode -eq "window" -and $w -gt 0 -and $h -gt 0) {
    $launchArgs += "$x", "$y", "$w", "$h"
    Write-Host "Foxit launching ($($launchArgs -join ' '))..."
} else {
    Write-Host "Foxit launching (-recordrect fullscreen)..."
}

Start-Process -FilePath $foxitExe -ArgumentList $launchArgs

# Wait for window to appear
for ($i = 0; $i -lt 15; $i++) {
    $fp = Get-Process -Name "FoxitRecordPlus" -ErrorAction SilentlyContinue
    if ($fp -and $fp.MainWindowHandle -ne [System.IntPtr]::Zero) { break }
    Start-Sleep -Seconds 1
}
Start-Sleep -Seconds 3

# Dismiss any first-run dialog
for ($i = 0; $i -lt 3; $i++) {
    $proc = Get-Process -Name 'FoxitRecordPlus' -ErrorAction SilentlyContinue
    if ($proc -and $proc.MainWindowTitle -match 'Setup|Wizard|Welcome|License|EULA|Install|Agreement') {
        [RecHelper]::BringToForeground("FoxitRecordPlus")
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep -Seconds 1
    } else { break }
}

# Send F7 to START recording
Write-Host "Starting recording (F7)..."
[RecHelper]::BringToForeground("FoxitRecordPlus")
Start-Sleep -Milliseconds 500
[RecHelper]::SendF7()
# F7 triggers recording start immediately. Engine captures from the moment F7 is sent.
$recordStartTime = Get-Date
Write-Host "Recording started"

# Step 4: Minimize Foxit, restore target window visibility
if ($mode -eq "window") {
    Write-Host "`n=== Step 4: Minimize Foxit, restore '$ProcessName' ==="
    Start-Sleep -Milliseconds 500
    [RecHelper]::Minimize("FoxitRecordPlus")
    Start-Sleep -Milliseconds 300
    [RecHelper]::BringToForeground($ProcessName)
    Start-Sleep -Milliseconds 500
    Write-Host ">> $ProcessName is VISIBLE on screen, recording for $Seconds seconds..."
} else {
    Write-Host "`n=== Step 4: Minimize Foxit ==="
    [RecHelper]::Minimize("FoxitRecordPlus")
    Write-Host ">> Fullscreen recording in progress for $Seconds seconds..."
}

if ($TypeText) {
    Write-Host ">> Will type text in $TypeDelay seconds..."
}

# Step 5: Record for specified duration, with optional typing
# Recording duration: target F7-to-F7 ≈ $Seconds.
# Step 6 (bring Foxit to foreground + send F7) adds ~1.5s overhead, so we
# start the stop sequence 1.5s early so F7-stop fires at roughly $Seconds.
$stopOverhead = 0.5
$targetEndTime = $recordStartTime.AddSeconds($Seconds - $stopOverhead)
Write-Host "F7-start: $($recordStartTime.ToString('HH:mm:ss')), target F7-stop: ~$($targetEndTime.AddSeconds($stopOverhead).ToString('HH:mm:ss')) (target: ${Seconds}s)"

$typingDone = $false
while ((Get-Date) -lt $targetEndTime) {
    $elapsedSec = ((Get-Date) - $recordStartTime).TotalSeconds
    if ($TypeText -and -not $typingDone -and $elapsedSec -ge $TypeDelay) {
        Write-Host "`n=== Typing: '$TypeText' ==="
        if ($mode -eq "window") {
            [RecHelper]::BringToForeground($ProcessName)
            Start-Sleep -Milliseconds 500
        }
        for ($i = 0; $i -lt $TypeText.Length; $i++) {
            $ch = ($TypeText[$i]).ToString()
            [System.Windows.Forms.SendKeys]::SendWait($ch)
            $rd = Get-Random -Minimum 150 -Maximum 400
            Start-Sleep -Milliseconds $rd
            Write-Host "Typed: '$ch' (${rd}ms)"
        }
        Write-Host "All characters typed one by one"
        $typingDone = $true
    }
    Start-Sleep -Milliseconds 300
}
Write-Host "`nRecording duration complete"

# Step 6: Stop recording
Write-Host "`n=== Step 6: Stop Recording (F7) ==="
[RecHelper]::BringToForeground("FoxitRecordPlus")
Start-Sleep -Milliseconds 500
[RecHelper]::SendF7()
Write-Host "Recording stopped"

$actualDuration = [math]::Round(((Get-Date) - $recordStartTime).TotalSeconds, 1)
Write-Host "Actual recording duration: ${actualDuration}s"

Write-Host "`nWaiting for file save..."
Start-Sleep -Seconds 5

# Find recording
$since = $recordStartTime.AddSeconds(-5)
$files = Get-ChildItem -Path $outDir -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -match "\.(mp4|mkv|avi)$" -and $_.LastWriteTime -ge $since }
if ($files) {
    $latest = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $sz = [math]::Round($latest.Length / 1MB, 1)
    Write-Host "Saved: $($latest.FullName) ($sz MB)"
} else {
    Write-Host "WARNING: No recording file found in $outDir"
    if (Test-Path $outDir) {
        Get-ChildItem -Path $outDir -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host "  $($_.Name) - $([math]::Round($_.Length/1MB,1)) MB - $($_.LastWriteTime)"
        }
    }
}

Get-Process -Name "FoxitRecordPlus" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Write-Host "`nDone."
