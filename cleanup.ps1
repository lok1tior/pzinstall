# Очистка остатков Project Zomboid (для чистой переустановки)
# Запуск: irm https://raw.githubusercontent.com/ТЫ/РЕПО/main/cleanup.ps1 | iex
# По каждой папке спрашивает подтверждение. Ничего не удаляет без ответа "y".

$ErrorActionPreference = "Stop"

function Get-DirSizeGB($p) {
    $s = (Get-ChildItem $p -Recurse -Force -File -ErrorAction SilentlyContinue |
          Measure-Object Length -Sum).Sum
    if (-not $s) { $s = 0 }
    return [math]::Round($s / 1GB, 2)
}

try {
    if (Get-Process ProjectZomboid64 -ErrorAction SilentlyContinue) {
        throw "Project Zomboid запущен. Закрой игру и запусти скрипт снова."
    }

    $steam = (Get-ItemProperty "HKCU:\Software\Valve\Steam").SteamPath
    $libs = @($steam)
    $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
    if (Test-Path $vdf) {
        $libs += Select-String -Path $vdf -Pattern '"path"\s+"(.+)"' |
            ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' }
    }
    $libs = $libs | ForEach-Object { [IO.Path]::GetFullPath($_) } | Select-Object -Unique

    $targets = @()
    foreach ($lib in $libs) {
        $sa = Join-Path $lib "steamapps"
        $installed = Test-Path (Join-Path $sa "appmanifest_108600.acf")
        if ($installed) {
            Write-Host "Игра ещё установлена в $lib - сначала удали её через Steam, папку игры не трогаю." -ForegroundColor Yellow
        } else {
            $targets += @{ Path = (Join-Path $sa "common\ProjectZomboid"); Note = "остатки папки игры" }
        }
        $targets += @{ Path = (Join-Path $sa "workshop\content\108600");   Note = "скачанные воркшоп-моды (сначала отпишись от коллекции в Steam, иначе Steam скачает их заново)" }
        $targets += @{ Path = (Join-Path $sa "workshop\downloads\108600"); Note = "недокачанные воркшоп-файлы" }
        $targets += @{ Path = (Join-Path $sa "downloading\108600");        Note = "недокачанные файлы игры" }
        $targets += @{ Path = (Join-Path $sa "shadercache\108600");        Note = "кэш шейдеров" }
    }
    $targets += @{ Path = (Join-Path $env:USERPROFILE "Zomboid"); Note = "СОХРАНЕНИЯ, настройки, логи, список модов. Если нужны сохранения - скопируй Zomboid\Saves заранее" }

    $freed = 0
    foreach ($t in $targets) {
        if (-not (Test-Path $t.Path)) { continue }
        $gb = Get-DirSizeGB $t.Path
        Write-Host ""
        Write-Host $t.Path -ForegroundColor Cyan
        Write-Host "  $gb ГБ - $($t.Note)"
        $ans = Read-Host "  Удалить? (y/N)"
        if ($ans -eq "y") {
            Remove-Item $t.Path -Recurse -Force
            $freed += $gb
            Write-Host "  Удалено" -ForegroundColor Green
        }
    }
    Write-Host ""
    Write-Host "Освобождено примерно: $([math]::Round($freed, 2)) ГБ" -ForegroundColor Green
}
catch {
    Write-Host "ОШИБКА: $($_.Exception.Message)" -ForegroundColor Red
}
