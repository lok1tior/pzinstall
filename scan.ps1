# Диагностика файлов Project Zomboid. Скрипт только читает данные и ничего не удаляет.
# Запуск: irm https://raw.githubusercontent.com/lok1tior/pzinstall/refs/heads/main/scan.ps1 | iex

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$CollectionId = '3831950228'

function Get-Bytes([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return [int64]0 }
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { return [int64]0 }
    return [int64]$sum
}
function Fmt([int64]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N2} ГБ' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} МБ' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} КБ' -f ($Bytes / 1KB)) }
    return "$Bytes Б"
}
function Row([string]$Name, [int64]$Bytes, [string]$Note = '') {
    Write-Host ('  {0,-48} {1,12}   {2}' -f $Name, (Fmt $Bytes), $Note)
}
function Head([string]$Title) { Write-Host "`n=== $Title ===" -ForegroundColor Cyan }
function Get-SteamLibraries {
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam').SteamPath
    $paths = @($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        $paths += Select-String -LiteralPath $vdf -Pattern '"path"\s+"(.+)"' |
            ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' }
    }
    $seen = @{}
    foreach ($p in $paths) {
        if (-not $p) { continue }
        $full = [IO.Path]::GetFullPath($p).TrimEnd('\')
        if (-not $seen.ContainsKey($full)) { $seen[$full] = $true; $full }
    }
}

try {
    Write-Host 'Считаю размеры файлов, подожди немного...' -ForegroundColor Gray
    $libs = @(Get-SteamLibraries)
    $total = [int64]0; $gameBytes = [int64]0; $workshopBytes = [int64]0
    $gameInstalled = $false; $workshopItems = @()
    Head 'Steam: файлы Project Zomboid по библиотекам'
    foreach ($lib in $libs) {
        $sa = Join-Path $lib 'steamapps'
        $installed = Test-Path -LiteralPath (Join-Path $sa 'appmanifest_108600.acf')
        $gamePath = Join-Path $sa 'common\ProjectZomboid'
        $wsPath = Join-Path $sa 'workshop\content\108600'
        $g = Get-Bytes $gamePath; $w = Get-Bytes $wsPath
        $wd = Get-Bytes (Join-Path $sa 'workshop\downloads\108600')
        $dl = Get-Bytes (Join-Path $sa 'downloading\108600')
        $sc = Get-Bytes (Join-Path $sa 'shadercache\108600')
        if (($g + $w + $wd + $dl + $sc) -eq 0 -and -not $installed) { continue }
        Write-Host "`nБиблиотека: $lib" -ForegroundColor White
        if ($installed) { $gameInstalled = $true; Row 'Папка игры: всего' $g 'установлена' }
        elseif ($g -gt 0) { Row 'Папка игры: всего' $g 'остатки после удаления' }
        if ($g -gt 0) {
            Get-ChildItem -LiteralPath $gamePath -Force -ErrorAction SilentlyContinue |
                ForEach-Object { Row ("  Игра\" + $_.Name) (Get-Bytes $_.FullName) $(if ($_.PSIsContainer) { 'папка' } else { 'файл' }) }
        }
        Row 'Воркшоп: загруженные моды (content\108600)' $w
        if ($wd -gt 0) { Row 'Воркшоп: незавершённые загрузки' $wd }
        if ($dl -gt 0) { Row 'Игра: незавершённые загрузки' $dl }
        if ($sc -gt 0) { Row 'Кэш шейдеров' $sc }
        $gameBytes += $g; $workshopBytes += $w
        $total += $g + $w + $wd + $dl + $sc
        if (Test-Path -LiteralPath $wsPath) { $workshopItems += Get-ChildItem -LiteralPath $wsPath -Directory -ErrorAction SilentlyContinue }
    }

    $zPath = Join-Path $env:USERPROFILE 'Zomboid'; $zBytes = Get-Bytes $zPath; $total += $zBytes
    Head "Папка пользователя: $zPath (всего $(Fmt $zBytes))"
    if (Test-Path -LiteralPath $zPath) {
        Get-ChildItem -LiteralPath $zPath -Directory -Force -ErrorAction SilentlyContinue |
            ForEach-Object { Row $_.Name (Get-Bytes $_.FullName) }
    } else { Write-Host '  Папки нет.' -ForegroundColor Green }

    $savesPath = Join-Path $zPath 'Saves'
    if (Test-Path -LiteralPath $savesPath) {
        Head 'Сохранения: крупнейшие миры'
        Get-ChildItem -LiteralPath $savesPath -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Name -eq 'Multiplayer') {
                Get-ChildItem -LiteralPath $_.FullName -Directory -Force -ErrorAction SilentlyContinue |
                    ForEach-Object { [pscustomobject]@{Name=('MP\' + $_.Name); Bytes=(Get-Bytes $_.FullName)} }
            } else {
                Get-ChildItem -LiteralPath $_.FullName -Directory -Force -ErrorAction SilentlyContinue |
                    ForEach-Object { [pscustomobject]@{Name=($_.Parent.Name + '\' + $_.Name); Bytes=(Get-Bytes $_.FullName)} }
            }
        } | Sort-Object Bytes -Descending | Select-Object -First 15 | ForEach-Object { Row $_.Name $_.Bytes }
    }

    if ($workshopItems.Count -gt 0) {
        $list = foreach ($d in $workshopItems) {
            $mi = Get-ChildItem -LiteralPath $d.FullName -Recurse -Depth 4 -Filter mod.info -File -ErrorAction SilentlyContinue | Select-Object -First 1
            $name = ''
            if ($mi) {
                $line = Get-Content -LiteralPath $mi.FullName -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*name\s*=' } | Select-Object -First 1
                if ($line) { $name = ($line -replace '^\s*name\s*=\s*', '').Trim() }
            }
            [pscustomobject]@{ Id=$d.Name; Name=$name; Bytes=(Get-Bytes $d.FullName) }
        }
        $listedBytes = [int64](($list | Measure-Object Bytes -Sum).Sum)
        Head "Воркшоп: $($list.Count) папок, сумма по модам $(Fmt $listedBytes); всего в библиотеках $(Fmt $workshopBytes)"
        $list | Sort-Object Bytes -Descending | Select-Object -First 30 | ForEach-Object {
            $n = if ($_.Name) { $_.Name } else { '(имя не найдено)' }
            Row ("{0} [{1}]" -f $n, $_.Id) $_.Bytes
        }
        if ($listedBytes -ne $workshopBytes) {
            Write-Host "  Примечание: разница $(Fmt ([math]::Abs($listedBytes - $workshopBytes))) может быть из-за файлов вне папок-модов либо повторяющихся ID в разных библиотеках." -ForegroundColor Yellow
        }
    }

    Head 'ИТОГО'
    Row 'Сумма учтённых файлов PZ (Steam + Zomboid)' $total
    Write-Host 'Размеры — сумма логических размеров файлов; некоторые системные/защищённые файлы могут не читаться.' -ForegroundColor Gray
    if (-not $gameInstalled -and ($gameBytes + $workshopBytes) -gt 0) { Write-Host 'Игра не установлена, но её файлы или моды остались.' -ForegroundColor Yellow }
    Write-Host 'Скрипт ничего не изменял и не удалял. Для очистки есть cleanup.ps1.'
} catch { Write-Host "ОШИБКА: $($_.Exception.Message)" -ForegroundColor Red }
