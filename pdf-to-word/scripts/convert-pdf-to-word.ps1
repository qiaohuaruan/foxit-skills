<#
.SYNOPSIS
    通过福昕 PDF 编辑器快捷键操作，将 PDF 转换为 Word (.docx)
.DESCRIPTION
    使用键盘模拟执行 Alt → B → D → 1 → A → Enter 菜单序列，
    将 PDF 转换为同名 Word 文件。
    支持重试、Verbose 输出、智能窗口管理。
.PARAMETER PdfPath
    要转换的 PDF 文件路径（必填）
.PARAMETER OutputDir
    输出目录，默认桌面
.PARAMETER CloseAfter
    转换后自动关闭福昕，默认 $false
.PARAMETER WaitSeconds
    最大等待秒数，默认 120
.PARAMETER RetryCount
    按键序列重试次数（超时未检测到文件时自动重试），默认 1
.PARAMETER Force
    强制关闭已有福昕进程（否则仅警告），默认 $false
.EXAMPLE
    .\convert-pdf-to-word.ps1 -PdfPath "C:\docs\report.pdf"
    .\convert-pdf-to-word.ps1 -PdfPath "C:\docs\report.pdf" -OutputDir "C:\output" -CloseAfter -Verbose
    .\convert-pdf-to-word.ps1 -PdfPath "C:\docs\report.pdf" -Force -RetryCount 2
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$PdfPath,

    [string]$OutputDir = [Environment]::GetFolderPath("Desktop"),

    [switch]$CloseAfter,

    [int]$WaitSeconds = 120,

    [int]$RetryCount = 1,

    [switch]$Force,

    [string]$OutputName
)

# Verbose 支持
$Verbose = $PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -ne 'SilentlyContinue'
function Write-Log {
    param([string]$Message, [string]$ForegroundColor = "White")
    if ($Verbose) { Write-Verbose $Message }
    Write-Host $Message -ForegroundColor $ForegroundColor
}

# ── 解析路径（支持相对路径）──
$PdfPath = (Resolve-Path $PdfPath -ErrorAction Stop).Path
$pdfName = [System.IO.Path]::GetFileNameWithoutExtension($PdfPath)
$pdfDir  = [System.IO.Path]::GetDirectoryName($PdfPath)

# ── 1. 查找福昕安装路径 ──────────────────────────────────
$foxitCandidates = @(
    "C:\Program Files (x86)\Foxit Software\Foxit Phantom\FoxitPhantom.exe"
    "C:\Program Files (x86)\Foxit Software\Foxit PhantomPDF\FoxitPhantomPDF.exe"
    "C:\Program Files (x86)\Foxit Software\Foxit PDF Editor\FoxitPDFEditor.exe"
    "C:\Program Files\Foxit Software\Foxit Phantom\FoxitPhantom.exe"
    "C:\Program Files\Foxit Software\Foxit PhantomPDF\FoxitPhantomPDF.exe"
    "C:\Program Files\Foxit Software\Foxit PDF Editor\FoxitPDFEditor.exe"
)

$foxitExe = $null
foreach ($c in $foxitCandidates) {
    if (Test-Path $c) { $foxitExe = $c; break }
}

# 注册表回退
if (-not $foxitExe) {
    Write-Log "⏳ 注册表中查找福昕..." -ForegroundColor Gray
    
    # 1) App Paths 注册表（最直接，安装程序自动注册）
    $appPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\FoxitPhantom.exe",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\FoxitPhantom.exe",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\FoxitPhantomPDF.exe",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\FoxitPhantomPDF.exe",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\FoxitPDFEditor.exe",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\FoxitPDFEditor.exe"
    )
    foreach ($ap in $appPaths) {
        $val = Get-ItemProperty $ap -Name "(default)" -ErrorAction SilentlyContinue
        if ($val -and $val."(default)" -and (Test-Path $val."(default)")) {
            $foxitExe = $val."(default)"
            Write-Log "注册表 App Paths 找到: $foxitExe" -ForegroundColor Green
            break
        }
    }
}

# 2) 卸载信息回退
if (-not $foxitExe) {
    $uninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $uninstall = Get-ItemProperty $uninstallPaths -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -match "Foxit" -and 
            $_.DisplayName -match "(Phantom|PDF|福昕)"
        }
    if ($uninstall) {
        $installDir = $uninstall | Select-Object -First 1 -ExpandProperty InstallLocation
        if ($installDir) {
            $foxitExe = Get-ChildItem "$installDir\*.exe" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "Foxit(Phantom|PDFEditor)" } |
                Select-Object -First 1 -ExpandProperty FullName
            if ($foxitExe) {
                Write-Log "注册表 Uninstall 找到: $foxitExe" -ForegroundColor Green
            }
        }
    }
}

if (-not $foxitExe) {
    throw "福昕PDF编辑器未安装，请先安装后重试。"
}

$foxitProcName = [System.IO.Path]::GetFileNameWithoutExtension($foxitExe)
Write-Log "福昕路径: $foxitExe" -ForegroundColor Green

# ── 2. 关闭已有福昕进程（有选择地） ────────────────────
$existingFoxit = Get-Process -Name $foxitProcName -ErrorAction SilentlyContinue
if ($existingFoxit) {
    if ($Force) {
        Write-Log "关闭已有福昕进程..." -ForegroundColor Yellow
        $existingFoxit | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    } else {
        Write-Log "福昕进程已在运行。使用 -Force 可自动关闭。尝试复用窗口..." -ForegroundColor Yellow
        Start-Process -FilePath $foxitExe -ArgumentList "`"$PdfPath`""
        Start-Sleep -Seconds 3
    }
}

# ── 3. 加载 WinForms + Win32 API ──────────────────────────
Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop

# 幂等加载 Win32 API
try {
    Add-Type -MemberDefinition @'
[DllImport("user32.dll")]
public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")]
public static extern bool IsIconic(IntPtr hWnd);
[DllImport("user32.dll")]
public static extern bool AllowSetForegroundWindow(int dwProcessId);
[DllImport("user32.dll")]
public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out int lpdwProcessId);
[DllImport("kernel32.dll")]
public static extern int GetCurrentThreadId();
[DllImport("user32.dll")]
public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
'@ -Name Win32Helper -Namespace NativeMethods -ErrorAction Stop
    Write-Log "Win32 API 已加载" -ForegroundColor Gray
} catch {
    Write-Log "Win32 API 已有，跳过加载" -ForegroundColor Gray
}

# ── 4. 启动福昕并打开 PDF ───────────────────────────────
if (-not $existingFoxit -or $Force) {
    Write-Log "打开 PDF: $PdfPath" -ForegroundColor Cyan
    $proc = Start-Process -FilePath $foxitExe -ArgumentList "`"$PdfPath`"" -PassThru
    # 等待窗口出现：最大 15 秒
    $foxitProc = $null
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 1
        $foxitProc = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
        if ($foxitProc -and $foxitProc.MainWindowHandle -ne 0) { break }
    }
} else {
    Start-Sleep -Seconds 4
    $foxitProc = $existingFoxit | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
}

if (-not $foxitProc) {
    throw "福昕启动后未检测到主窗口"
}

# ── 5. 窗口置前（增强版）────────────────────────────────
$hWnd = $foxitProc.MainWindowHandle

# 还原最小化窗口
if ([NativeMethods.Win32Helper]::IsIconic($hWnd)) {
    [NativeMethods.Win32Helper]::ShowWindow($hWnd, 9)  # SW_RESTORE
    Start-Sleep -Milliseconds 500
}

# 方法 1: VB AppActivate（最可靠）
try {
    [Microsoft.VisualBasic.Interaction]::AppActivate($foxitProc.Id)
    Write-Log "AppActivate 成功" -ForegroundColor Gray
} catch {
    Write-Log "AppActivate 失败，尝试 SetForegroundWindow" -ForegroundColor Yellow
}

# 方法 2: AttachThreadInput 协助激活
# 获取目标窗口的线程 ID
$targetPid = 0
[NativeMethods.Win32Helper]::GetWindowThreadProcessId($hWnd, [ref]$targetPid)
$currentThreadId = [NativeMethods.Win32Helper]::GetCurrentThreadId()
$targetThreadId = [NativeMethods.Win32Helper]::GetWindowThreadProcessId($hWnd, [ref]$null)

# 挂接到目标线程，然后 SetForegroundWindow
if ($targetThreadId -ne $currentThreadId) {
    [NativeMethods.Win32Helper]::AttachThreadInput($currentThreadId, $targetThreadId, $true)
    [NativeMethods.Win32Helper]::SetForegroundWindow($hWnd)
    [NativeMethods.Win32Helper]::AttachThreadInput($currentThreadId, $targetThreadId, $false)
} else {
    [NativeMethods.Win32Helper]::SetForegroundWindow($hWnd)
}

# 兜底：模拟 Alt 键让窗口接收焦点
[System.Windows.Forms.SendKeys]::SendWait("%")
Start-Sleep -Milliseconds 500
[System.Windows.Forms.SendKeys]::SendWait("%")
Start-Sleep -Seconds 1

# ── 6. 构造输出路径（用于填入文件名框） ──────────────────
# 优先使用 OutputDir，否则用 PDF 所在目录
$outputDirFinal = if ($OutputDir) { $OutputDir } else { $pdfDir }
$outName = if ($OutputName) { $OutputName } else { $pdfName }
$outputFilePath = [System.IO.Path]::Combine($outputDirFinal, "$outName.docx")

# ⬇ 自动重命名：目标文件已存在时自增后缀
$counter = 1
while (Test-Path $outputFilePath) {
    $outputFilePath = [System.IO.Path]::Combine($outputDirFinal, "${outName}_$counter.docx")
    $counter++
}
if ($counter -gt 1) {
    Write-Log "目标文件已存在，自动重命名为: $([System.IO.Path]::GetFileName($outputFilePath))" -ForegroundColor Yellow
}

# 提取最终文件名（不含扩展名）供监听器使用
$outNameFinal = [System.IO.Path]::GetFileNameWithoutExtension($outputFilePath)

# ── 7. 按键序列 ──────────────────────────────────────────
function Send-KeysWithDelay {
    param([string[]]$Keys, [int]$DelayMs = 400)
    foreach ($k in $Keys) {
        Write-Log "  -> 按键: $k" -ForegroundColor Gray
        [System.Windows.Forms.SendKeys]::SendWait($k)
        Start-Sleep -Milliseconds $DelayMs
    }
}

$outputFile = $null

for ($attempt = 1; $attempt -le ($RetryCount + 1); $attempt++) {
    Write-Log "第 $attempt 轮快捷键" -ForegroundColor Cyan

    # 每次重试重新置前
    # 先模拟 Alt 激活菜单栏，确保键盘焦点在福昕
    try {
        [Microsoft.VisualBasic.Interaction]::AppActivate($foxitProc.Id)
    } catch {
        [NativeMethods.Win32Helper]::SetForegroundWindow($hWnd)
    }
    Start-Sleep -Milliseconds 800

    # 先发一个 Alt 激活 Key Tips，再稍等让 UI 就绪
    [System.Windows.Forms.SendKeys]::SendWait("%")
    Start-Sleep -Milliseconds 400

    # 使用带 %（Alt）前缀的组合键更可靠
    Send-KeysWithDelay -Keys @("%b")  -DelayMs 800  # Alt+B: 转换选项卡
    Send-KeysWithDelay -Keys @("d")   -DelayMs 1000 # D: PDF 转 Word
    Send-KeysWithDelay -Keys @("1")   -DelayMs 500  # 1: 页面范围选项
    Send-KeysWithDelay -Keys @("a")   -DelayMs 600  # A: 应用 (焦点移到文件名框)

    # ── 在文件名框输入输出路径 ──────────────────────
    # 此时焦点在文件名输入框上，用剪贴板避免中文/特殊字符问题
    Write-Log "输入输出文件名: $([System.IO.Path]::GetFileName($outputFilePath))" -ForegroundColor Cyan
    try {
        [System.Windows.Forms.Clipboard]::SetText($outputFilePath)
    } catch {
        # 回退：直接设置文本
        Set-Clipboard -Value $outputFilePath -ErrorAction Stop
    }
    Start-Sleep -Milliseconds 300
    Send-KeysWithDelay -Keys @("^(a)") -DelayMs 300  # Ctrl+A: 全选
    Send-KeysWithDelay -Keys @("^(v)") -DelayMs 300  # Ctrl+V: 粘贴完整路径
    Send-KeysWithDelay -Keys @("{ENTER}") -DelayMs 500  # Enter: 确认转换

    Write-Log "等待转换完成..." -ForegroundColor Cyan

    # ── 7. 监听输出文件 ────────────────────────────────
    $watchDirs = @($OutputDir, $pdfDir, [Environment]::GetFolderPath("Desktop")) | Select-Object -Unique
    $elapsed = 0

    while ($elapsed -lt $WaitSeconds) {
        Start-Sleep -Seconds 2
        $elapsed += 2

        foreach ($dir in $watchDirs) {
            if (-not (Test-Path $dir)) { continue }
            $candidate = Get-ChildItem -Path $dir -Filter "$outNameFinal.docx" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if ($candidate -and $candidate.Length -gt 0) {
                $size1 = $candidate.Length
                Start-Sleep -Milliseconds 1000
                $size2 = (Get-Item $candidate.FullName -ErrorAction SilentlyContinue).Length
                if ($size1 -eq $size2 -and $size2 -gt 0) {
                    $outputFile = $candidate.FullName
                    break
                }
            }
        }
        if ($outputFile) { break }

        if ($elapsed % 20 -eq 0) {
            Write-Log "... 等待中 ($elapsed / $WaitSeconds 秒)" -ForegroundColor Gray
        }
    }

    if ($outputFile) { break }

    if ($attempt -le $RetryCount) {
        Write-Log "未检测到输出文件，准备重试 ($attempt / $RetryCount)..." -ForegroundColor Yellow
        Start-Sleep -Seconds 3
    }
}

# ── 9. 结果 ──────────────────────────────────────────────
Write-Host ""
if ($outputFile -and (Test-Path $outputFile)) {
    $sizeKB = (Get-Item $outputFile).Length / 1KB -as [int]
    Write-Host "=== 转换成功 ===" -ForegroundColor Green
    Write-Host "源文件: $PdfPath"
    Write-Host "输出: $outputFile"
    Write-Host "大小: $sizeKB KB"
} else {
    Write-Warning "超时或未检测到输出文件。"
    Write-Warning "可能原因:"
    Write-Warning "  - 快捷键映射因福昕版本不同而有差异"
    Write-Warning "  - 转换对话框需要手动操作"
    Write-Warning "  - 福昕版本未注册，功能受限"
    Write-Host ""
    Write-Host "手动操作: Alt B D 1 A Enter" -ForegroundColor Cyan
}

if ($CloseAfter -and $outputFile) {
    Start-Sleep -Seconds 2
    Stop-Process -Id $foxitProc.Id -Force -ErrorAction SilentlyContinue
    Write-Log "福昕已关闭" -ForegroundColor Gray
}

if ($outputFile) { Write-Output $outputFile }
