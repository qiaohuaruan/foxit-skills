# 下载福昕录屏安装程序
$url = 'https://file.foxitreader.cn/file/Channel/foxitrec/foxitrec-seoB.exe'
$out = "$env:TEMP\foxitrec-installer.exe"

if (Test-Path $out) {
    $size = [math]::Round((Get-Item $out).Length / 1MB, 1)
    Write-Host "已存在: $out (${size} MB)"
    exit 0
}

Write-Host "正在下载福昕录屏安装程序 (~66MB)..."
try {
    Start-BitsTransfer -Source $url -Destination $out -DisplayName "福昕录屏" -ErrorAction Stop
}
catch {
    Write-Host "BITS 失败，改用 Invoke-WebRequest..."
    Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
}

if (Test-Path $out) {
    $size = [math]::Round((Get-Item $out).Length / 1MB, 1)
    Write-Host "下载成功! ${size} MB -> $out"
} else {
    Write-Host "下载失败"
    exit 1
}
