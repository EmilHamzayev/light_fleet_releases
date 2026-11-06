# Обновление бота LIGHT до последней версии (один раз вручную; дальше бот обновляется сам).
# Запуск в PowerShell "от имени администратора":
#   irm https://raw.githubusercontent.com/EmilHamzayev/light_fleet_releases/main/update_bot.ps1 -OutFile $env:TEMP\update_bot.ps1; powershell -ExecutionPolicy Bypass -File $env:TEMP\update_bot.ps1
# Не трогает: .env, google_service_account.json, .venv, logs, service\nssm.exe.
param([string]$Dir = "", [switch]$Test)
$ErrorActionPreference = "Stop"
$Name = "LightFleetBot"
$Base = "https://raw.githubusercontent.com/EmilHamzayev/light_fleet_releases/main/"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Fail($msg) { Write-Host "ОШИБКА: $msg" -ForegroundColor Red; exit 1 }

if (-not $Test) {
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $admin) { Fail "Запустите PowerShell от имени администратора." }
}
if (-not $Dir) {
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name\Parameters"
    if (-not (Test-Path $key)) { Fail "Служба $Name не найдена. Укажите папку бота: -Dir C:\LightFleetBot" }
    $Dir = (Get-ItemProperty $key).AppDirectory
}
if (-not (Test-Path (Join-Path $Dir "fleetbot"))) { Fail "В папке $Dir нет бота (нет fleetbot)." }
if (Test-Path (Join-Path $Dir ".git")) { Fail "$Dir - папка разработки, тут обновлять нельзя." }
Write-Host "Папка бота: $Dir"

$m = Invoke-RestMethod ($Base + "version.json") -Headers @{"Cache-Control" = "no-cache"}
$file = $m.bot.file
Write-Host "Последняя версия: $($m.version) ($file)"
$tmp = Join-Path $env:TEMP ("lightfleet_bot_" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force $tmp | Out-Null
$zip = Join-Path $tmp $file
Invoke-WebRequest ($Base + $file) -OutFile $zip -UseBasicParsing
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
if ($hash -ne $m.bot.sha256) { Fail "Контрольная сумма архива не совпадает - файл не установлен." }
Expand-Archive $zip -DestinationPath $tmp -Force
$src = Join-Path $tmp "LightFleetBot"
if (-not (Test-Path (Join-Path $src "fleetbot\__main__.py"))) { Fail "Архив неполный." }
foreach ($secret in @(".env", "google_service_account.json")) {
    if (Test-Path (Join-Path $src $secret)) { Remove-Item (Join-Path $src $secret) -Force }
}

if (-not $Test) {
    Write-Host "Останавливаю службу $Name..."
    Stop-Service $Name -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}
Copy-Item (Join-Path $src "*") $Dir -Recurse -Force
Write-Host "Файлы заменены."

$py = Join-Path $Dir ".venv\Scripts\python.exe"
if (-not $Test) {
    if (-not (Test-Path $py)) { Fail "Нет $py - запустите service\setup_bot_pc.ps1." }
    Write-Host "Ставлю библиотеки (может занять минуту)..."
    & $py -m pip install -q -r (Join-Path $Dir "requirements-bot.txt")
    if ($LASTEXITCODE -ne 0) { Write-Host "pip завершился с ошибкой - бот может не запуститься." -ForegroundColor Yellow }
}
$logs = Join-Path $Dir "logs"
New-Item -ItemType Directory -Force $logs | Out-Null
[IO.File]::WriteAllText((Join-Path $logs "updated.json"), "{""version"": ""$($m.version)""}", (New-Object Text.UTF8Encoding $false))
Remove-Item $tmp -Recurse -Force

if (-not $Test) {
    Start-Service $Name
    Start-Sleep -Seconds 5
    Get-Service $Name | Format-Table -AutoSize Status, Name
}
Write-Host "Готово: бот обновлён до $($m.version). В Telegram придёт «Bot zaktualizowany do $($m.version)»." -ForegroundColor Green
