$ErrorActionPreference = 'Continue'

# Check if the exe exists
$exe = 'C:\Program Files (x86)\Foxit Software\Foxit_ScreenRecording\FoxitRecordPlus.exe'
if (Test-Path $exe) {
    Write-Host "EXE exists: $exe"
    $fso = (Get-Item $exe).VersionInfo
    Write-Host "File version: $($fso.FileVersion)"
    Write-Host "Company: $($fso.CompanyName)"
    Write-Host "Product: $($fso.ProductName)"
    
    # Check for uninstaller in same dir or parent
    $dir = Split-Path $exe -Parent
    Write-Host "`nContents of: $dir"
    Get-ChildItem -Path $dir | ForEach-Object {
        Write-Host "  $($_.Name) - $($_.Length) bytes"
    }
    
    # Check for unins*.exe
    $uninst = Get-ChildItem -Path $dir -Include 'unins*.exe','uninstall*.exe','*uninstall*' -Recurse -ErrorAction SilentlyContinue
    if ($uninst) {
        Write-Host "`nUninstaller found:"
        $uninst | ForEach-Object { Write-Host "  $($_.FullName)" }
    }
    
    # Check parent dir
    $parent = Split-Path $dir -Parent
    Write-Host "`nContents of parent: $parent"
    Get-ChildItem -Path $parent -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "  $($_.Name)"
    }
    $uninst2 = Get-ChildItem -Path $parent -Include 'unins*.exe','uninstall*.exe','*uninstall*' -Recurse -ErrorAction SilentlyContinue
    if ($uninst2) {
        Write-Host "`nUninstaller in parent:"
        $uninst2 | ForEach-Object { Write-Host "  $($_.FullName)" }
    }
} else {
    Write-Host "EXE not found: $exe"
}

# Check Foxit in other uninstall paths
$morePaths = @(
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
Write-Host "`nSearching uninstall registry keys..."
foreach ($rp in $morePaths) {
    $items = Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue
    foreach ($item in $items) {
        if ($item.DisplayName -and ($item.DisplayName -match 'Foxit|Screen.*Record|å½•å±')) {
            Write-Host "  Path: $rp"
            Write-Host "  Name: $($item.DisplayName)"
            Write-Host "  Uninstall: $($item.UninstallString)"
            Write-Host "  ---"
        }
    }
}

# Check Windows Apps (Store apps)
Write-Host "`nChecking WindowsApps..."
Get-AppxPackage -Name '*Foxit*' -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  Name: $($_.Name)"
    Write-Host "  Version: $($_.Version)"
    Write-Host "  InstallLocation: $($_.InstallLocation)"
    Write-Host "  ---"
}
