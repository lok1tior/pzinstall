# Очистка файлов Project Zomboid. Каждая существующая папка удаляется только после ответа y.
# Запуск: irm https://raw.githubusercontent.com/lok1tior/pzinstall/refs/heads/main/cleanup.ps1 | iex
$ErrorActionPreference = 'Stop'

function Get-DirBytes([string]$Path) {
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { return [int64]0 }
    return [int64]$sum
}
function Fmt([int64]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N2} ГБ' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} МБ' -f ($Bytes / 1MB)) }
    return ('{0:N0} КБ' -f ($Bytes / 1KB))
}
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
    if ((Get-Process ProjectZomboid64 -ErrorAction SilentlyContinue) -or (Get-Process ProjectZomboidServer -ErrorAction SilentlyContinue)) { throw 'Project Zomboid или сервер запущен. Закрой игру/сервер и запусти скрипт снова.' }
    $targets = @(); $targetPaths = @{}
    foreach ($lib in @(Get-SteamLibraries)) {
        $sa = Join-Path $lib 'steamapps'
        $installed = Test-Path -LiteralPath (Join-Path $sa 'appmanifest_108600.acf')
        if ($installed) {
            Write-Host "Игра установлена в $lib — папку игры не предлагаю удалять." -ForegroundColor Yellow
            $serverWorkshop = Join-Path $sa 'common\ProjectZomboid\steamapps\workshop'
            $targets += @{Path=$serverWorkshop; Note='Отдельная копия Workshop-модов и служебный манифест, используемые локальным Host/сервером. Это не обычная подписочная папка Steam. После удаления Steam-клиент сам её не восстановит; при следующем запуске хостинга нужные серверу моды могут скачаться снова.'}
        } else {
            $targets += @{Path=(Join-Path $sa 'common\ProjectZomboid'); Note='остатки папки игры'}
        }
        $targets += @{Path=(Join-Path $sa 'workshop\content\108600'); Note='скачанные воркшоп-моды; при активных подписках Steam скачает их снова'}
        $targets += @{Path=(Join-Path $sa 'workshop\downloads\108600'); Note='незавершённые загрузки воркшопа'}
        $targets += @{Path=(Join-Path $sa 'downloading\108600'); Note='незавершённые загрузки игры'}
        $targets += @{Path=(Join-Path $sa 'shadercache\108600'); Note='кэш шейдеров'}
    }
    $zomboid = Join-Path $env:USERPROFILE 'Zomboid'
    # Сохранения и логи остаются отдельными каталогами на диске, но предлагаются
    # одним выбором, как просил пользователь. Настройки вынесены в свой пункт.
    $targets += @{Paths=@((Join-Path $zomboid 'Saves'), (Join-Path $zomboid 'Logs')); Label='Saves + Logs'; Note='миры сохранений и журналы игры. Удаление миров необратимо — сохрани нужные заранее'}
    $targets += @{Paths=@((Join-Path $zomboid 'Lua'), (Join-Path $zomboid 'InputBindings'), (Join-Path $zomboid 'joypads'), (Join-Path $zomboid 'Sandbox Presets'), (Join-Path $zomboid 'Server'), (Join-Path $zomboid 'mods.txt.backup')); Label='Настройки'; Note='настройки модов, управления и пресеты; после удаления игра создаст часть заново'}
    # Остальные данные пользователя предлагаем по отдельности: можно выбрать
    # только действительно ненужные каталоги, включая логи модов и кэши.
    $groupedNames = @('Saves', 'Logs', 'Lua', 'InputBindings', 'joypads', 'Sandbox Presets', 'Server', 'mods.txt.backup')
    if (Test-Path -LiteralPath $zomboid) {
        Get-ChildItem -LiteralPath $zomboid -Force -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer -and $_.Name -notin $groupedNames } | ForEach-Object {
            $note = switch -Regex ($_.Name) {
                '^backups$' { 'Резервные копии игровых данных; удаляй, только если они больше не нужны.'; break }
                '^Crafting$' { 'Пользовательские данные/состояние крафта.'; break }
                '^db$' { 'Базы данных серверов, включая списки игроков и администрирование.'; break }
                '^mods$' { 'Локальные моды, установленные не через обычную подписку Steam Workshop.'; break }
                '^Workshop$' { 'Локальные проекты Workshop, например подготовка собственных модов.'; break }
                '^Screenshots$' { 'Скриншоты игры.'; break }
                '^Recording$' { 'Записи игрового процесса, если они есть.'; break }
                '^PZO$' { 'Данные дополнительного компонента/мода PZO.'; break }
                '^viewpoint-' { 'Данные/кэш мода Viewpoint.'; break }
                '^TrueWeathers$' { 'Данные мода TrueWeathers.'; break }
                default { 'Пользовательские данные или настройки Project Zomboid.' }
            }
            $targets += @{Paths=@($_.FullName); Label=$_.Name; Note=$note}
        }
    }
    $freed = [int64]0
    foreach ($t in $targets) {
        $paths = if ($t.Paths) { @($t.Paths) } else { @($t.Path) }
        $existing = @($paths | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') } | Where-Object { (Test-Path -LiteralPath $_) -and -not $targetPaths.ContainsKey($_) })
        if ($existing.Count -eq 0) { continue }
        foreach ($full in $existing) { $targetPaths[$full] = $true }
        [int64]$bytes = 0
        foreach ($full in $existing) { $bytes += Get-DirBytes $full }
        $label = if ($t.Label) { $t.Label } else { $existing[0] }
        Write-Host "`n$label" -ForegroundColor Cyan
        Write-Host '  Что будет удалено:' -ForegroundColor White
        foreach ($full in $existing) { Write-Host "    $full — $(Fmt (Get-DirBytes $full))" }
        Write-Host "  Всего: $(Fmt $bytes)"
        Write-Host "  Для чего это нужно / что содержит: $($t.Note)" -ForegroundColor Gray
        $ans = Read-Host '  Удалить перечисленные данные? (y/N)'
        if ($ans -ceq 'y') {
            foreach ($full in $existing) { Remove-Item -LiteralPath $full -Recurse -Force }
            $freed += $bytes
            Write-Host '  Удалено' -ForegroundColor Green
        }
    }
    Write-Host "`nОсвобождено примерно: $(Fmt $freed)" -ForegroundColor Green
} catch { Write-Host "ОШИБКА: $($_.Exception.Message)" -ForegroundColor Red }
