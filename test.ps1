# Запускать строго от Администратора
$ErrorActionPreference = "SilentlyContinue"

# Твой список сигнатур
$sigs = @(
    "!2023/07/03:22:01:11!0!",
    "2023/05/09:19 10 04",
    "2024/04/05",
    "2021/11/29:17:36:29",
    "2022/07/06:20:23:42",
    "2024/08/14:18:46:25",
    "2023/06/06:06:27:09",
    "2024/03/15:02 10 26",
    "2024/05/31:21:46:54"
)

$pd64 = "$env:TEMP\procdump64.exe"
$dumpFile = "$env:TEMP\dps_final.dmp"

if (!(Test-Path $pd64)) {
    Write-Host "[*] Загрузка ProcDump64..." -ForegroundColor Gray
    Invoke-WebRequest -Uri "https://live.sysinternals.com/procdump64.exe" -OutFile $pd64 -UseBasicParsing
}

$pid = (Get-WmiObject Win32_Service | Where-Object { $_.Name -eq "DPS" }).ProcessId
if (!$pid) { Write-Host "[-] Служба DPS не найдена!" -ForegroundColor Red; exit }

Write-Host "[>>>] Создание дампа DPS (PID: $pid)..." -ForegroundColor Cyan
& $pd64 -ma $pid $dumpFile -accepteula -nobanner

if (!(Test-Path $dumpFile)) { Write-Host "[-] Ошибка: Дамп не был создан." -ForegroundColor Red; exit }

Write-Host "[*] Чтение данных памяти..." -ForegroundColor Gray
$bytes = [System.IO.File]::ReadAllBytes($dumpFile)

# Декодируем один раз для экономии ресурсов
$methods = @{
    "Unicode" = [System.Text.Encoding]::Unicode.GetString($bytes)
    "ASCII"   = [System.Text.Encoding]::ASCII.GetString($bytes)
}

Write-Host "[*] Поиск сигнатур..." -ForegroundColor Gray
$foundList = @()

foreach ($s in $sigs) {
    # Сохраняем оригинальный вид для вывода, но чистим для поиска
    $cleanSig = $s.Trim('!')
    if ($cleanSig.EndsWith("!0!")) { $cleanSig = $cleanSig.Replace("!0!", "") }

    foreach ($method in $methods.Keys) {
        if ($methods[$method].Contains($cleanSig)) {
            Write-Host "[!!!] НАЙДЕНО: $s" -ForegroundColor Red -BackgroundColor Black
            $foundList += $s
            break # Нашли в одной кодировке, переходим к следующей сигнатуре
        }
    }
}

# Очистка
Remove-Item $dumpFile -Force

# Итоговый отчет
Write-Host "`n--- ИТОГО ---" -ForegroundColor Cyan
if ($foundList.Count -gt 0) {
    Write-Host "Обнаружено совпадений: $($foundList.Count)" -ForegroundColor Red
    foreach ($item in $foundList) {
        Write-Host " [+] $item" -ForegroundColor Red
    }
} else {
    Write-Host "Ни одной сигнатуры не обнаружено." -ForegroundColor Green
}

Write-Host "`n[+] Проверка завершена." -ForegroundColor Cyan
