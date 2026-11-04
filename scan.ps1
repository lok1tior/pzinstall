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
    $gameInstalled = $false; $workshopItems = @(); $spaceItems = @()
    Head 'Steam: файлы Project Zomboid по библиотекам'
    foreach ($lib in $libs) {
        $sa = Join-Path $lib 'steamapps'
        $installed = Test-Path -LiteralPath (Join-Path $sa 'appmanifest_108600.acf')
        $gamePath = Join-Path $sa 'common\ProjectZomboid'
        $wsPath = Join-Path $sa 'workshop\content\108600'
        $w = Get-Bytes $wsPath
        # В папке игры есть отдельное хранилище модов для локального сервера.
        # Не включаем его в размер файлов игры, иначе один и тот же серверный
        # кэш выглядит как часть самой установки PZ.
        $gameEntries = @(Get-ChildItem -LiteralPath $gamePath -Force -ErrorAction SilentlyContinue)
        $gameBreakdown = foreach ($entry in $gameEntries) {
            if ($entry.Name -ine 'steamapps') {
                $b = Get-Bytes $entry.FullName
                $why = switch -Regex ($entry.Name) {
                    '^media$' { 'Основные игровые ресурсы: карты, графика, звук и другие файлы игры; нужны для работы игры.'; break }
                    '^jre64$' { 'Среда Java, используемая игрой.'; break }
                    '^mods$' { 'Моды, установленные прямо в папку игры.'; break }
                    default { 'Файлы установленной игры.' }
                }
                [pscustomobject]@{ Name=('Игра\' + $entry.Name); Bytes=$b; Why=$why }
            }
        }
        [int64]$g = ($gameBreakdown | Measure-Object -Property Bytes -Sum).Sum
        foreach ($item in $gameBreakdown) { $spaceItems += $item }
        $serverSteamApps = Join-Path $gamePath 'steamapps'
        $serverWorkshop = Join-Path $serverSteamApps 'workshop'
        $serverContent = Join-Path $serverWorkshop 'content\108600'
        $serverWorkshopBytes = Get-Bytes $serverContent
        $serverDownloadsBytes = Get-Bytes (Join-Path $serverWorkshop 'downloads')
        $serverTempBytes = Get-Bytes (Join-Path $serverWorkshop 'temp')
        $serverStorageBytes = Get-Bytes $serverSteamApps
        $serverOtherBytes = $serverStorageBytes - $serverWorkshopBytes - $serverDownloadsBytes - $serverTempBytes
        if ($serverOtherBytes -lt 0) { $serverOtherBytes = 0 }
        if ($serverWorkshopBytes -gt 0) {
            $spaceItems += [pscustomobject]@{Name='Серверный кэш модов'; Bytes=$serverWorkshopBytes; Why='Отдельная копия Workshop-модов для локального хостинга. При следующем хостинге нужные серверу моды могут скачаться снова.'}
        }
        if ($serverOtherBytes -gt 0) {
            $spaceItems += [pscustomobject]@{Name='Прочие данные серверного Workshop'; Bytes=$serverOtherBytes; Why='Манифест и служебные файлы сервера.'}
        }
        $wd = Get-Bytes (Join-Path $sa 'workshop\downloads\108600')
        $dl = Get-Bytes (Join-Path $sa 'downloading\108600')
        $sc = Get-Bytes (Join-Path $sa 'shadercache\108600')
        if (($g + $w + $wd + $dl + $sc) -eq 0 -and -not $installed) { continue }
        Write-Host "`nБиблиотека: $lib" -ForegroundColor White
        if ($installed) { $gameInstalled = $true; Row 'Папка игры: всего' $g 'установлена' }
        elseif ($g -gt 0) { Row 'Папка игры: всего' $g 'остатки после удаления' }
        if ($g -gt 0) {
            Row 'Файлы игры (без серверного кэша)' $g
            $gameEntries | Where-Object { $_.Name -ine 'steamapps' } |
                ForEach-Object { Row ("  Игра\" + $_.Name) (Get-Bytes $_.FullName) $(if ($_.PSIsContainer) { 'папка' } else { 'файл' }) }
        }
        if ($serverWorkshopBytes -gt 0) {
            Row 'Копия воркшоп-модов для хостинга' $serverWorkshopBytes 'Project Zomboid server cache; отдельна от обычного Steam Workshop'
            if ($serverDownloadsBytes -gt 0) { Row '  Сервер: незавершённые загрузки' $serverDownloadsBytes }
            if ($serverTempBytes -gt 0) { Row '  Сервер: временные файлы' $serverTempBytes }
            if ($serverOtherBytes -gt 0) { Row '  Сервер: манифест и прочие файлы' $serverOtherBytes }
        } elseif ($serverStorageBytes -gt 0) {
            Row 'Данные server steamapps внутри папки игры' $serverStorageBytes
        }
        Row 'Воркшоп: загруженные моды (content\108600)' $w
        if ($wd -gt 0) { Row 'Воркшоп: незавершённые загрузки' $wd; $spaceItems += [pscustomobject]@{Name='Незавершённые загрузки Workshop'; Bytes=$wd; Why='Временные данные загрузки модов через Steam.'} }
        if ($dl -gt 0) { Row 'Игра: незавершённые загрузки' $dl; $spaceItems += [pscustomobject]@{Name='Незавершённые загрузки игры'; Bytes=$dl; Why='Временные данные загрузки/обновления игры через Steam.'} }
        if ($sc -gt 0) { Row 'Кэш шейдеров' $sc; $spaceItems += [pscustomobject]@{Name='Кэш шейдеров'; Bytes=$sc; Why='Временный кэш графики; Steam или игра создадут его снова при необходимости.'} }
        $gameBytes += $g; $workshopBytes += $w
        $total += $g + $serverStorageBytes + $w + $wd + $dl + $sc
        if (Test-Path -LiteralPath $wsPath) { $workshopItems += Get-ChildItem -LiteralPath $wsPath -Directory -ErrorAction SilentlyContinue }
    }

    $zPath = Join-Path $env:USERPROFILE 'Zomboid'; $zBytes = Get-Bytes $zPath; $total += $zBytes
    Head "Папка пользователя: $zPath (всего $(Fmt $zBytes))"
    if (Test-Path -LiteralPath $zPath) {
        $zEntries = @(Get-ChildItem -LiteralPath $zPath -Force -ErrorAction SilentlyContinue)
        foreach ($entry in $zEntries) {
            $b = Get-Bytes $entry.FullName
            Row $entry.Name $b
            if ($b -gt 0) {
                $why = switch -Regex ($entry.Name) {
                    '^Saves$' { 'Миры и прогресс игры; удаление миров необратимо без резервной копии.'; break }
                    '^Logs$' { 'Журналы работы и диагностики; полезны для поиска ошибок.'; break }
                    '^(Lua|InputBindings|joypads|Sandbox Presets|Server)$' { 'Настройки игры, управления, модов или серверных профилей.'; break }
                    '^backups$' { 'Резервные копии сохранений или игровых данных.'; break }
                    '^Workshop$' { 'Локальные проекты/данные Workshop, например подготовка собственных модов.'; break }
                    '^mods$' { 'Локально установленные моды, не обязательно загруженные через Steam Workshop.'; break }
                    default { 'Пользовательские данные Project Zomboid.' }
                }
                $spaceItems += [pscustomobject]@{Name=('Zomboid\' + $entry.Name); Bytes=$b; Why=$why}
            }
        }
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
        foreach ($mod in $list) {
            $modName = if ($mod.Name) { $mod.Name } else { 'Имя мода не найдено' }
            $spaceItems += [pscustomobject]@{Name=("Workshop\{0} [{1}]" -f $modName, $mod.Id); Bytes=$mod.Bytes; Why='Файлы подписанного Workshop-мода для обычной игры.'}
        }
        if ($listedBytes -ne $workshopBytes) {
            Write-Host "  Примечание: разница $(Fmt ([math]::Abs($listedBytes - $workshopBytes))) может быть из-за файлов вне папок-модов либо повторяющихся ID в разных библиотеках." -ForegroundColor Yellow
        }
    }

    Head 'ИТОГО'
    Row 'Сумма учтённых файлов PZ (Steam + Zomboid)' $total
    Write-Host 'Кэш воркшопа сервера учтён отдельно от размера файлов игры; при хостинге PZ хранит серверную копию модов отдельно от обычного Steam Workshop.' -ForegroundColor Gray
    Head 'Что занимает больше всего места: крупнейшие папки и данные'
    $spaceItems | Where-Object { $_.Bytes -gt 0 } | Sort-Object Bytes -Descending | Select-Object -First 15 | ForEach-Object {
        Row $_.Name $_.Bytes $_.Why
    }
    Write-Host 'Размеры — сумма логических размеров файлов; некоторые системные/защищённые файлы могут не читаться.' -ForegroundColor Gray
    if (-not $gameInstalled -and ($gameBytes + $workshopBytes) -gt 0) { Write-Host 'Игра не установлена, но её файлы или моды остались.' -ForegroundColor Yellow }
    Write-Host 'Скрипт ничего не изменял и не удалял. Для очистки есть cleanup.ps1.'
} catch { Write-Host "ОШИБКА: $($_.Exception.Message)" -ForegroundColor Red }
