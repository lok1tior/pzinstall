# Установщик сборки Project Zomboid (Build 42)
# Запуск: irm https://raw.githubusercontent.com/ТЫ/РЕПО/main/install.ps1 | iex
# Скрипт можно запускать повторно: он обновляет файлы и не дублирует пресет.
# Бета Viewpoint: скачанный из Discord zip скрипт ищет в Загрузках/на рабочем столе (или путь в $env:PZ_VIEWPOINT_ZIP).

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ---------------- НАСТРОЙКИ ----------------
$WorkshopZBId = "3619862853"      # ID воркшоп-предмета ZombieBuddy
$PresetName   = "Viewpoint"       # имя пресета порядка загрузки
$Preset = @'
Viewpoint:CACustomWoodWeight;CACustomMetalWeight;SawAllLogsDropPlanks;ChuckleberryFinnAlertSystem;errorMagnifier;RealisticDash;TombWardrobeALT;TombBody;TombBodyTexNUDE;TombBodyCompat;UsefulBarrelsMP;TombGothHair;TombGothMakeup;TombGothTexNUDE;ElliesOutfits;SpnHair;YakiHSBasegameTexture;YakiHS;ihm_picker;improvedhairmenubuild42;SpnCloth;SpnOpenCloth;SpnOpenClothBase;1VCESTANDARD;EURY_TRAPPING;autotsartrailers;ATakeABathAndShowerDepthMap;TakeABathAndShowerNew;PROJECTRVInterior42;RVInteriorExpansionPart2;RVInteriorExpansion;DieWithStyle;SVRPClassicBows;ModManager;SKITTLE_LongTermPreservation4220;ModLoadOrderSorter_b42;GanydeBielovzki's Frockin Shirts n Ties;GanydeBielovzki's Frockin Wiseguys;GanydeBielovzki's Frockin Stompers!;GanydeBielovzki's Frockin Stompers! VFR;GanydeBielovzki's Frockin Splendor! Vol.2;GanydeBielovzki's Frockin Splendor! Vol.3;GanydeBielovzki's Frockin Splendor! Vol.4;GanydeBielovzki's Frockin Splendor!;GanydeBielovzki's Frockin Splendor! Vol.5;FWOFitnessWorkoutOverhaul;FWOBenchPressTreadmill;HideClothingSlot;LGExtendedPlumbing;VHSSkillNameInTooltip;CHAINS;MedievalZ;VanillaFoodsExpanded;SapphCooking_B42;MattSimpleAddonsFriuts;TwisTonFireFasterActions;ProjectVarietyChapterOne;InvisiblePatches;GanydeBielovzki's Frockin Backstage!;PZVoxelStudioViewpoint;ViewpointBloodFX;ViewpointBloodFXAddon;ProjectALifeNPCs;Horse;BicycleMod;SkateboardMod;amclub;AviationCore;UH-1BHelicopter;ViewpointHeli;VFExpansion1;HorsePatch3d;ProjectViewpointADS;ViewpointTrueBallistics;ViewpointAdvancedThrowables;SMB_steps;BuildYourOwnKayak;damnlib;RET_LethalStealth;REORDER_THE_HOTBAR;RebalancedPropMoving;RainCleansBlood;Parkour;LGTapeXP;ImprovisedSilencers;stanks_suicide;ImmersiveBlackouts;FH;EQUIPMENT_UI_B42;dustinguished_bolt_cutters;BetterSortCC;AutoMechanics;alicesWeaponSling;alicesWeaponSlingRadialMenu;YAPZLib;MinimalSidebar;tsarslib;DetailedDescriptionsForOccupationsAndTraits;CVI;ViewpointLivingProps;ViewpointRollingHills;RollingHillsPhysics;PFHDTrueCargo;CarRoofFix;CarEnterExitFix;CarWeaponFix;KI5minifixes;VSUIKI5;VMZNEW;isoContainers;KI5trailers;KI5campers;93townCar;93fordTaurus;93mustangSSP;93fordF350;93fordElgin;93chevySuburban;93chevySuburbanExpanded;92nissanGTR;92jeepYJ;92fordCVPI;92amgeneralM998;92amgeneralM998extra;91range;91nissan240sx;91lexusLS400;91geoMetro;91fordRanger;91fordLTD;90pierceArrow;90fordF350ambulance;90bmwE30;89volvo200;89defender;89trooper;89fordBronco;89dodgeCaravan;88toyotaHilux;88chevyS10;87toyotaMR2;87toyotaCorolla;87fordB700;87chevySuburban;87buickRegal;86fordE150;86fordE150expanded;86fordE150mm;86chevyCUCV;85pontiacParisienne;85oldsmobileDelta88;85chevyStepVan;85chevyStepVanexpanded;85chevyCaprice;85buickLeSabre;84oldsmobile98;84merc;84jeepXJ;84corvette;84cadillacDeVille;84buickElectra;82porsche911;82firebird;82oshkoshM911;82jeepJ10;81deloreanDMC12;79camaro;78lamboCountach;78amgeneralM35A2;78amgeneralM35A2extra;78amgeneralM62;77firebird;76chryslerNewYorker;76chevyKseries;76chevyKseriesExpanded;75grandPrix;73nissanGTR;73fordFalcon;70roadRunner;70barracuda;70fordEscort;70dodge;70chevelle;69mini;69mini_ItalianJob;69mini_MrBean;69fordMustang;69fordMustangExtra;69charger;69camaro;68firebird;67gt500;67commando;66pontiacLeMans;65banshee;63Type2Van;63beetle;62daimlerFerret;49powerWagon;MPOptimizer;
'@
$Preset = $Preset.Trim()
# -------------------------------------------

$utf8 = New-Object System.Text.UTF8Encoding($false)   # UTF-8 без BOM (Java не любит BOM в json)

# ---------- вспомогательные функции для беты Viewpoint ----------
function Get-ModInfoValue($file, $key) {
    $line = Get-Content $file -ErrorAction SilentlyContinue |
        Where-Object { $_ -match ("^\s*" + $key + "\s*=") } | Select-Object -First 1
    if ($line) { return ($line -replace ("^\s*" + $key + "\s*=\s*"), "").Trim() }
    return $null
}

# Распаковывает zip беты в <Zomboid>\Workshop\Viewpoint. Сначала проверяет содержимое, старую папку заменяет целиком.
function Install-ViewpointBeta($zipPath, $workshopRoot) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("vpbeta_" + [guid]::NewGuid().ToString("N"))
    try {
        Expand-Archive -LiteralPath $zipPath -DestinationPath $tmp -Force
        $src  = Join-Path $tmp "Viewpoint"
        $info = Join-Path $src "Contents/mods/Viewpoint/common/mod.info"
        if (-not (Test-Path $info)) { throw "В архиве нет Viewpoint\Contents\mods\Viewpoint\common\mod.info - это не тот архив." }
        if ((Get-ModInfoValue $info "id") -ne "Viewpoint") { throw "mod.info в архиве не принадлежит моду Viewpoint." }

        # значения читаем ДО перемещения папки
        $newVer = Get-ModInfoValue $info "modversion"
        $gMin = Get-ModInfoValue $info "versionMin"
        $gMax = Get-ModInfoValue $info "versionMax"

        $dest = Join-Path $workshopRoot "Viewpoint"
        $oldInfo = Join-Path $dest "Contents/mods/Viewpoint/common/mod.info"
        $old = $null
        if (Test-Path $oldInfo) { $old = Get-ModInfoValue $oldInfo "modversion" }

        New-Item -ItemType Directory -Force -Path $workshopRoot | Out-Null
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
        Move-Item $src $dest
        return [pscustomobject]@{
            New = $newVer; Old = $old; GameMin = $gMin; GameMax = $gMax; Dest = $dest
        }
    }
    finally { if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue } }
}

try {
    if (Get-Process ProjectZomboid64 -ErrorAction SilentlyContinue) {
        throw "Project Zomboid запущен. Закрой игру и запусти скрипт снова."
    }

    # ---------- 1. Поиск игры (учитывает другие диски/библиотеки Steam) ----------
    $steam = (Get-ItemProperty "HKCU:\Software\Valve\Steam").SteamPath
    $libs = @($steam)
    $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
    if (Test-Path $vdf) {
        $libs += Select-String -Path $vdf -Pattern '"path"\s+"(.+)"' |
            ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' }
    }
    $lib = $libs | Where-Object {
        Test-Path (Join-Path $_ "steamapps\common\ProjectZomboid\ProjectZomboid64.json")
    } | Select-Object -First 1
    if (-not $lib) { throw "Project Zomboid не найден. Сначала установи игру через Steam." }

    $lib = [IO.Path]::GetFullPath($lib)
    $game = Join-Path $lib "steamapps\common\ProjectZomboid"
    $workshop = Join-Path $lib "steamapps\workshop\content\108600"
    Write-Host "Игра найдена: $game" -ForegroundColor Cyan

    # ---------- 2. Оперативная память ----------
    $totalGB = [int][math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    $xmx = [int][math]::Max(4, [math]::Min(8, [math]::Floor($totalGB / 2)))
    $xms = [int][math]::Max(2, [math]::Floor($xmx / 2))
    if ($totalGB -lt 12) {
        Write-Host "ВНИМАНИЕ: в ПК только $totalGB ГБ ОЗУ. Со сборкой такого размера игра, скорее всего, будет тормозить." -ForegroundColor Yellow
    }

    $json = Join-Path $game "ProjectZomboid64.json"
    $bak = "$json.bak"
    if (-not (Test-Path $bak)) { Copy-Item $json $bak }     # оригинал сохраняем один раз

    $text = [IO.File]::ReadAllText($json)
    if ($text -notmatch '"-Xmx\d+[mMgG]"') {
        throw "В ProjectZomboid64.json не найден параметр -Xmx. Пришли файл автору сборки."
    }
    $text = [regex]::Replace($text, '"-Xmx\d+[mMgG]"', "`"-Xmx${xmx}g`"")
    if ($text -match '"-Xms\d+[mMgG]"') {
        $text = [regex]::Replace($text, '"-Xms\d+[mMgG]"', "`"-Xms${xms}g`"")
    } else {
        $text = [regex]::Replace($text, '"-Xmx\d+g"',
            ('"-Xmx{0}g",' -f $xmx) + "`r`n`t`t" + ('"-Xms{0}g"' -f $xms))
    }
    try { $null = $text | ConvertFrom-Json } catch { throw "Получился некорректный json, файл не изменён." }
    [IO.File]::WriteAllText($json, $text, $utf8)
    Write-Host "Память: -Xmx${xmx}g, -Xms${xms}g (ОЗУ в ПК: $totalGB ГБ)" -ForegroundColor Green

    # ---------- 3. ZombieBuddy (ручная установка, вариант B) ----------
    $zbSrc = Join-Path $workshop "$WorkshopZBId\mods\ZombieBuddy\libs"
    $zbOk = Test-Path $zbSrc
    if ($zbOk) {
        foreach ($f in "ZombieBuddy.jar", "zbNative.dll") {
            $p = Join-Path $zbSrc $f
            if (-not (Test-Path $p)) { throw "Не найден файл $p" }
            Copy-Item $p $game -Force
        }
        Write-Host "ZombieBuddy.jar и zbNative.dll скопированы в папку игры" -ForegroundColor Green
    } else {
        Write-Host "ZombieBuddy ещё не скачан Steam. Подпишись на коллекцию, дождись конца загрузки и запусти скрипт ещё раз." -ForegroundColor Yellow
    }

    # ---------- 4. Порядок загрузки модов ----------
    $cfgDir = Join-Path $env:USERPROFILE "Zomboid\Lua"
    $cfg = Join-Path $cfgDir "pz_modlist_settings.cfg"
    New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null

    $old = ""
    if (Test-Path $cfg) {
        if (-not (Test-Path "$cfg.bak")) { Copy-Item $cfg "$cfg.bak" }
        $old = [IO.File]::ReadAllText($cfg)
    }
    # Формат игры: отдельная строка !fav!:..., затем отдельная строка на каждый пресет Name:mod;mod;...;
    # Раньше разделитель ';' склеивал запись пресета с предыдущей строкой избранного.
    $lines = @()
    if (-not [string]::IsNullOrWhiteSpace($old)) {
        $lines = @([regex]::Split($old.Trim(), '\r?\n') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    $favIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^!fav!:') { $favIndex = $i; break }
    }
    if ($favIndex -lt 0) { $lines = @('!fav!:') + $lines }

    $presetIndex = -1
    $presetPrefix = '^' + [regex]::Escape($PresetName) + ':'
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $presetPrefix) { $presetIndex = $i; break }
    }
    if ($presetIndex -ge 0) {
        $lines[$presetIndex] = $Preset
        Write-Host "Пресет $PresetName обновлён, остальные пресеты и избранное сохранены" -ForegroundColor Green
    } elseif ($favIndex -ge 0 -and $lines[$favIndex] -match '^!fav!:Viewpoint;(.+)$') {
        # Исправляем старую ошибочную запись, где имя пресета и его моды оказались в строке избранного.
        # Резервная копия cfg создаётся выше; содержимое переносим в новый пресет, избранное очищаем.
        $migratedMods = $Matches[1]
        $lines[$favIndex] = '!fav!:'
        $lines += ($PresetName + ':' + $migratedMods)
        Write-Host "Список модов перенесён из ошибочной строки избранного в пресет $PresetName" -ForegroundColor Green
    } else {
        $lines += $Preset
        Write-Host "Пресет $PresetName добавлен отдельной строкой; остальные пресеты и избранное сохранены" -ForegroundColor Green
    }
    [IO.File]::WriteAllText($cfg, ($lines -join "`r`n") + "`r`n", $utf8)

    # ---------- 4б. Бета Project Viewpoint (ставится вручную из zip) ----------
    # Zip НЕЛЬЗЯ выкладывать в репозиторий: лицензия Viewpoint запрещает перезаливать мод и включать его в сборки.
    # Каждый скачивает архив сам, из Discord Project Viewpoint, а скрипт только распаковывает его куда нужно.
    $vpDone = $false
    $zip = $env:PZ_VIEWPOINT_ZIP
    if (-not $zip) {
        $zip = @((Join-Path $env:USERPROFILE "Downloads"), (Join-Path $env:USERPROFILE "Desktop")) |
            Where-Object { Test-Path $_ } |
            ForEach-Object { Get-ChildItem $_ -Filter "Viewpoint*.zip" -File -ErrorAction SilentlyContinue } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $zip) {
        Write-Host ""
        Write-Host "Архив беты Viewpoint (Viewpoint-nightly-....zip) не найден в Загрузках и на рабочем столе." -ForegroundColor Yellow
        $zip = (Read-Host "Путь к zip (можно перетащить файл в окно) или Enter, чтобы пропустить").Trim('" ')
    }
    if ($zip -and (Test-Path -LiteralPath $zip)) {
        Write-Host "Бета Viewpoint: $zip"
        $vp = Install-ViewpointBeta $zip (Join-Path $env:USERPROFILE "Zomboid\Workshop")
        $vpDone = $true
        if ($vp.Old -and $vp.Old -ne $vp.New) { Write-Host "Бета Viewpoint обновлена: $($vp.Old) -> $($vp.New)" -ForegroundColor Green }
        else { Write-Host "Бета Viewpoint $($vp.New) установлена в $($vp.Dest)" -ForegroundColor Green }
        Write-Host "Бета рассчитана на версию игры $($vp.GameMin)-$($vp.GameMax); на другой версии мод не загрузится." -ForegroundColor Yellow
    } elseif ($zip) {
        Write-Host "Файл не найден: $zip" -ForegroundColor Yellow
    } else {
        Write-Host "Установка беты Viewpoint пропущена: скачай архив из Discord Project Viewpoint и запусти скрипт ещё раз." -ForegroundColor Yellow
    }

    # ---------- 5. Что осталось сделать руками ----------
    Set-Clipboard -Value "-agentlib:zbNative --"
    Write-Host ""
    Write-Host "=== ПОСЛЕДНИЙ ШАГ (15 секунд) ===" -ForegroundColor Cyan
    Write-Host "Строка уже скопирована в буфер обмена:  -agentlib:zbNative --"
    Write-Host "Steam -> Библиотека -> Project Zomboid -> ПКМ -> Свойства -> Общие -> Параметры запуска -> Ctrl+V"
    Write-Host "Две чёрточки в конце обязательны!" -ForegroundColor Yellow
    if (-not $zbOk) { Write-Host "И не забудь перезапустить скрипт после загрузки ZombieBuddy." -ForegroundColor Yellow }
    Write-Host "В игре: Mods -> загрузи пресет $PresetName."
    if ($vpDone) {
        Write-Host "Viewpoint: в списке модов будут ДВЕ записи Viewpoint (релиз из Steam и бета). Нужна бета, версия $($vp.New)." -ForegroundColor Yellow
        Write-Host "При первом запуске ZombieBuddy попросит подтвердить Java-часть мода - подтверди."
        Write-Host "Если видишь ошибку INVALID SIGNATURE - смотри совет разработчиков Viewpoint в их Discord."
    }
    Write-Host "Готово!" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ОШИБКА: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Если написано про доступ - запусти PowerShell от имени администратора." -ForegroundColor Yellow
    exit 1
}
