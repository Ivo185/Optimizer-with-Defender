# Optimizer_with_Defender_x86.ps1
# 32-битова версия — автоматично се рестартира в 32-bit PowerShell (SysWOW64)
# ------------------------------------------------------------

# 1. РЕСТАРТ В 32-БИТ (ако е нужно)
if ([IntPtr]::Size -ne 4) {
    $syswow = "$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path $syswow) {
        Write-Host "[x86] Рестартиране в 32-битов PowerShell..." -ForegroundColor Magenta
        & $syswow -NoProfile -ExecutionPolicy Bypass -File "$PSCommandPath"
        exit
    }
}

# 2. АДМИНИСТРАТОРСКИ ПРАВА
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $syswow = "$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
    $exe = if (Test-Path $syswow) { $syswow } else { "powershell.exe" }
    Start-Process $exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Set-Location $PSScriptRoot

# 3. ЕЗИКОВА СИСТЕМА И ИЗХОД
function Get-Localization {
    Clear-Host
    Write-Host "1. Български (Bulgarian)"
    Write-Host "2. English"
    Write-Host "0. Изход (Exit)"
    $choice = Read-Host "Избор / Choice"
    
    if ($choice -eq "0") { exit }
    
    $lang = @{}
    if ($choice -eq "1") {
        $lang.Title = "ПАРАМЕТРИ ЗА ОПТИМИЗАЦИЯ (x86)"
        $lang.LogQ = "1. Искате ли да се създава log файл? (Y/N)"
        $lang.LogLevelQ = "   - Ниво на детайлност: [1] Само сумарно | [2] Всеки изтрит файл"
        $lang.ScanQ = "2. Стартиране на пълно сканиране с Microsoft Defender? (Y/N)"
        $lang.RestartQ = "3. Рестарт на explorer.exe накрая? (Y/N)"
        $lang.WinSxSQ = "4. Оптимизация на WinSxS (бавно)? (Y/N)"
        $lang.SmartQ = "5. Smart Scan за остатъчни папки? (Y/N)"
        $lang.Scanning = "Стартиране на пълно антивирусно сканиране... (Може да отнеме време)"
        $lang.ScanDone = "Антивирусното сканиране приключи."
        $lang.Working = "Започва почистването на файлове..."
        $lang.Found = "Намерена възможна излишна папка:"
        $lang.Prompt = "Желаете ли да я изтриете? (Y/N)"
        $lang.Total = "Вие освободихте ОБЩО"
        $lang.Duration = "Време за изпълнение"
        $lang.Done = "Готово! Прозорецът ще остане отворен."
        $lang.LogFolder = "Папка [{0}] - Освободени: {1} MB"
        $lang.LogSmartTotal = "Остатъци от приложения: Освободени {0} MB"
        $lang.Checking = "Проверка на {0}..."
        $lang.OK = " Готово!"
        $lang.UserTemp = "Потребителски Temp"
        $lang.WinTemp = "Системен Temp"
        $lang.Prefetch = "Prefetch кеш"
        $lang.Bin = "Кошчето"
        $lang.Wow64 = "SysWOW64 Temp (32-bit)"
    } else {
        $lang.Title = "OPTIMIZATION PARAMETERS (x86)"
        $lang.LogQ = "1. Create log file? (Y/N)"
        $lang.LogLevelQ = "   - Detail level: [1] Summary only | [2] Every deleted file"
        $lang.ScanQ = "2. Run Full Microsoft Defender Scan? (Y/N)"
        $lang.RestartQ = "3. Restart explorer.exe at the end? (Y/N)"
        $lang.WinSxSQ = "4. WinSxS Optimization (slow)? (Y/N)"
        $lang.SmartQ = "5. Smart Scan for leftover folders? (Y/N)"
        $lang.Scanning = "Starting Full Virus Scan... (This may take a while)"
        $lang.ScanDone = "Virus scan completed."
        $lang.Working = "Starting file cleanup..."
        $lang.Found = "Potential leftover folder found:"
        $lang.Prompt = "Do you want to delete it? (Y/N)"
        $lang.Total = "Total space freed"
        $lang.Duration = "Time taken"
        $lang.Done = "Done! The window will stay open."
        $lang.LogFolder = "Folder [{0}] - Freed: {1} MB"
        $lang.LogSmartTotal = "App leftovers: Freed {0} MB"
        $lang.Checking = "Checking {0}..."
        $lang.OK = " OK!"
        $lang.UserTemp = "User Temp"
        $lang.WinTemp = "Win Temp"
        $lang.Prefetch = "Prefetch"
        $lang.Bin = "Recycle Bin"
        $lang.Wow64 = "SysWOW64 Temp (32-bit)"
    }
    return $lang
}

$msg = Get-Localization

Write-Host "Архитектура: x86 (32-bit режим)" -ForegroundColor Magenta

# 4. ПОМОЩНИ ФУНКЦИИ
function Get-FreeSpace {
    $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
    return [double]$disk.FreeSpace
}

$global:totalFreed = 0.0
$global:logPath = Join-Path $PSScriptRoot "Optimization_Report_x86.txt"

# 5. МЕНЮ С ВЪПРОСИ
Write-Host "`n=== $($msg.Title) ===" -ForegroundColor Cyan
$global:doLog = (Read-Host $msg.LogQ) -match "^[Yy]$"
if ($global:doLog) { $global:logLv = Read-Host $msg.LogLevelQ }
$global:doScan = (Read-Host $msg.ScanQ) -match "^[Yy]$"
$global:doRest = (Read-Host $msg.RestartQ) -match "^[Yy]$"
$global:doSxS = (Read-Host $msg.WinSxSQ) -match "^[Yy]$"
$global:doSmart = (Read-Host $msg.SmartQ) -match "^[Yy]$"

# 6. ТОЧКА ЗА ВЪЗСТАНОВЯВАНЕ
Write-Progress -Activity "System" -Status "Creating Restore Point" -PercentComplete 5
Checkpoint-Computer -Description "PC_Optimizer_x86_Point" -RestorePointType "MODIFY_SETTINGS" -ErrorAction SilentlyContinue

$sw = [System.Diagnostics.Stopwatch]::StartNew()
if ($global:doLog) { Add-Content $global:logPath -Value "`n--- START (x86): $(Get-Date) ---" }

# 7. АНТИВИРУСНО СКАНИРАНЕ
if ($global:doScan) {
    Write-Host "`n[!] $($msg.Scanning)" -ForegroundColor Yellow
    if ($global:doLog) { Add-Content $global:logPath -Value "Defender Scan: Started at $(Get-Date)" }
    try {
        Start-MpScan -ScanType FullScan -ErrorAction Stop
        Write-Host $msg.ScanDone -ForegroundColor Green
        if ($global:doLog) { Add-Content $global:logPath -Value "Defender Scan: Finished at $(Get-Date)" }
    } catch {
        Write-Host "Внимание: Вече има активно сканиране на заден фон. Тази стъпка се прескача." -ForegroundColor Yellow
        if ($global:doLog) { Add-Content $global:logPath -Value "Defender Scan: Skipped (Already in progress or error)" }
    }
}

# 8. ПОЧИСТВАЩА ЛОГИКА
function Clean-Target {
    param([string]$Path, [string]$Name)
    $before = Get-FreeSpace
    Write-Host ($msg.Checking -f $Name) -NoNewline
    
    if (Test-Path $Path) {
        $items = Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue
        foreach ($i in $items) {
            if ($global:doLog -and $global:logLv -eq "2") {
                Add-Content $global:logPath -Value "DEL: $($i.FullName)"
            }
            Remove-Item $i.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    $after = Get-FreeSpace
    $freedThisFolder = [math]::Max(0, ($after - $before) / 1MB)
    $global:totalFreed += $freedThisFolder
    
    if ($global:doLog) {
        $logMsg = $msg.LogFolder -f $Name, $freedThisFolder.ToString("N2")
        Add-Content $global:logPath -Value $logMsg
    }
    Write-Host $msg.OK -ForegroundColor Green
}

Write-Host "`n$($msg.Working)" -ForegroundColor Cyan

Clean-Target -Path $env:TEMP -Name $msg.UserTemp
Clean-Target -Path "C:\Windows\Temp" -Name $msg.WinTemp
Clean-Target -Path "C:\Windows\Prefetch" -Name $msg.Prefetch

# x86 СПЕЦИФИЧНО: Почистване на SysWOW64 временни файлове
$wow64Temp = "C:\Windows\SysWOW64\config\systemprofile\AppData\Local\Temp"
Clean-Target -Path $wow64Temp -Name $msg.Wow64

# Кошче
Write-Host ($msg.Checking -f $msg.Bin) -NoNewline
$bBin = Get-FreeSpace
Clear-RecycleBin -Force -ErrorAction SilentlyContinue
$freedBin = [math]::Max(0, (Get-FreeSpace) - $bBin) / 1MB
$global:totalFreed += $freedBin
Write-Host " OK!" -ForegroundColor Green

if ($global:doLog) {
    $logMsg = $msg.LogFolder -f $msg.Bin, $freedBin.ToString("N2")
    Add-Content $global:logPath -Value $logMsg
}

# WinSxS
if ($global:doSxS) {
    Write-Progress -Activity "Cleanup" -Status "Optimizing WinSxS" -PercentComplete 80
    DISM.exe /online /Cleanup-Image /StartComponentCleanup /Quiet
}

# SMART SCANNER
if ($global:doSmart) {
    $smartTotalFreed = 0.0 
    $whitelist = @("Microsoft","Windows","Common Files","NVIDIA","Intel","AMD","Google","Steam","Epic Games","Windows Defender","Windows Defender Advanced Threat Protection","Windows Mail","Windows Media Player","Windows NT","WindowsPowerShell","Windows Photo Viewer","WindowsApps","Internet Explorer","Microsoft.NET","Dolby","Package Cache","Microsoft DevDiv","K7F0O","ssh","USOPrivate","USOShared","Whesvc",".IdentityService","Backup","Packages","pip","Programs","speech","ConnectedDevicesPlatform","CEF","Microsoft_Corporation","Microsoft Office 15","ModifiableWindowsApps","Lenovo","D3DSCache","PackageManagement","Temp")
    
    $apps = Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object -ExpandProperty DisplayName -ErrorAction SilentlyContinue
    # x86: включваме и Program Files (x86) като основен път
    $paths = @("C:\Program Files", "C:\Program Files (x86)", "C:\ProgramData", "$env:AppData")
    
    foreach ($p in $paths) {
        if (Test-Path $p) {
            Get-ChildItem $p -Directory | ForEach-Object {
                $f = $_
                if ($whitelist -contains $f.Name) { return }
                $match = $apps | Where-Object { $_ -like "*$($f.Name)*" }
                
                if (-not $match) {
                    Write-Host "`n[?] $($msg.Found) $($f.FullName)" -ForegroundColor Cyan
                    if ((Read-Host $msg.Prompt) -match "^[Yy]$") {
                        $b = Get-FreeSpace
                        Remove-Item $f.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        $freed = [math]::Max(0, ((Get-FreeSpace) - $b) / 1MB)
                        $global:totalFreed += $freed
                        $smartTotalFreed += $freed
                        if ($global:doLog) { 
                            Add-Content $global:logPath -Value "SMART SCAN DELETE: $($f.FullName) [$($freed.ToString('N2')) MB]" 
                        }
                    }
                }
            }
        }
    }
    if ($global:doLog -and $smartTotalFreed -gt 0) {
        $logMsg = $msg.LogSmartTotal -f $smartTotalFreed.ToString("N2")
        Add-Content $global:logPath -Value $logMsg
    }
}

$sw.Stop()
$time = "{0:00}h {1:00}m {2:00}s" -f $sw.Elapsed.Hours, $sw.Elapsed.Minutes, $sw.Elapsed.Seconds

# 9. ФИНАЛЕН ОТЧЕТ
Write-Host "`n========================================"
Write-Host "$($msg.Total): $($global:totalFreed.ToString('N2')) MB" -ForegroundColor Red
Write-Host "$($msg.Duration): $time" -ForegroundColor Yellow
Write-Host "Режим: 32-bit (x86)" -ForegroundColor Magenta
Write-Host "========================================"

if ($global:doLog) {
    Add-Content $global:logPath -Value "--- END (x86): $(Get-Date) ---"
    Add-Content $global:logPath -Value "Duration: $time | Total Freed: $($global:totalFreed.ToString('N2')) MB | Mode: x86"
}

[System.Console]::Beep(440, 500)
if ($global:doRest) { Stop-Process -Name explorer -Force; Start-Process explorer.exe }

Write-Host "`n$($msg.Done)"
pause
