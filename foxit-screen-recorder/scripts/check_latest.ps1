$f = Get-ChildItem -Path 'C:\Foxit_ScreenRecording' -Filter '*.mp4' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($f) {
    $sz = [math]::Round($f.Length / 1MB, 1)
    Write-Host "Latest: $($f.Name) - $sz MB - $($f.LastWriteTime)"
} else {
    Write-Host "No MP4 found"
}
