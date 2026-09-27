# Windows-side helper. Run from PowerShell on your PC, not the VPS.
#
#   powershell -ExecutionPolicy Bypass -File connect.ps1
#   powershell -ExecutionPolicy Bypass -File connect.ps1 -VpsHost 185.223.252.137

param(
    [string]$VpsHostIp = "185.223.252.137",
    [int]$Port = 5555,
    [int]$MaxSize = 1024,
    [int]$BitRate = 4000000,
    [int]$MaxFps = 30
)

$ErrorActionPreference = "Stop"

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

# A wedged adb.exe on Windows produces "actively refused" on 127.0.0.1:5037
# even when the VPS is fine. Force-kill it first.
Step "Clearing any wedged local adb"
Get-Process adb -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

Step "Starting local adb server"
adb start-server | Out-Null
adb devices

Step "Connecting to $VpsHostIp`:$Port"
adb disconnect | Out-Null
Start-Sleep -Seconds 1

# The host may still be finishing its first boot. Retry rather than fail once.
$ok = $false
for ($i = 1; $i -le 5; $i++) {
    $out = adb connect "${VpsHostIp}:$Port" 2>&1
    Write-Host "  attempt $i : $out"
    if ("$out" -match "connected to") { $ok = $true; break }
    Start-Sleep -Seconds 6
}

if (-not $ok) {
    Write-Host "`nStill refusing. On the VPS run:" -ForegroundColor Yellow
    Write-Host "  docker ps -a                       # is the container Up?"
    Write-Host "  ss -tlnp | grep 5555              # is anything listening?"
    Write-Host "  docker logs --tail 30 redroid_google_instance"
    Write-Host "  bash ~/redroid-gapps/01-build-and-boot.sh   # full rebuild"
    exit 1
}

# "connected to" only means the TCP socket opened. adbd can still be
# mid-boot, in which case the device enumerates as "offline".
Step "Waiting for the device to finish booting"
$state = ""
for ($i = 1; $i -le 30; $i++) {
    $line = adb devices | Select-String "device$"
    if ($line) { $state = "device"; break }
    Start-Sleep -Seconds 4
}

if ($state -ne "device") {
    Write-Host "`nTCP is up but adbd is still offline." -ForegroundColor Yellow
    Write-Host "This is the container still initialising, or a boot-loop." -ForegroundColor Yellow
    Write-Host "On the VPS:  docker logs --tail 50 redroid_google_instance" -ForegroundColor Yellow
    exit 1
}

Step "Confirming Play Services is present"
$gms = adb shell pm path com.google.android.gms 2>&1
if ("$gms" -match "package:") {
    Write-Host "  Play Services: INSTALLED" -ForegroundColor Green
    adb shell dumpsys package com.google.android.gms |
        Select-String -Pattern "versionName" | Select-Object -First 1
} else {
    Write-Host "  Play Services: NOT FOUND - the image build did not land." -ForegroundColor Red
    Write-Host "  Re-run 01-build-and-boot.sh on the VPS." -ForegroundColor Red
}

Step "Launching scrcpy"
Write-Host "In the window: swipe up for the app drawer, then" -ForegroundColor DarkGray
Write-Host "Settings > Accounts > Add account > Google" -ForegroundColor DarkGray

scrcpy --tcpip="${VpsHostIp}:$Port" --max-fps=$MaxFps --max-size=$MaxSize --video-bit-rate=$BitRate --no-audio
