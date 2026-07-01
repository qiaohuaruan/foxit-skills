$ErrorActionPreference = 'Continue'

$paths = @(
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

foreach ($p in $paths) {
    $items = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
    foreach ($item in $items) {
        if ($item.DisplayName -match 'Foxit') {
            Write-Host "Name: $($item.DisplayName)"
            Write-Host "UninstallString: $($item.UninstallString)"
            Write-Host "InstallLocation: $($item.InstallLocation)"
            Write-Host "---"
        }
    }
}
