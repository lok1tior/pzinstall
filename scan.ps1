# Диагностика: что занимает место у Project Zomboid. Ничего не удаляет и не меняет.
# Запуск: irm https://raw.githubusercontent.com/ТЫ/РЕПО/main/scan.ps1 | iex
# Для самой проверки не нужны ни права администратора, ни запущенный Steam.
# На большой сборке может занять до минуты.

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ---------------- НАСТРОЙКИ ----------------
$CollectionId = "3831950228"   # ID твоей коллекции (чтобы найти моды не из неё)
# -------------------------------------------

function Get-Bytes($p) {
    if (-not (Test-Path $p)) { return [int64]0 }
    $s = (Get-ChildItem $p -Recurse -Force -File -ErrorAction SilentlyContinue |
          Measure-Object Length -Sum).Sum
    if (-not $s) { return [int64]0 }
    return [int64]$s
}
function Fmt($b) {
    if ($b -ge 1GB) { return ("{0:N2} ГБ" -f ($b / 1GB)) }
    if ($b -ge 1MB) { return ("{0:N0} МБ" -f ($b / 1MB)) }
    return ("{0:N0} КБ" -f ($b / 1KB))
}
function Row($name, $bytes, $note = "") {
    Write-Host ("  {0,-46} {1,12}   {2}" -f $name, (Fmt $bytes), $note)
}
function Head($t) { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Cyan }

try {
    Write-Host "Считаю размеры, подожди немного..." -ForegroundColor Gray

    # ---------- Библиотеки Steam ----------
    $steam = (Get-ItemProperty "HKCU:\Software\Valve\Steam").SteamPath
    $libs = @($steam)
    $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
    if (Test-Path $vdf) {
        $libs += Select-String -Path $vdf -Pattern '"path"\s+"(.+)"' |
            ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' }
    }
    $libs = $libs | ForEach-Object { [IO.Path]::GetFullPath($_) } | Select-Object -Unique

    $total = [int64]0
    $gameInstalled = $false
    $gameBytes = [int64]0
    $workshopBytes = [int64]0
    $workshopItems = @()      # все папки модов во всех библиотеках

    Head "Steam (по библиотекам)"
    foreach ($lib in $libs) {
        $sa = Join-Path $lib "steamapps"
        $installed = Test-Path (Join-Path $sa "appmanifest_108600.acf")
        $gamePath = Join-Path $sa "common\ProjectZomboid"
        $wsPath   = Join-Path $sa "workshop\content\108600"

        $g  = Get-Bytes $gamePath
        $w  = Get-Bytes $wsPath
        $wd = Get-Bytes (Join-Path $sa "workshop\downloads\108600")
        $dl = Get-Bytes (Join-Path $sa "downloading\108600")
        $sc = Get-Bytes (Join-Path $sa "shadercache\108600")

        if (($g + $w + $wd + $dl + $sc) -eq 0 -and -not $installed) { continue }
        Write-Host "  Библиотека: $lib" -ForegroundColor White
        if ($installed) { $gameInstalled = $true; Row "  Папка игры" $g "установлена" }
        elseif ($g -gt 0) { Row "  Папка игры" $g "ОСТАТКИ: игра удалена, а файлы остались" }
        Row "  Воркшоп-моды (content\108600)" $w
        if ($wd -gt 0) { Row "  Недокачанные воркшоп-файлы" $wd "застряли, можно удалять" }
        if ($dl -gt 0) { Row "  Недокачанные файлы игры" $dl "застряли, можно удалять" }
        if ($sc -gt 0) { Row "  Кэш шейдеров" $sc }
        $gameBytes += $g; $workshopBytes += $w
        $total += $g + $w + $wd + $dl + $sc

        if (Test-Path $wsPath) {
            $workshopItems += Get-ChildItem $wsPath -Directory -ErrorAction SilentlyContinue
        }
    }

    # ---------- Папка пользователя Zomboid ----------
    $zPath = Join-Path $env:USERPROFILE "Zomboid"
    $zBytes = Get-Bytes $zPath
    $total += $zBytes
    Head "Папка пользователя: $zPath  ($(Fmt $zBytes))"
    if (Test-Path $zPath) {
        $subs = Get-ChildItem $zPath -Directory -Force -ErrorAction SilentlyContinue |
            ForEach-Object { [pscustomobject]@{ Name = $_.Name; Bytes = (Get-Bytes $_.FullName) } } |
            Sort-Object Bytes -Descending
        foreach ($s in $subs) {
            $note = switch ($s.Name) {
                "Saves"    { "сохранения (подробнее ниже)" }
                "Logs"     { "логи, можно чистить" }
                "Lua"      { "настройки модов и пресеты, лучше не трогать" }
                "mods"     { "локальные моды" }
                "Workshop" { "локальные воркшоп-проекты" }
                default    { "" }
            }
            Row $s.Name $s.Bytes $note
        }
    } else {
        Write-Host "  Папки нет - всё чисто." -ForegroundColor Green
    }

    # ---------- Сохранения подробно ----------
    $savesPath = Join-Path $zPath "Saves"
    if (Test-Path $savesPath) {
        Head "Сохранения подробно"
        $mp = Join-Path $savesPath "Multiplayer"
        if (Test-Path $mp) {
            Row "Multiplayer (кэш серверов)" (Get-Bytes $mp) "карта серверов, на которых играл"
            Get-ChildItem $mp -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { [pscustomobject]@{ Name = $_.Name; Bytes = (Get-Bytes $_.FullName) } } |
                Sort-Object Bytes -Descending | Select-Object -First 8 |
                ForEach-Object { Row ("  " + $_.Name) $_.Bytes }
        }
        $single = Get-ChildItem $savesPath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "Multiplayer" } |
            ForEach-Object { Get-ChildItem $_.FullName -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { [pscustomobject]@{ Name = ($_.Parent.Name + "\" + $_.Name); Bytes = (Get-Bytes $_.FullName); Date = $_.LastWriteTime } } } |
            Sort-Object Bytes -Descending | Select-Object -First 10
        if ($single) {
            Write-Host "  Одиночные сохранения (топ по размеру):"
            foreach ($s in $single) { Row ("  " + $s.Name) $s.Bytes ("последний раз: " + $s.Date.ToString("dd.MM.yyyy")) }
        }
    }

    # ---------- Воркшоп-моды ----------
    if ($workshopItems.Count -gt 0) {
        Head "Воркшоп-моды: $($workshopItems.Count) шт., всего $(Fmt $workshopBytes)"

        # состав коллекции (публичный API Steam, ключ не нужен)
        $inCollection = $null
        try {
            $r = Invoke-RestMethod -Method Post -Uri "https://api.steampowered.com/ISteamRemoteStorage/GetCollectionDetails/v1/" `
                 -Body @{ collectioncount = 1; "publishedfileids[0]" = $CollectionId }
            $ids = @($r.response.collectiondetails[0].children | ForEach-Object { [string]$_.publishedfileid })
            if ($ids.Count -gt 0) { $inCollection = $ids }
        } catch { }

        $list = foreach ($d in $workshopItems) {
            $name = ""
            $mi = Get-ChildItem $d.FullName -Recurse -Depth 4 -Filter mod.info -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($mi) {
                $line = Get-Content $mi.FullName -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*name\s*=' } | Select-Object -First 1
                if ($line) { $name = ($line -replace '^\s*name\s*=\s*', '').Trim() }
            }
            [pscustomobject]@{
                Id = $d.Name; Name = $name; Bytes = (Get-Bytes $d.FullName)
                Extra = ($inCollection -and ($inCollection -notcontains $d.Name))
            }
        }

        Write-Host "  Самые тяжёлые:"
        $list | Sort-Object Bytes -Descending | Select-Object -First 15 | ForEach-Object {
            $n = if ($_.Name) { $_.Name } else { "(без имени)" }
            if ($n.Length -gt 34) { $n = $n.Substring(0, 34) + "..." }
            Row ("  {0}  [{1}]" -f $n, $_.Id) $_.Bytes
        }

        if ($inCollection) {
            $extra = @($list | Where-Object { $_.Extra })
            $extraBytes = [int64]0
            foreach ($e in $extra) { $extraBytes += $e.Bytes }
            Write-Host ""
            if ($extra.Count -gt 0) {
                Write-Host "  Не из коллекции $CollectionId : $($extra.Count) шт., $(Fmt $extraBytes)" -ForegroundColor Yellow
                Write-Host "  (старые подписки или моды из других коллекций; топ по размеру:)"
                $extra | Sort-Object Bytes -Descending | Select-Object -First 10 | ForEach-Object {
                    $n = if ($_.Name) { $_.Name } else { "(без имени)" }
                    if ($n.Length -gt 34) { $n = $n.Substring(0, 34) + "..." }
                    Row ("  {0}  [{1}]" -f $n, $_.Id) $_.Bytes
                }
            } else {
                Write-Host "  Лишних модов нет: всё из коллекции." -ForegroundColor Green
            }
        } else {
            Write-Host "  (Не удалось получить состав коллекции, сравнение со старыми подписками пропущено.)" -ForegroundColor Gray
        }
    }

    # ---------- Итог ----------
    Head "ИТОГО"
    Write-Host ("  Всего занято Project Zomboid: {0}" -f (Fmt $total)) -ForegroundColor White

    Write-Host ""
    Write-Host "Выводы:" -ForegroundColor Cyan
    if (-not $gameInstalled -and ($gameBytes + $workshopBytes) -gt 0) {
        Write-Host "  - Игра не установлена, но файлы на диске остались. Отпишись от модов в Steam (Воркшоп -> Мои подписки), потом запусти cleanup.ps1." -ForegroundColor Yellow
    }
    if ($workshopBytes -gt 0 -and $total -gt 0 -and ($workshopBytes / $total) -gt 0.5) {
        Write-Host "  - Больше половины места занимают воркшоп-моды. Это обычно главная причина." -ForegroundColor Yellow
    }
    if ($zBytes -gt 5GB) {
        Write-Host "  - Папка Zomboid больше 5 ГБ: смотри раздел 'Сохранения подробно' и логи." -ForegroundColor Yellow
    }
    Write-Host "  Этот скрипт ничего не удалял. Для очистки есть cleanup.ps1 (спрашивает подтверждение по каждой папке)."
}
catch {
    Write-Host "ОШИБКА: $($_.Exception.Message)" -ForegroundColor Red
}
