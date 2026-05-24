#Requires -Version 5.1
<#
.SYNOPSIS
    Mine Tiers all-in-one integrity tool.
.DESCRIPTION
    Combines deep Minecraft mod scanning, JVM and injector runtime checks,
    and live mouse macro monitoring in a single PowerShell script.

    Modes:
      - Menu    : Interactive launcher
      - Scan    : Run the integrity scan only
      - Monitor : Start the live macro monitor only
      - Full    : Run the integrity scan, then start the live macro monitor
#>
[CmdletBinding()]
param(
    [ValidateSet("Menu", "Scan", "Monitor", "Full")]
    [string]$Mode = "Menu",
    [string]$ModsPath,
    [switch]$SkipPause
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Initialize-Console {
    try { [Console]::SetBufferSize(150, 9999) } catch {}
    try { [Console]::SetWindowSize(150, 32) } catch {}
    try {
        $rawUi = $Host.UI.RawUI
        $buffer = $rawUi.BufferSize
        $buffer.Width = 150
        $buffer.Height = 9999
        $rawUi.BufferSize = $buffer
        $window = $rawUi.WindowSize
        $window.Width = 150
        $window.Height = 32
        $rawUi.WindowSize = $window
    } catch {}
}

function Show-MineTiersBanner {
    param([string]$Subtitle = "Integrity Suite")

    Write-Host ""
    Write-Host "   __  __ _              _______ _" -ForegroundColor Magenta
    Write-Host "  |  \/  (_)_ __   ___  |__   __(_) ___ _ __ ___" -ForegroundColor Magenta
    Write-Host "  | |\/| | | '_ \ / _ \    | |  | |/ _ \ '__/ __|" -ForegroundColor Magenta
    Write-Host "  | |  | | | | | |  __/    | |  | |  __/ |  \__ \" -ForegroundColor DarkMagenta
    Write-Host "  |_|  |_|_|_| |_|\___|    |_|  |_|\___|_|  |___/" -ForegroundColor DarkMagenta
    Write-Host ""
    Write-Host ("  " + $Subtitle) -ForegroundColor White
    Write-Host ""
}

function Pause-ForExit {
    if ($SkipPause) { return }
    Write-Host ""
    Write-Host "  Press any key to continue..." -ForegroundColor DarkGray
    try { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch {}
}

function Resolve-ModsPath {
    param([string]$InputPath)

    $defaultModsPath = Join-Path $env:USERPROFILE "AppData\Roaming\.minecraft\mods"
    $trimmedInput = if ([string]::IsNullOrWhiteSpace($InputPath)) { "" } else { $InputPath.Trim('"') }
    $liveSource = Get-LiveMinecraftModsPath

    if ($liveSource -and (
        [string]::IsNullOrWhiteSpace($trimmedInput) -or
        $trimmedInput -match "^(?i:live|auto)$" -or
        (Test-SamePath -Left $trimmedInput -Right $defaultModsPath)
    )) {
        Write-Host "  Live Minecraft mods path detected" -ForegroundColor DarkGray
        Write-Host "  $($liveSource.Path)" -ForegroundColor Magenta
        Write-Host "  Source: $($liveSource.Source)" -ForegroundColor DarkGray
        return $liveSource.Path
    }

    if (-not [string]::IsNullOrWhiteSpace($trimmedInput)) {
        return $trimmedInput
    }

    Write-Host "  Mods path (leave blank for default, or type live)" -ForegroundColor DarkGray
    Write-Host "  > " -ForegroundColor Magenta -NoNewline
    $entered = Read-Host
    if ([string]::IsNullOrWhiteSpace($entered)) {
        return $defaultModsPath
    }
    if ($entered.Trim() -match "^(?i:live|auto)$" -and $liveSource) {
        return $liveSource.Path
    }
    return $entered.Trim('"')
}

function Select-RunMode {
    while ($true) {
        Clear-Host
        Show-MineTiersBanner -Subtitle "All-in-One Integrity Suite"
        Write-Host "  [1] Full suite  - integrity scan + live macro monitor" -ForegroundColor White
        Write-Host "  [2] Scan only   - mods, JVM, injector, and runtime analysis" -ForegroundColor White
        Write-Host "  [3] Monitor     - live macro and file deletion monitor" -ForegroundColor White
        Write-Host "  [4] Exit" -ForegroundColor White
        Write-Host ""
        Write-Host "  Select mode" -ForegroundColor DarkGray
        Write-Host "  > " -ForegroundColor Magenta -NoNewline
        $choice = (Read-Host).Trim()
        switch ($choice) {
            "1" { return "Full" }
            "2" { return "Scan" }
            "3" { return "Monitor" }
            "4" { return "Exit" }
            default {
                Write-Host ""
                Write-Host "  Invalid selection." -ForegroundColor Red
                Start-Sleep -Milliseconds 900
            }
        }
    }
}

$script:ReportWidth = 94

function Write-ReportBorder {
    param(
        [ValidateSet("Top", "Sep", "Bot")]
        [string]$Type,
        [System.ConsoleColor]$Color = [System.ConsoleColor]::DarkGray
    )

    switch ($Type) {
        "Top" { Write-Host ("  +" + ("-" * $script:ReportWidth) + "+") -ForegroundColor $Color }
        "Sep" { Write-Host ("  +" + ("-" * $script:ReportWidth) + "+") -ForegroundColor $Color }
        "Bot" { Write-Host ("  +" + ("-" * $script:ReportWidth) + "+") -ForegroundColor $Color }
    }
}

function Write-ReportText {
    param(
        [string]$Text,
        [System.ConsoleColor]$TextColor = [System.ConsoleColor]::White,
        [System.ConsoleColor]$BorderColor = [System.ConsoleColor]::DarkGray
    )

    if ($Text.Length -gt $script:ReportWidth) {
        $Text = $Text.Substring(0, $script:ReportWidth - 3) + "..."
    }
    $padding = [Math]::Max(0, $script:ReportWidth - $Text.Length)
    Write-Host "  |" -ForegroundColor $BorderColor -NoNewline
    Write-Host $Text -ForegroundColor $TextColor -NoNewline
    Write-Host (" " * $padding + "|") -ForegroundColor $BorderColor
}

function Write-ReportRow {
    param(
        [string]$Label,
        [string]$Value,
        [System.ConsoleColor]$LabelColor = [System.ConsoleColor]::DarkGray,
        [System.ConsoleColor]$ValueColor = [System.ConsoleColor]::White,
        [System.ConsoleColor]$BorderColor = [System.ConsoleColor]::DarkGray
    )

    $text = $Label + $Value
    if ($text.Length -gt $script:ReportWidth) {
        $valueBudget = [Math]::Max(0, $script:ReportWidth - $Label.Length - 3)
        if ($Value.Length -gt $valueBudget) {
            $Value = $Value.Substring(0, $valueBudget) + "..."
        }
    }

    $padding = [Math]::Max(0, $script:ReportWidth - $Label.Length - $Value.Length)
    Write-Host "  |" -ForegroundColor $BorderColor -NoNewline
    Write-Host $Label -ForegroundColor $LabelColor -NoNewline
    Write-Host $Value -ForegroundColor $ValueColor -NoNewline
    Write-Host (" " * $padding + "|") -ForegroundColor $BorderColor
}

function Add-HashSetValues {
    param(
        [System.Collections.Generic.HashSet[string]]$Set,
        [string[]]$Values
    )

    foreach ($value in $Values) {
        [void]$Set.Add($value)
    }
}

function Get-MinecraftJavaProcessInfo {
    $results = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[int]]::new()
    $javaProcesses = @(Get-Process javaw -ErrorAction SilentlyContinue) + @(Get-Process java -ErrorAction SilentlyContinue)
    foreach ($proc in $javaProcesses) {
        if (-not $seen.Add($proc.Id)) { continue }
        try {
            $wmi = Get-WmiObject Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction Stop
            if ($wmi.CommandLine -match "net\.minecraft|Minecraft") {
                $results.Add([PSCustomObject]@{
                    PID            = $proc.Id
                    ProcessName    = $proc.ProcessName
                    StartTime      = $proc.StartTime
                    WorkingSet64   = $proc.WorkingSet64
                    CommandLine    = $wmi.CommandLine
                    ExecutablePath = $wmi.ExecutablePath
                })
            }
        } catch {}
    }
    return $results
}

function Get-CommandLineOptionValue {
    param(
        [string]$CommandLine,
        [string]$OptionName
    )

    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
    $escaped = [regex]::Escape($OptionName)
    $match = [regex]::Match($CommandLine, "(?i)(?:^|\s)$escaped(?:=|\s+)(?:""([^""]+)""|([^\s""]+))")
    if (-not $match.Success) { return $null }
    if ($match.Groups[1].Success) { return $match.Groups[1].Value }
    return $match.Groups[2].Value
}

function Get-JvmPropertyValue {
    param(
        [string]$CommandLine,
        [string]$PropertyName
    )

    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
    $escaped = [regex]::Escape($PropertyName)
    $match = [regex]::Match($CommandLine, "(?i)(?:^|\s)-D$escaped=(?:""([^""]+)""|([^\s""]+))")
    if (-not $match.Success) { return $null }
    if ($match.Groups[1].Success) { return $match.Groups[1].Value }
    return $match.Groups[2].Value
}

function Convert-ToComparablePath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    try {
        return ([System.IO.Path]::GetFullPath($Path.Trim('"')).TrimEnd("\", "/"))
    } catch {
        return $Path.Trim('"').TrimEnd("\", "/")
    }
}

function Test-SamePath {
    param(
        [string]$Left,
        [string]$Right
    )

    $leftPath = Convert-ToComparablePath -Path $Left
    $rightPath = Convert-ToComparablePath -Path $Right
    return [string]::Equals($leftPath, $rightPath, [System.StringComparison]::OrdinalIgnoreCase)
}

function Split-ModPathList {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
    return @($Value -split "[;,]" | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Resolve-LivePathCandidate {
    param(
        [string]$PathText,
        [string]$BasePath
    )

    if ([string]::IsNullOrWhiteSpace($PathText)) { return $null }
    $expanded = [Environment]::ExpandEnvironmentVariables($PathText.Trim().Trim('"'))
    if ([System.IO.Path]::IsPathRooted($expanded)) { return $expanded }
    if (-not [string]::IsNullOrWhiteSpace($BasePath)) {
        return (Join-Path $BasePath $expanded)
    }
    return $expanded
}

function Add-LiveMinecraftModSource {
    param(
        [System.Collections.Generic.List[object]]$Sources,
        [System.Collections.Generic.HashSet[string]]$Seen,
        [string]$Path,
        [string]$Source,
        [int]$ProcessId,
        [datetime]$StartTime
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path $Path -PathType Container)) { return }
    $key = Convert-ToComparablePath -Path $Path
    if (-not $Seen.Add($key)) { return }

    $jarCount = 0
    try {
        $jarCount = @(Get-ChildItem -Path $Path -Filter *.jar -File -ErrorAction Stop).Count
    } catch {}

    $Sources.Add([PSCustomObject]@{
        Path      = $Path
        Source    = $Source
        PID       = $ProcessId
        StartTime = $StartTime
        JarCount  = $jarCount
    })
}

function Get-LiveMinecraftModSources {
    $sources = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $minecraftProcesses = @(Get-MinecraftJavaProcessInfo | Sort-Object StartTime -Descending)

    foreach ($minecraftProcess in $minecraftProcesses) {
        $commandLine = [string]$minecraftProcess.CommandLine
        $gameDir = Get-CommandLineOptionValue -CommandLine $commandLine -OptionName "--gameDir"
        if (-not $gameDir) {
            $gameDir = Get-CommandLineOptionValue -CommandLine $commandLine -OptionName "--workDir"
        }
        $gameDir = Resolve-LivePathCandidate -PathText $gameDir -BasePath $null

        if ($gameDir) {
            Add-LiveMinecraftModSource -Sources $sources -Seen $seen `
                -Path (Join-Path $gameDir "mods") `
                -Source "--gameDir for PID $($minecraftProcess.PID)" `
                -ProcessId $minecraftProcess.PID `
                -StartTime $minecraftProcess.StartTime
        }

        foreach ($propertyName in @(
            "fabric.modsDir",
            "fabric.addMods",
            "fabric.loadMods",
            "forge.modDir",
            "forge.modsDirectories",
            "forge.addMods",
            "forge.mods"
        )) {
            $propertyValue = Get-JvmPropertyValue -CommandLine $commandLine -PropertyName $propertyName
            foreach ($part in (Split-ModPathList -Value $propertyValue)) {
                $candidate = Resolve-LivePathCandidate -PathText $part -BasePath $gameDir
                if ($candidate -and (Test-Path $candidate -PathType Leaf) -and [System.IO.Path]::GetExtension($candidate).Equals(".jar", [System.StringComparison]::OrdinalIgnoreCase)) {
                    $candidate = Split-Path -Parent $candidate
                }
                Add-LiveMinecraftModSource -Sources $sources -Seen $seen `
                    -Path $candidate `
                    -Source "-D$propertyName for PID $($minecraftProcess.PID)" `
                    -ProcessId $minecraftProcess.PID `
                    -StartTime $minecraftProcess.StartTime
            }
        }
    }

    return @($sources | Sort-Object @{ Expression = { $_.JarCount -gt 0 }; Descending = $true }, StartTime -Descending)
}

function Get-LiveMinecraftModsPath {
    $sources = @(Get-LiveMinecraftModSources)
    if ($sources.Count -eq 0) { return $null }
    return ($sources | Select-Object -First 1)
}

function Get-MinecraftStatus {
    $mc = Get-MinecraftJavaProcessInfo | Select-Object -First 1
    if ($null -ne $mc) {
        $uptime = (Get-Date) - $mc.StartTime
        $minutes = [Math]::Floor($uptime.TotalMinutes)
        $ram = [Math]::Round($mc.WorkingSet64 / 1MB, 0)
        return [PSCustomObject]@{
            Running = $true
            PID     = $mc.PID
            Uptime  = "$minutes min"
            RAM     = "$ram MB"
        }
    }

    return [PSCustomObject]@{
        Running = $false
        PID     = 0
        Uptime  = "-"
        RAM     = "-"
    }
}

$script:cleanModWhitelist = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
Add-HashSetValues -Set $script:cleanModWhitelist -Values @(
    "sodium","lithium","iris","fabric-api","modmenu","ferrite-core","lazydfu","starlight",
    "entityculling","memoryleakfix","krypton","c2me-fabric","smoothboot-fabric","immediatelyfast",
    "noisium","indium","sodium-extra","rei","jei","appleskin","dynamic-fps","fpsreducer",
    "IAS","IAS-Fabric","ias","ias-fabric","optiboxes","ukulib","TierTagger","tiertagger",
    "silicon","Silicon","motionblur","ravenclawspingequalizer","threadtweak","entity_texture_features",
    "citresewn","rendervis","modelfix","phosphor","noisium","immediatelyfast",
    "creamykeys","CreamyKeys","vmp","vmp-fabric","lithium","journeymap","xaerominimap","xaeroworldmap",
    "betterthirdperson","carpet","tweakeroo","syncmatica","minihud","litematica","malilib",
    "replaymod","optifine","optifabric","continuity","lambdynamiclights","wthit","jade",
    "architectury","cloth-config","kotlin-for-forge","geckolib","patchouli",
    "yetanotherconfiglib","yet-another-config-lib","yaclv3","yacl",
    "modernfix","modern-fix","voicechat","simple-voice-chat","notenoughanimations",
    "shulkerboxtooltip","satin","celestial","morechathistory","wi-zoom","wizoom",
    "crosshairaddons","armor-hud-numbers","ukus-armor-hud","totemtweaks",
    "ferritecore","ferrite-core"
)

function Get-ModBaseName {
    param([string]$FileName)

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $baseName = $baseName -replace '[-_][0-9][0-9A-Za-z.\-+_]*$', ''
    return $baseName.ToLowerInvariant()
}

$script:suspiciousPatterns = @(
    "AimAssist","AutoAnchor","AutoCrystal","AutoDoubleHand","AutoHitCrystal","AutoPot","AutoTotem","AutoArmor","InventoryTotem",
    "JumpReset","LegitTotem","PingSpoof","SelfDestruct","ShieldBreaker","TriggerBot","AxeSpam","WebMacro",
    "WalskyOptimizer","WalksyOptimizer","walsky.optimizer","WalksyCrystalOptimizerMod","Donut","Replace Mod",
    "ShieldDisabler","SilentAim","Totem Hit","Wtap","FakeLag","BlockESP","dev.krypton","Virgin","AntiMissClick",
    "LagReach","PopSwitch","SprintReset","ChestSteal","AntiBot","AirAnchor","FakeInv","HoverTotem","AutoClicker",
    "PackSpoof","Antiknockback","catlean","Argon","AuthBypass","Asteria","Prestige","MaceSwap","DoubleAnchor",
    "AutoTPA","BaseFinder","Xenon","gypsy","imgui","imgui.gl3","imgui.glfw","BowAim","Criticals","Fakenick",
    "FakeItem","invsee","ItemExploit","Hellion","hellion","LicenseCheckMixin","obfuscatedAuth","phantom-refmap.json","xyz.greaj",
    "org.chainlibs.module.impl.modules.Crystal.Y","org.chainlibs.module.impl.modules.Crystal.bF",
    "org.chainlibs.module.impl.modules.Crystal.bM","org.chainlibs.module.impl.modules.Crystal.bY",
    "org.chainlibs.module.impl.modules.Crystal.bq","org.chainlibs.module.impl.modules.Crystal.cv",
    "org.chainlibs.module.impl.modules.Crystal.o","org.chainlibs.module.impl.modules.Blatant.I",
    "org.chainlibs.module.impl.modules.Blatant.bR","org.chainlibs.module.impl.modules.Blatant.bx",
    "org.chainlibs.module.impl.modules.Blatant.cj","org.chainlibs.module.impl.modules.Blatant.dk"
)

$script:cheatStrings = @(
    "AutoCrystal","autocrystal","auto crystal","cw crystal","dontPlaceCrystal","dontBreakCrystal",
    "AutoHitCrystal","autohitcrystal","canPlaceCrystalServer","healPotSlot",
    "AutoAnchor","autoanchor","auto anchor","DoubleAnchor","hasGlowstone","HasAnchor",
    "anchortweaks","anchor macro","safe anchor","safeanchor","SafeAnchor","AirAnchor","anchorMacro",
    "AutoTotem","autototem","auto totem","InventoryTotem","inventorytotem","HoverTotem","hover totem","legittotem",
    "AutoPot","autopot","auto pot","speedPotSlot","strengthPotSlot","AutoArmor","autoarmor","auto armor","AutoPotRefill",
    "preventSwordBlockBreaking","preventSwordBlockAttack","ShieldDisabler","ShieldBreaker","Breaking shield with axe...",
    "AutoDoubleHand","autodoublehand","auto double hand","Failed to switch to mace after axe!",
    "AutoMace","MaceSwap","SpearSwap","StunSlam","JumpReset","axespam","axe spam",
    "EndCrystalItemMixin","findKnockbackSword","attackRegisteredThisClick",
    "AimAssist","aimassist","aim assist","triggerbot","trigger bot","Silent Rotations","SilentRotations",
    "FakeInv","swapBackToOriginalSlot","FakeLag","fakePunch","Fake Punch",
    "webmacro","web macro","AntiWeb","AutoWeb","lvstrng","dqrkis",
    "WalksyCrystalOptimizerMod","WalksyOptimizer","WalskyOptimizer","autoCrystalPlaceClock",
    "AutoFirework","ElytraSwap","FastXP","FastExp","NoJumpDelay",
    "PackSpoof","Antiknockback","catlean","AuthBypass","obfuscatedAuth","LicenseCheckMixin",
    "BaseFinder","ItemExploit","FreezePlayer","LWFH Crystal","KeyPearl","LootYeeter","FastPlace","AutoBreach",
    "setBlockBreakingCooldown","getBlockBreakingCooldown","blockBreakingCooldown",
    "onBlockBreaking","setItemUseCooldown","setSelectedSlot","invokeDoAttack","invokeDoItemUse","invokeOnMouseButton",
    "onPushOutOfBlocks","onIsGlowing","Automatically switches to sword when hitting with totem",
    "arrayOfString","POT_CHEATS","Dqrkis Client","Entity.isGlowing","Activate Key","Click Simulation","On RMB",
    "No Count Glitch","No Bounce","NoBounce","Place Delay","Break Delay","Fast Mode","Place Chance",
    "Break Chance","Stop On Kill","damagetick","Anti Weakness","Particle Chance","Trigger Key",
    "Switch Delay","Totem Slot","Smooth Rotations","Use Easing","Easing Strength","While Use",
    "Glowstone Delay","Glowstone Chance","Explode Delay","Explode Chance","Explode Slot","Only Charge",
    "Anchor Macro","Reach Distance","Min Height","Min Fall Speed","Attack Delay","Breach Delay",
    "Require Elytra","Auto Switch Back","Check Line of Sight","Only When Falling","Require Crit",
    "Show Status Display","Stop On Crystal","Check Shield","On Pop","Check Players","Predict Crystals",
    "Check Aim","Check Items","Activates Above","Blatant","Force Totem","Stay Open For",
    "Auto Inventory Totem","Only On Pop","Vertical Speed","Hover Totem","Swap Speed","Strict One-Tick",
    "Mace Priority","Min Totems","Min Pearls","Totem First","Drop Interval","Random Pattern","Loot Yeeter",
    "Horizontal Aim Speed","Vertical Aim Speed","Include Head","Web Delay","Holding Web",
    "Not When Affects Player","Hit Delay","Require Hold Axe","placeInterval","breakInterval","stopOnKill",
    "activateOnRightClick","holdCrystal","Macro Key",
    "KillAura","ClickAura","MultiAura","ForceField","LegitAura","FINDING_SPAWNER","OPENING_SPAWNER","AimBot","AutoAim","SilentAim","AimLock","HeadSnap",
    "WAITING_SPAWNER_GUI","LOOTING_BONES","CLOSING_SPAWNER","ORDER_COMMAND","WAIT_ORDER_GUI",
    "SELECT_ORDER_ITEM","WAIT_DELIVERY_GUI","DELIVERING_BONES","WAIT_AFTER_DELIVERY_1",
    "CLOSING_DELIVERY","WAIT_AFTER_CLOSE_DELIVERY","WAIT_CONFIRM_GUI","WAIT_CONFIRM_SETTLE",
    "CLICK_CONFIRM_SLOT","WAIT_AFTER_CONFIRM_1","WAIT_AFTER_CONFIRM_2","WAIT_AFTER_CONFIRM_3",
    "DOUBLE_ESCAPE","DOUBLE_RIGHTCLICK_FIRST","DOUBLE_RIGHTCLICK_SECOND","POST_CYCLE_DELAY",
    "CrystalAura","AnchorAura","AnchorFill","AnchorPlace","BedAura","AutoBed","BedBomb","BedPlace",
    "BowAimbot","BowSpam","AutoBow","AutoCrit","CritBypass","AlwaysCrit","CriticalHit",
    "ReachHack","ExtendReach","LongReach","HitboxExpand","AntiKB","NoKnockback","GrimVelocity","GrimDisabler",
    "VelocitySpoof","KBReduce","OffhandTotem","TotemSwitch","AutoWeapon","AutoSword","AutoCity","Burrow","SelfTrap",
    "HoleFiller","AntiSurround","AntiBurrow","WTap","TargetStrafe","AutoGap","AutoPearl",
    "FlyHack","CreativeFlight","BoatFly","PacketFly","AirJump","SpeedHack","BHop","BunnyHop",
    "AntiFall","NoFallDamage","StepHack","FastClimb","AutoStep","HighStep","WaterWalk","LiquidWalk","LavaWalk",
    "NoSlow","NoSlowdown","NoWeb","NoSoulSand","WallHack","ElytraSpeed","InstantElytra",
    "ScaffoldWalk","FastBridge","AutoBridge","Nuker","NukerLegit","InstantBreak","GhostHand","NoSwing",
    "PlaceAssist","AirPlace","AutoPlace","InstantPlace","PlayerESP","MobESP","ItemESP","StorageESP","ChestESP",
    "Tracers","NameTagsHack","XRayHack","OreFinder","CaveFinder","OreESP","NewChunks","TunnelFinder",
    "TargetHUD","ReachDisplay","DoubleClicker","JitterClick","ButterflyClick","CPSBoost",
    "ChestStealer","InvManager","InvMovebypass","AutoSprint","AntiAFK","FakeLatency","FakePing",
    "SpoofRotation","PositionSpoof","GameSpeed","SpeedTimer",
    "GrimBypass","VulcanBypass","MatrixBypass","AACBypass","VerusDisabler","IntaveBypass","WatchdogBypass",
    "PacketMine","PacketWalk","PacketSneak","PacketCancel","PacketDupe","PacketSpam",
    "SelfDestruct","HideClient","SessionStealer","TokenLogger","TokenGrabber","DiscordToken",
    "ReverseShell","C2Server","KeyLogger","StashFinder","TrailFinder",
    "imgui.binding","imgui.gl3","imgui.glfw","JNativeHook","GlobalScreen","NativeKeyListener",
    "client-refmap.json","cheat-refmap.json","phantom-refmap.json",
    "aHR0cDovL2FwaS5ub3ZhY2xpZW50LmxvbC93ZWJob29rLnR4dA==",
    "meteordevelopment","cc/novoline","com/alan/clients","club/maxstats","wtf/moonlight",
    "me/zeroeightsix/kami","net/ccbluex","today/opai","net/minecraft/injection",
    "org/chainlibs/module/impl/modules","xyz/greaj","com/cheatbreaker",
    "doomsdayclient","DoomsdayClient","doomsday.jar","novaclient","api.novaclient.lol",
    "WalksyOptimizer","vape.gg","vapeclient","VapeClient","VapeLite","intent.store","IntentClient",
    "rise.today","riseclient.com","meteor-client","meteorclient","meteordevelopment.meteorclient",
    "liquidbounce","fdp-client","net.ccbluex","novoware","novoclient","aristois","impactclient","azura",
    "pandaware","moonClient","astolfo","futureClient","konas","rusherhack","inertia","exhibition",
    "sessionstealer","tokengrabber","webhookstealer","cookiethief","discordstealer","keylogger",
    "iplogger","cryptominer","reverseShell","backdoormod","exploitmod","ratmod","ransomware",
    "sendWebhook","exfiltrate","connectBack","callHome","grabToken","stealSession","accountstealer",
    "discord/token","grabber/cookie","grab_cookies","stealerutils","sendToWebhook","postDiscord",
    "webhookurl","discordwebhook",
    "crasher","lagmachine","booksploit","signcrasher","entityspammer","nukermod","worldnuker",
    "tntmod","bedexplode","anchorexplode","injectClass","modifyBytecode","hookMethod",
    "attachAgent","VirtualMachine.attach",
    "FLOW_OBFUSCATION","STRING_ENCRYPTION","RESOURCE_ENCRYPTION",
    "skidfuscator","me/itzsomebody","radon/transform","bozar/","paramorphism","zelix/klassmaster",
    "allatori","dasho","com/icqm/smoke","dev.krypton","dev.gambleclient","com.cheatbreaker",
    "spoofVersion","brandOverride","overrideBrand","fakeClientBrand","brandSpoof","versionSpoof",
    "cancelPacket","dropPacket","suppressPacket","blockPacket","spoofPacket","injectPacket",
    "sendFakePacket","sendSilentPacket","bypassAC","bypass_ac","evadeAC","evadeAnticheat",
    "isGrimAC","isNoCheat","isAAC","isSpartanAC","isIntave","grimBypass","ncpBypass","aacBypass",
    "spartanBypass","checkAnticheat","detectAnticheat","getAnticheat","GrimBypass","NCPBypass",
    "AACBypass","IntaveBypass",
    "setTimerSpeed","timerSpeed","Timer.timerSpeed","setTickRate",
    "overrideTickRate","fakeTickCount","tickBoost","hitboxExpand","expandHitbox",
    "suppressKnockback","cancelKnockback","noKnockback","setVelocity(0","zeroVelocity","ignoreKnockback",
    "antiKnockback","KnockbackModifier","noVelocity",
    "renderPlayerSpoofed","spoofRender","hideFromRender",
    "fakeGlowing","GlowBypass","glowBypass","baritone.bypass","pathfindBypass","suppressPathfind",
    "bypassLicense","fakeAuth","spoofSession","AltManager","grimac","GrimAC","grim-api","ac.grim",
    "game.grim","setGrimFlag","rotationBypass","fakeYaw","fakePitch","spoofYaw","spoofPitch"
)

$script:contextOnlyStrings = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
Add-HashSetValues -Set $script:contextOnlyStrings -Values @(
    "HttpClient","HttpURLConnection","openConnection","URLConnection",
    "getOutputStream","getInputStream","ProcessBuilder","powershell.exe",
    "Runtime.exec","cmd.exe"
)

$script:knownCheatFileTokens = @(
    "doomsday","doomsdayclient","dqrkis","dqrk",
    "vape","vapeclient","vape-client","vapelite",
    "meteor","meteorclient","meteor-client",
    "liquidbounce","liquid-bounce",
    "wurst","wurst-client",
    "futureclient","future-client",
    "konas","inertia","exhibition",
    "pandaware","astolfo","rusherhack",
    "novaclient","nova-client","novaware",
    "impactclient","aristois","azura",
    "intentclient","intentstore",
    "prestigeclient",
    "cheatbreaker","kamiblue","fdpclient",
    "skidfuscator","skidware",
    "wolframclient","wolfram-client",
    "bleachhack","bleach-hack",
    "themisclient","ravenb",
    "fluxclient","flux-client",
    "strafeclient","strafe-client"
)

$script:cheatMixinSignatures = @(
    "MultiPlayerGameModeMixin",
    "ClientPlayerInteractionManagerMixin",
    "CombatTrackerMixin",
    "SwordItemMixin",
    "AxeItemMixin",
    "ShieldItemMixin",
    "EndCrystalEntityMixin",
    "ExplosionMixin",
    "ExplosionMixinAccessor",
    "RespawnAnchorBlockMixin",
    "BedBlockMixin",
    "MovementInputMixin",
    "ClientConnectionMixin",
    "NetworkHandlerMixin",
    "ChunkDeltaUpdateS2CPacketMixin",
    "PlayerMoveC2SPacketMixin"
)

$script:suspiciousRefmapPattern = '"refmap"\s*:\s*"(cheat|hack|phantom|ghost|shadow|xray|aimbot|killaura)[^"]*"'

$script:bytecodeHookSignatures = @(
    "invokeAttackEntity","invokeUseItem","invokeStopUsingItem","callAttackEntity","callUseItem",
    "invokeDoAttack","invokeDoItemUse","invokeOnMouseButton",
    "getAttackCooldownProgress","resetLastAttackedTicks","setItemUseCooldown",
    "setSelectedSlot","setCurrentItem","switchToSlot",
    "setVelocity(0","addVelocity(0","motionX = 0","motionZ = 0",
    "Timer.timerSpeed","setTimerSpeed","timerSpeed","tickLength",
    "cancelPacket","dropPacket","suppressPacket","injectPacket","spoofPacket",
    "sendFakePacket","sendSilentPacket",
    "VirtualMachine.attach","attachAgent","agentmain","premain"
)

$script:networkExfilSignatures = @(
    "discord.com/api/webhooks","discordapp.com/api/webhooks",
    "sendWebhook","postToWebhook","webhookUrl","WEBHOOK_URL","discordWebhook",
    "grabToken","stealSession","TokenGrabber","SessionStealer","CookieThief",
    "grabify","iplogger.org","2no.co","leakinfo.org","blasze.tk",
    "canarytokens","whereismyip",
    "pastebin.com/raw","hastebin.com/raw","ghostbin.com",
    "api.novaclient.lol","vape.gg/api","intent.store/api","rise.today/api",
    "liquidbounce.net/api","meteordevelopment.org","rusherhack.org/api",
    "exfiltrate","connectBack","callHome","reverseShell","C2Server","c2server",
    "sendToServer(","postData(","uploadData("
)

$script:deepCheatStrings = @(
    "invokeAttackEntity","invokeUseItem","invokeStopUsingItem","callAttackEntity","callUseItem",
    "getAttackCooldownProgress","resetLastAttackedTicks","ModuleManager","FeatureManager","HackList",
    "CommandManager.register","GuiHacks","ClickGui","AltManager","SessionStealer","spoofPacket",
    "cancelPacket","dropPacket","CPacketHeldItemChange","ServerboundMovePlayerPacket","Timer.timerSpeed",
    "timerSpeed","setTimerSpeed",
    "com.sun.jndi.rmi.object.trustURLCodebase=true","com.sun.jndi.ldap.object.trustURLCodebase=true",
    "-Xrunjdwp:","agentlib:jdwp",
    "dev.gambleclient","xyz.greaj","org.chainlibs","dev.krypton","Dqrkis","dqrkis","lvstrng",
    "Unsafe.getUnsafe",
    "setHardTarget","mixinBypass",
    "defineClass(","VirtualMachine.attach","agentmain(",
    "discord.com/api/webhooks","discordapp.com/api/webhooks",
    "pastebin.com/raw","grabify","iplogger.org",
    "EndCrystalEntityMixin","ExplosionMixinAccessor",
    "ModuleManager","HackManager","CheatManager",
    "toggleModule","isModuleEnabled","getModule(","registerModule(",
    "setTimerSpeed","timerBoost","tickBoost",
    "autocrystal.place","autocrystal.break","crystal.place.delay","crystal.break.delay"
)

$script:patternRegex = [regex]::new(
    "(?<![A-Za-z])(" + (($script:suspiciousPatterns | ForEach-Object { [regex]::Escape($_) }) -join "|") + ")(?![A-Za-z])",
    [System.Text.RegularExpressions.RegexOptions]::Compiled
)
$script:cheatStringSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
Add-HashSetValues -Set $script:cheatStringSet -Values $script:cheatStrings
$script:deepCheatStringSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
Add-HashSetValues -Set $script:deepCheatStringSet -Values $script:deepCheatStrings
$script:mixinSigSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
Add-HashSetValues -Set $script:mixinSigSet -Values $script:cheatMixinSignatures
$script:bytecodeSigSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
Add-HashSetValues -Set $script:bytecodeSigSet -Values $script:bytecodeHookSignatures
$script:networkExfilSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
Add-HashSetValues -Set $script:networkExfilSet -Values $script:networkExfilSignatures
$script:fullwidthRegex = [regex]::new("[\uFF21-\uFF3A\uFF41-\uFF5A\uFF10-\uFF19]{2,}", [System.Text.RegularExpressions.RegexOptions]::Compiled)
$script:tokenRegex = [regex]::new(
    "(?<![a-z])(" + (($script:knownCheatFileTokens | ForEach-Object { [regex]::Escape($_) }) -join "|") + ")(?![a-z])",
    [System.Text.RegularExpressions.RegexOptions]::Compiled
)

$script:disallowedMods = @{
    "auto-clicker"                 = @{ Names = @("Auto Clicker","AutoClicker","autoclicker","auto-clicker","Auto-Clicker") }
    "freecam"                      = @{ Names = @("Freecam","freecam","FreeCam","Free Cam") }
    "inventory-profiles-next"      = @{ Names = @("Inventory Profiles Next","InventoryProfilesNext","IPN") }
    "inventory-control-tweaks"     = @{ Names = @("Inventory Control Tweaks","InventoryControlTweaks") }
    "chestcleaner"                 = @{ Names = @("Chest Cleaner","ChestCleaner","chestcleaner") }
    "quickswap"                    = @{ Names = @("QuickSwap","Quick Swap","quickswap") }
    "autofish"                     = @{ Names = @("AutoFish","Auto Fish","autofish","auto-fish") }
    "autofarm"                     = @{ Names = @("AutoFarm","Auto Farm","autofarm") }
    "client-crafting"              = @{ Names = @("Client Crafting","ClientCrafting") }
    "enchant-order"                = @{ Names = @("Enchant Order","EnchantOrder") }
    "inventory-sorter"             = @{ Names = @("Inventory Sorter","InventorySorter") }
    "shoulder-surfing-reloaded"    = @{ Names = @("Shoulder Surfing","ShoulderSurfing","Shoulder Surfing Reloaded") }
    "camera-utils"                 = @{ Names = @("Camera Utils","CameraUtils") }
    "free-look"                    = @{ Names = @("FreeLook","Free Look","freelook","free-look") }
    "perspective-mod"              = @{ Names = @("Perspective Mod","PerspectiveMod","perspective-mod") }
    "freelook"                     = @{ Names = @("FreeLook","Freelook","free look") }
    "double-hotbar"                = @{ Names = @("Double Hotbar","DoubleHotbar") }
    "slot-cycler"                  = @{ Names = @("Slot Cycler","SlotCycler") }
    "elytrafly"                    = @{ Names = @("ElytraFly","Elytra Fly","elytrafly") }
    "toggle-sneak-sprint"          = @{ Names = @("Toggle Sneak","Toggle Sprint","ToggleSneak","ToggleSprint") }
    "quick-elytra"                 = @{ Names = @("Quick Elytra","QuickElytra") }
    "sprint-toggle"                = @{ Names = @("Sprint Toggle","SprintToggle","sprint-toggle") }
    "autosneak"                    = @{ Names = @("AutoSneak","Auto Sneak","autosneak") }
    "stepup"                       = @{ Names = @("StepUp","Step Up","stepup","step-up") }
    "noslow"                       = @{ Names = @("NoSlow","No Slow","noslow","no-slow","NoSlowMod") }
    "bridging-mod"                 = @{ Names = @("Bridging Mod","BridgingMod","SlothPixel") }
    "scaffold"                     = @{ Names = @("Scaffold","scaffold","ScaffoldMod") }
    "tower"                        = @{ Names = @("Tower","TowerMod","tower-mod") }
    "clickcrystals"                = @{ Names = @("ClickCrystals","clickcrystals","Click Crystals") }
    "walksycrystaloptimizer"       = @{ Names = @("WalksyCrystalOptimizer","WalksyOptimizer","WalskyOptimizer") }
    "hazel-crystal-optimizer"      = @{ Names = @("Hazel Crystal Optimizer","HazelCrystalOptimizer") }
    "switchtotems"                 = @{ Names = @("SwitchTotems","switchtotems","Switch Totems") }
    "no-delay-optimizer"           = @{ Names = @("No Delay Optimizer","NoDelayOptimizer","NoDelay") }
    "dokkos-hotbar-optimizer"      = @{ Names = @("Dokko's Hotbar Optimizer","DokkoHotbar") }
    "crystal-macro"                = @{ Names = @("Crystal Macro","CrystalMacro","crystal-macro") }
    "anchor-macro"                 = @{ Names = @("Anchor Macro","AnchorMacro","anchor-macro") }
    "totem-macro"                  = @{ Names = @("Totem Macro","TotemMacro","totem-macro") }
    "pot-macro"                    = @{ Names = @("Pot Macro","PotMacro","pot-macro","AutoPotMacro") }
    "combat-macro"                 = @{ Names = @("Combat Macro","CombatMacro","combat-macro") }
    "arrow-shifter"                = @{ Names = @("Arrow Shifter","ArrowShifter") }
    "d-hand"                       = @{ Names = @("D-hand","Dhand","D Hand") }
    "frostbyte-improved-inventory" = @{ Names = @("Frostbyte's Improved Inventory","FrostbyteInventory") }
    "fast-xp"                      = @{ Names = @("Fast Xp","FastXP","FastXp") }
    "quick-exp"                    = @{ Names = @("Quick Exp","QuickExp") }
    "xray"                         = @{ Names = @("XRay","xray","X-Ray","x-ray","XRayMod") }
    "cave-finder"                  = @{ Names = @("Cave Finder","CaveFinder","cave-finder") }
    "nofall"                       = @{ Names = @("NoFall","No Fall","nofall","no-fall","NoFallMod") }
    "killaura"                     = @{ Names = @("KillAura","killaura","Kill Aura","kill-aura") }
    "packetmod"                    = @{ Names = @("PacketMod","packet-mod","PacketManipulation") }
    "esp"                          = @{ Names = @("ESP","esp","EspMod","PlayerESP","esp-mod") }
    "speedhack"                    = @{ Names = @("SpeedHack","speedhack","speed-hack","SpeedMod") }
}

function Get-ShannonEntropy {
    param([byte[]]$Data)

    if ($Data.Length -eq 0) { return 0.0 }
    $freq = @{}
    foreach ($byte in $Data) {
        $freq[$byte] = ($freq[$byte] -as [int]) + 1
    }

    $entropy = 0.0
    $length = $Data.Length
    foreach ($count in $freq.Values) {
        $probability = $count / $length
        if ($probability -gt 0) {
            $entropy -= $probability * [Math]::Log($probability, 2)
        }
    }

    return [Math]::Round($entropy, 4)
}

function Get-Mod-Info-From-Jar {
    param([string]$JarPath)

    $result = [PSCustomObject]@{
        ModId = $null
        Name  = $null
    }

    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($JarPath)
        foreach ($entry in @(
            ($zip.Entries | Where-Object { $_.FullName -match "fabric\.mod\.json$" } | Select-Object -First 1),
            ($zip.Entries | Where-Object { $_.FullName -match "quilt\.mod\.json$" }  | Select-Object -First 1)
        )) {
            if ($null -eq $entry) { continue }
            try {
                $stream = $entry.Open()
                $buffer = New-Object System.IO.MemoryStream
                $stream.CopyTo($buffer)
                $stream.Close()
                $json = [System.Text.Encoding]::UTF8.GetString($buffer.ToArray())
                $buffer.Dispose()
                if ($json -match '"id"\s*:\s*"([^"]+)"') { $result.ModId = $Matches[1] }
                if ($json -match '"name"\s*:\s*"([^"]+)"') { $result.Name = $Matches[1] }
            } catch {}
        }

        $tomlEntry = $zip.Entries | Where-Object { $_.FullName -match "META-INF/mods\.toml$" } | Select-Object -First 1
        if ($tomlEntry -and -not $result.ModId) {
            try {
                $stream = $tomlEntry.Open()
                $buffer = New-Object System.IO.MemoryStream
                $stream.CopyTo($buffer)
                $stream.Close()
                $toml = [System.Text.Encoding]::UTF8.GetString($buffer.ToArray())
                $buffer.Dispose()
                if ($toml -match 'modId\s*=\s*"([^"]+)"') { $result.ModId = $Matches[1] }
                if ($toml -match 'displayName\s*=\s*"([^"]+)"') { $result.Name = $Matches[1] }
            } catch {}
        }

        $zip.Dispose()
    } catch {}

    return $result
}

function Invoke-MixinInjectionScan {
    param(
        [string]$FilePath,
        [bool]$IsWhitelisted
    )

    $hits = [System.Collections.Generic.List[string]]::new()
    if ($IsWhitelisted) { return $hits }

    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($FilePath)
        $mixinJsonEntries = @($zip.Entries | Where-Object { $_.FullName -match "\.mixins\.json$|mixin.*\.json$" })
        foreach ($mixinJsonEntry in $mixinJsonEntries) {
            try {
                $stream = $mixinJsonEntry.Open()
                $buffer = New-Object System.IO.MemoryStream
                $stream.CopyTo($buffer)
                $stream.Close()
                $text = [System.Text.Encoding]::UTF8.GetString($buffer.ToArray())
                $buffer.Dispose()

                $mixinMatches = [regex]::Matches($text, '"[A-Za-z][A-Za-z0-9_$]+"')
                if ($mixinMatches.Count -gt 200) {
                    $hits.Add("Excessive mixin count ($($mixinMatches.Count)) in $($mixinJsonEntry.FullName)")
                }
                foreach ($signature in $script:mixinSigSet) {
                    if ($text -match [regex]::Escape($signature)) {
                        $hits.Add("Cheat mixin target: $signature")
                    }
                }
                if ($text -match $script:suspiciousRefmapPattern) {
                    $hits.Add("Suspicious refmap name: $($Matches[1])")
                }
            } catch {}
        }

        $classEntries = @($zip.Entries | Where-Object { $_.FullName -match "\.class$" } | Select-Object -First 50)
        foreach ($classEntry in $classEntries) {
            try {
                $stream = $classEntry.Open()
                $buffer = New-Object System.IO.MemoryStream
                $stream.CopyTo($buffer)
                $stream.Close()
                $raw = $buffer.ToArray()
                $buffer.Dispose()
                $ascii = [System.Text.Encoding]::ASCII.GetString($raw)
                foreach ($signature in $script:mixinSigSet) {
                    if ($ascii.Contains($signature)) {
                        $hits.Add("Mixin bytecode hit: $signature")
                        break
                    }
                }
            } catch {}
        }

        $zip.Dispose()
    } catch {}

    return $hits
}

function Invoke-BytecodeHookScan {
    param(
        [string]$FilePath,
        [bool]$IsWhitelisted
    )

    $hits = [System.Collections.Generic.List[string]]::new()
    if ($IsWhitelisted) { return $hits }

    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($FilePath)
        $classes = @($zip.Entries | Where-Object { $_.FullName -match "\.class$" })
        $sampledClasses = $classes | Select-Object -First ([Math]::Min(60, $classes.Count))
        foreach ($classEntry in $sampledClasses) {
            try {
                $stream = $classEntry.Open()
                $buffer = New-Object System.IO.MemoryStream
                $stream.CopyTo($buffer)
                $stream.Close()
                $raw = $buffer.ToArray()
                $buffer.Dispose()
                $ascii = [System.Text.Encoding]::ASCII.GetString($raw)
                foreach ($signature in $script:bytecodeSigSet) {
                    if ($ascii.Contains($signature)) {
                        $hits.Add("Bytecode hook: $signature")
                        break
                    }
                }
                if ($ascii -match "defineClass" -and $ascii -match "ClassLoader" -and $ascii -notmatch "SecureClassLoader|URLClassLoader") {
                    $hits.Add("Dynamic class injection detected")
                }
            } catch {}
        }
        $zip.Dispose()
    } catch {}

    $unique = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($hit in $hits) {
        [void]$unique.Add($hit)
    }

    return [System.Collections.Generic.List[string]]$unique
}

function Invoke-NetworkExfilScan {
    param(
        [string]$FilePath,
        [bool]$IsWhitelisted
    )

    $hits = [System.Collections.Generic.List[string]]::new()
    if ($IsWhitelisted) { return $hits }

    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($FilePath)
        $scanExtensions = "\.(class|json|toml|yml|yaml|txt|cfg|properties|xml|html|js|kt|groovy)$|MANIFEST\.MF"
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -notmatch $scanExtensions) { continue }
            try {
                $stream = $entry.Open()
                $buffer = New-Object System.IO.MemoryStream
                $stream.CopyTo($buffer)
                $stream.Close()
                $raw = $buffer.ToArray()
                $buffer.Dispose()
                $ascii = [System.Text.Encoding]::ASCII.GetString($raw)
                $utf8 = [System.Text.Encoding]::UTF8.GetString($raw)
                foreach ($signature in $script:networkExfilSet) {
                    if ($ascii.Contains($signature) -or $utf8.Contains($signature)) {
                        $hits.Add("Network exfil: $signature")
                        break
                    }
                }
            } catch {}
        }
        $zip.Dispose()
    } catch {}

    $unique = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($hit in $hits) {
        [void]$unique.Add($hit)
    }

    return [System.Collections.Generic.List[string]]$unique
}

function Invoke-ObfuscationFlags {
    param([string]$FilePath)

    $flags = [System.Collections.Generic.List[string]]::new()
    $baseName = Get-ModBaseName -FileName ([System.IO.Path]::GetFileName($FilePath))
    $isWhitelisted = $script:cleanModWhitelist.Contains($baseName)

    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($FilePath)
        $modInfo = Get-Mod-Info-From-Jar -JarPath $FilePath
        $outerModId = $modInfo.ModId
        if ($outerModId -and $script:cleanModWhitelist.Contains($outerModId)) {
            $isWhitelisted = $true
        }

        $classes = @($zip.Entries | Where-Object { $_.FullName -match "\.class$" })
        $totalClassCount = $classes.Count
        if ($totalClassCount -eq 0) {
            $zip.Dispose()
            return $flags
        }

        $obfuscatedCount = 0
        $numericClassCount = 0
        $unicodeClassCount = 0

        foreach ($class in $classes) {
            $parts = $class.FullName.Split("/")
            $folderParts = @()
            if ($parts.Count -gt 1) {
                $folderParts = $parts[0..($parts.Count - 2)]
            }
            $isObfuscated = ($folderParts | Where-Object { $_.Length -le 1 -and $_ -cmatch "^[a-z]$" }).Count -ge 2
            if ($isObfuscated) { $obfuscatedCount++ }

            $className = [System.IO.Path]::GetFileNameWithoutExtension($class.Name)
            if ($className -cmatch "^\d+$") { $numericClassCount++ }
            if ($className -match "[^\x00-\x7F]") { $unicodeClassCount++ }
        }

        $obfPct = if ($totalClassCount -ge 10) { [Math]::Round(($obfuscatedCount / $totalClassCount) * 100) } else { 0 }
        $numPct = if ($totalClassCount -ge 5) { [Math]::Round(($numericClassCount / $totalClassCount) * 100) } else { 0 }
        $uniPct = if ($totalClassCount -ge 5) { [Math]::Round(($unicodeClassCount / $totalClassCount) * 100) } else { 0 }

        $runtimeExecFound = $false
        $httpDownloadFound = $false
        $httpExfilFound = $false
        $sampled = $classes | Select-Object -First ([Math]::Min(30, $totalClassCount))
        foreach ($classEntry in $sampled) {
            try {
                $stream = $classEntry.Open()
                $buffer = New-Object System.IO.MemoryStream
                $stream.CopyTo($buffer)
                $stream.Close()
                $raw = $buffer.ToArray()
                $buffer.Dispose()
                $ascii = [System.Text.Encoding]::ASCII.GetString($raw)
                if ($ascii -match "Runtime\.exec") { $runtimeExecFound = $true }
                if ($ascii -match "openConnection|getOutputStream") { $httpDownloadFound = $true }
                if ($ascii -match "setRequestMethod.*POST") { $httpExfilFound = $true }
            } catch {}
        }

        if (-not $isWhitelisted) {
            if ($runtimeExecFound -and $obfPct -ge 25) { $flags.Add("Runtime.exec() in obfuscated code") }
            if ($httpDownloadFound -and $obfPct -ge 20) { $flags.Add("HTTP file download in obfuscated code") }
            if ($httpExfilFound) { $flags.Add("HTTP POST exfiltration") }
        }
        if ($totalClassCount -ge 10 -and $obfPct -ge 25) { $flags.Add("Heavy obfuscation - $obfPct% of classes use single-letter path segments") }
        if ($numPct -ge 20) { $flags.Add("Numeric class names - $numPct% of classes are numeric only") }
        if ($uniPct -ge 10) { $flags.Add("Unicode class names - $uniPct% of classes use non-ASCII characters") }

        $knownLegitModIds = @(
            "vmp-fabric","vmp","lithium","sodium","iris","fabric-api","modmenu","ferrite-core",
            "lazydfu","starlight","entityculling","memoryleakfix","krypton","c2me-fabric","smoothboot-fabric",
            "immediatelyfast","noisium","threadtweak","indium","rendervis","entity_texture_features",
            "citresewn","sodium-extra","rei","jei","journeymap","xaerominimap","xaeroworldmap","lithium",
            "phosphor","appleskin","modelfix","dynamic-fps","betterthirdperson","fpsreducer",
            "motionblur","ravenclawspingequalizer","silicon","creamykeys","carpet","malilib"
        )

        $dangerCount = ($flags | Where-Object { $_ -match "Runtime\.exec|HTTP file download|HTTP POST|Heavy obfuscation" }).Count
        if ($outerModId -and ($knownLegitModIds -contains $outerModId) -and $dangerCount -gt 0) {
            $flags.Add("Fake mod identity - claims to be '$outerModId' but contains dangerous code")
        }

        $obfuscatorSignatures = @{
            "Allatori"     = "Allatori"
            "Zelix"        = "Zelix"
            "ProGuard"     = "Obfuscated-By: ProGuard"
            "Stringer"     = "Stringer Java Obfuscator"
            "Skidfuscator" = "skidfuscator"
            "Radon"        = "Obfuscated-By: Radon"
            "BisGuard"     = "BisGuard"
            "Paramorphism" = "paramorphism"
        }
        foreach ($entry in ($zip.Entries | Where-Object { $_.FullName -match "MANIFEST\.MF$|\.json$|\.toml$" })) {
            try {
                $stream = $entry.Open()
                $buffer = New-Object System.IO.MemoryStream
                $stream.CopyTo($buffer)
                $stream.Close()
                $text = [System.Text.Encoding]::UTF8.GetString($buffer.ToArray())
                $buffer.Dispose()
                foreach ($pair in $obfuscatorSignatures.GetEnumerator()) {
                    if ($text -match [regex]::Escape($pair.Value)) {
                        $flags.Add("Obfuscator marker: $($pair.Key)")
                    }
                }
            } catch {}
        }

        $encMarkers = @("decrypt","deobf","StringEncryption","StringDecryptor","decryptString","stringPool","StringPool")
        $encCount = 0
        foreach ($classEntry in ($classes | Select-Object -First 20)) {
            try {
                $stream = $classEntry.Open()
                $buffer = New-Object System.IO.MemoryStream
                $stream.CopyTo($buffer)
                $stream.Close()
                $ascii = [System.Text.Encoding]::ASCII.GetString($buffer.ToArray())
                $buffer.Dispose()
                foreach ($marker in $encMarkers) {
                    if ($ascii -match $marker) {
                        $encCount++
                        break
                    }
                }
            } catch {}
        }
        if ($encCount -ge 5) { $flags.Add("String encryption detected in $encCount class(es)") }

        $zip.Dispose()
    } catch {}

    return $flags
}

function Get-ModSignature {
    param(
        [string]$Path,
        [bool]$ScanStrings = $true,
        [bool]$ScanDeep = $true
    )

    $hits = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $entropyWarnings = [System.Collections.Generic.List[string]]::new()

    $baseName = Get-ModBaseName -FileName ([System.IO.Path]::GetFileName($Path))
    $isWhitelisted = $script:cleanModWhitelist.Contains($baseName)

    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        $modInfo = Get-Mod-Info-From-Jar -JarPath $Path
        if ($modInfo.ModId -and $script:cleanModWhitelist.Contains($modInfo.ModId)) {
            $isWhitelisted = $true
        }

        foreach ($entry in $zip.Entries) {
            foreach ($match in $script:patternRegex.Matches($entry.FullName)) {
                [void]$hits.Add("P|$($match.Value)")
            }
        }

        $flatEntries = [System.Collections.Generic.List[object]]::new()
        $nestedArchives = [System.Collections.Generic.List[object]]::new()
        foreach ($entry in $zip.Entries) {
            $flatEntries.Add($entry)
        }

        foreach ($nestedJar in ($zip.Entries | Where-Object { $_.FullName -match "^META-INF/jars/.+\.jar$" })) {
            try {
                $nestedStream = $nestedJar.Open()
                $memoryStream = New-Object System.IO.MemoryStream
                $nestedStream.CopyTo($memoryStream)
                $nestedStream.Close()
                $memoryStream.Position = 0
                $innerZip = [System.IO.Compression.ZipArchive]::new($memoryStream, [System.IO.Compression.ZipArchiveMode]::Read)
                $nestedArchives.Add($innerZip)
                foreach ($innerEntry in $innerZip.Entries) {
                    $flatEntries.Add($innerEntry)
                }
            } catch {}
        }

        $scanExtensions = "\.(class|json|toml|yml|yaml|txt|cfg|properties|xml|html|js|ts|kt|groovy)$|MANIFEST\.MF"
        foreach ($entry in $flatEntries) {
            if ($entry.FullName -notmatch $scanExtensions) { continue }
            try {
                $stream = $entry.Open()
                $buffer = New-Object System.IO.MemoryStream
                $stream.CopyTo($buffer)
                $stream.Close()
                $raw = $buffer.ToArray()
                $buffer.Dispose()

                $ascii = [System.Text.Encoding]::ASCII.GetString($raw)
                $utf8 = [System.Text.Encoding]::UTF8.GetString($raw)
                foreach ($match in $script:patternRegex.Matches($ascii)) {
                    [void]$hits.Add("P|$($match.Value)")
                }

                if ($ScanStrings -and -not $isWhitelisted) {
                    foreach ($cheatString in $script:cheatStringSet) {
                        if ($script:contextOnlyStrings.Contains($cheatString)) { continue }
                        if ($ascii.Contains($cheatString) -or $utf8.Contains($cheatString)) {
                            [void]$hits.Add("S|$cheatString")
                        }
                    }

                    foreach ($match in $script:fullwidthRegex.Matches($utf8)) {
                        [void]$hits.Add("F|$($match.Value)")
                    }
                }

                if ($ScanDeep -and -not $isWhitelisted) {
                    foreach ($deepString in $script:deepCheatStringSet) {
                        if ($script:contextOnlyStrings.Contains($deepString)) { continue }
                        if ($ascii.Contains($deepString) -or $utf8.Contains($deepString)) {
                            [void]$hits.Add("D|$deepString")
                        }
                    }

                    if ($entry.FullName -match "\.class$" -and $raw.Length -gt 512) {
                        $entropy = Get-ShannonEntropy -Data $raw
                        if ($entropy -gt 7.2) {
                            $shortName = [System.IO.Path]::GetFileName($entry.FullName)
                            $entropyWarnings.Add("HIGH_ENTROPY:$shortName($entropy)")
                        }
                    }
                }
            } catch {}
        }

        foreach ($archive in $nestedArchives) {
            try { $archive.Dispose() } catch {}
        }
        $zip.Dispose()
    } catch {}

    $fullwidthPool = @($script:cheatStrings | Where-Object { $_ -cmatch "[\uFF21-\uFF3A\uFF41-\uFF5A\uFF10-\uFF19]" })
    foreach ($hit in @($hits)) {
        if ($hit -match "^F\|") {
            $fullwidthHit = $hit.Substring(2)
            if ($fullwidthHit.Length -lt 3) { continue }

            $bestMatch = $null
            foreach ($candidate in $fullwidthPool) {
                if ($candidate.Contains($fullwidthHit)) {
                    if ($null -eq $bestMatch -or $candidate.Length -lt $bestMatch.Length) {
                        $bestMatch = $candidate
                    }
                }
            }

            $final = if ($bestMatch) {
                $bestMatch
            } elseif ($fullwidthHit.Length -ge 6) {
                $fullwidthHit
            } else {
                $null
            }

            if ($final) {
                $hits.Remove($hit)
                [void]$hits.Add("F|$final")
            }
        }
    }

    $fullwidthFinal = @($hits | Where-Object { $_ -match "^F\|" } | ForEach-Object { $_.Substring(2) })
    $fullwidthUnique = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($fullwidthValue in $fullwidthFinal) {
        $isRedundant = $false
        foreach ($otherValue in $fullwidthFinal) {
            if ($fullwidthValue.Length -lt $otherValue.Length -and $otherValue.Contains($fullwidthValue)) {
                $isRedundant = $true
                break
            }
        }
        if (-not $isRedundant) {
            [void]$fullwidthUnique.Add($fullwidthValue)
        }
    }

    $cleaned = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($hit in $hits) {
        if ($hit -match "^F\|") {
            if ($fullwidthUnique.Contains($hit.Substring(2))) {
                [void]$cleaned.Add($hit)
            }
        } else {
            [void]$cleaned.Add($hit)
        }
    }

    foreach ($warning in $entropyWarnings) {
        [void]$cleaned.Add("E|$warning")
    }

    return $cleaned
}

function Get-ModSources {
    param([string]$Path)

    $urls = [System.Collections.Generic.List[string]]::new()
    $blacklist = @(
        "w3\.org","jsonschema\.org","fabricmc\.net","quiltmc\.net","oracle\.com","mojang\.com",
        "minecraft\.net","isxander\.dev","github\.com"
    )

    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -match "\.(json|toml|yml|yaml)$|MANIFEST\.MF") {
                try {
                    $stream = $entry.Open()
                    $buffer = New-Object System.IO.MemoryStream
                    $stream.CopyTo($buffer)
                    $stream.Close()
                    $raw = [System.Text.Encoding]::UTF8.GetString($buffer.ToArray())
                    $buffer.Dispose()
                    $matches = [regex]::Matches($raw, "https?://[^\s<>]+")
                    foreach ($match in $matches) {
                        $url = $match.Value.TrimEnd("\", ",", ")", "}", '"')
                        $isBlocked = $false
                        foreach ($blocked in $blacklist) {
                            if ($url -match $blocked) {
                                $isBlocked = $true
                                break
                            }
                        }
                        if (-not $isBlocked -and $url -notmatch "\.(png|jpg|jpeg|gif|svg)$") {
                            $urls.Add($url)
                        }
                    }
                } catch {}
            }
        }
        $zip.Dispose()
    } catch {}

    return @($urls | Select-Object -Unique)
}

function Find-DisallowedMods {
    param([array]$JarFiles)

    $found = [System.Collections.Generic.List[PSObject]]::new()
    foreach ($file in $JarFiles) {
        $fileName = $file.Name.ToLowerInvariant()
        $modInfo = Get-Mod-Info-From-Jar -JarPath $file.FullName
        $baseName = Get-ModBaseName -FileName $file.Name
        if ($script:cleanModWhitelist.Contains($baseName)) { continue }
        if ($modInfo.ModId -and $script:cleanModWhitelist.Contains($modInfo.ModId)) { continue }

        foreach ($slug in $script:disallowedMods.Keys) {
            $definition = $script:disallowedMods[$slug]
            $isDisallowed = $false
            $source = ""
            if ($modInfo.ModId -and $modInfo.ModId.ToLowerInvariant() -match [regex]::Escape($slug.ToLowerInvariant())) {
                $isDisallowed = $true
                $source = "mod ID"
            } elseif ($modInfo.Name -and $modInfo.Name.ToLowerInvariant() -match [regex]::Escape($slug.ToLowerInvariant().Replace("-", " "))) {
                $isDisallowed = $true
                $source = "mod name"
            } else {
                foreach ($name in $definition.Names) {
                    $nameLower = $name.ToLowerInvariant()
                    $nameSquashed = $nameLower -replace "\s", ""
                    $slugLower = $slug.ToLowerInvariant()
                    if (
                        $fileName -eq "$nameLower.jar" -or
                        $fileName -eq "$nameSquashed.jar" -or
                        $fileName -eq "$slugLower.jar" -or
                        $fileName -match [regex]::Escape($nameSquashed)
                    ) {
                        $isDisallowed = $true
                        $source = "filename"
                        break
                    }
                }
            }

            if ($isDisallowed) {
                $found.Add([PSCustomObject]@{
                    FileName     = $file.Name
                    ModName      = $definition.Names[0]
                    Slug         = $slug
                    MatchedBy    = $source
                    DetectedId   = if ($modInfo.ModId) { $modInfo.ModId } else { "-" }
                    DetectedName = if ($modInfo.Name) { $modInfo.Name } else { "-" }
                })
                break
            }
        }
    }

    return $found
}

function Test-JvmArguments {
    $findings = [System.Collections.Generic.List[PSObject]]::new()
    $foundFlags = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $mcProcesses = Get-MinecraftJavaProcessInfo
    if ($mcProcesses.Count -eq 0) { return $findings }

    $suspiciousArgsList = @(
        @("-Dfabric\.addMods=",                  "FABRIC_ADD_MODS",              "HIGH",   "Injects extra Fabric mod JARs at runtime"),
        @("-Dfabric\.loadMods=",                 "FABRIC_LOAD_MODS",             "HIGH",   "Overrides Fabric mod loading mechanism"),
        @("-Dfabric\.classPathGroups=",          "FABRIC_CLASSPATH_GROUPS",      "HIGH",   "Manipulates Fabric classpath groups"),
        @("-Dfabric\.gameJarPath=",              "FABRIC_GAME_JAR_PATH",         "MEDIUM", "Redirects Minecraft game JAR path"),
        @("-Dfabric\.skipMcProvider=",           "FABRIC_SKIP_MC_PROVIDER",      "HIGH",   "Skips Minecraft provider checks"),
        @("-Dfabric\.remapClasspathFile=",       "FABRIC_REMAP_CLASSPATH",       "HIGH",   "Redirects remap classpath file"),
        @("-Dfabric\.skipIntermediary=",         "FABRIC_SKIP_INTERMEDIARY",     "HIGH",   "Skips intermediary mappings"),
        @("-Dfabric\.mixin\.configs=",           "FABRIC_MIXIN_CONFIGS",         "HIGH",   "Injects custom Mixin configs"),
        @("-Dfabric\.mixin\.hotSwap=",           "FABRIC_MIXIN_HOTSWAP",         "HIGH",   "Enables Mixin hot-swapping"),
        @("-Dfabric\.forceVersion=",             "FABRIC_FORCE_VERSION",         "HIGH",   "Forces a specific game version"),
        @("-Dfabric\.customModList=",            "FABRIC_CUSTOM_MOD_LIST",       "HIGH",   "Injects custom mod list"),
        @("-Dfabric\.skipDependencyResolution=", "FABRIC_SKIP_DEP_RESOLUTION",   "HIGH",   "Skips dependency resolution"),
        @("-Dfabric\.loader\.entrypoints=",      "FABRIC_LOADER_ENTRYPOINTS",    "HIGH",   "Injects custom entrypoints"),
        @("-Dfabric\.language\.providers=",      "FABRIC_LANGUAGE_PROVIDERS",    "HIGH",   "Injects custom language providers"),
        @("-Dfabric\.mods\.toml\.path=",         "FABRIC_MODS_TOML_PATH",        "HIGH",   "Redirects Fabric mods.toml path"),
        @("-Dfabric\.resolve\.modFiles=",        "FABRIC_RESOLVE_MODFILES",      "MEDIUM", "Forces mod file resolution"),
        @("-Dfabric\.loader\.config=",           "FABRIC_LOADER_CONFIG",         "MEDIUM", "Redirects Fabric loader config"),
        @("-Dfabric\.configDir=",                "FABRIC_CONFIG_DIR",            "MEDIUM", "Changes Fabric config directory"),
        @("-Dfabric\.gameVersion=",              "FABRIC_GAME_VERSION",          "MEDIUM", "Overrides Fabric game version"),
        @("-Dfabric\.allowUnsupportedVersion=",  "FABRIC_UNSUPPORTED_VERSION",   "MEDIUM", "Allows unsupported versions"),
        @("-Dfabric\.dli\.config=",              "FABRIC_DLI_CONFIG",            "MEDIUM", "Changes data loader injector config"),
        @("-Dfabric\.development=",              "FABRIC_DEV_MODE",              "LOW",    "Enables Fabric development mode"),
        @("-Dforge\.addMods=",                   "FORGE_ADD_MODS",               "HIGH",   "Injects extra Forge mod JARs at runtime"),
        @("-Dforge\.mods=",                      "FORGE_MODS",                   "HIGH",   "Overrides Forge mod list"),
        @("-Dfml\.coreMods\.load=",              "FORGE_COREMODS",               "HIGH",   "Loads Forge core mods via JVM flag"),
        @("-Dforge\.coreMods\.dir=",             "FORGE_COREMODS_DIR",           "HIGH",   "Redirects core mods directory"),
        @("-Dforge\.modDir=",                    "FORGE_MOD_DIR",                "HIGH",   "Redirects mod directory"),
        @("-Dforge\.modsDirectories=",           "FORGE_MODS_DIRECTORIES",       "HIGH",   "Adds extra mod directories"),
        @("-Dfml\.customModList=",               "FORGE_CUSTOM_MOD_LIST",        "HIGH",   "Injects custom Forge mod list"),
        @("-Dforge\.disableModScan=",            "FORGE_DISABLE_MODSCAN",        "HIGH",   "Disables Forge mod scanning"),
        @("-Dforge\.modList=",                   "FORGE_MOD_LIST",               "HIGH",   "Overrides Forge mod list"),
        @("-Dforge\.mixin\.hotSwap=",            "FORGE_MIXIN_HOTSWAP",          "HIGH",   "Enables Forge Mixin hot-swapping"),
        @("-Dforge\.forceVersion=",              "FORGE_FORCE_VERSION",          "HIGH",   "Forces Forge version"),
        @("-Dforge\.disableUpdateCheck=",        "FORGE_DISABLE_UPDATE",         "MEDIUM", "Disables Forge update checks"),
        @("-Djava\.security\.manager=",          "SECURITY_MANAGER_DISABLED",    "HIGH",   "Disables Java Security Manager"),
        @("-Djava\.security\.policy=",           "SECURITY_POLICY_OVERRIDE",     "HIGH",   "Overrides security policy"),
        @("-Xbootclasspath",                     "BOOTCLASSPATH_MODIFY",         "HIGH",   "Modifies boot classpath"),
        @("-Djava\.system\.class\.loader=",      "CUSTOM_CLASSLOADER",           "HIGH",   "Replaces system classloader"),
        @("-Djava\.class\.path=",                "CLASSPATH_OVERRIDE",           "HIGH",   "Overrides Java classpath"),
        @("-Xrunjdwp:",                          "REMOTE_DEBUG",                 "HIGH",   "Remote debugging is enabled"),
        @("agentlib:jdwp",                       "JDWP_AGENT",                   "HIGH",   "JDWP agent attached"),
        @("-agentlib:",                          "NATIVE_AGENT",                 "HIGH",   "Loads native JVMTI agent"),
        @("-agentpath:",                         "NATIVE_AGENT_PATH",            "HIGH",   "Loads native agent by path"),
        @("-D(client|launcher)\.brand=(Wurst|Aristois|Impact|Future|Lambda|Rusher|Konas|Phobos|Salhack|Meteor|Async|Wolfram|Huzuni|Rise|Flux|Gamesense|Intent|Remix|Vape|Ghost|Inertia|Sigma|Novoline|Ares|Prestige|Entropy)",
            "CHEAT_CLIENT_BRAND", "HIGH", "Cheat client brand spoofed in JVM arguments")
    )

    $agentWhitelist = @("jmxremote","yjp","jrebel","newrelic","jacoco","hotswapagent","theseus","lunar","appney")

    foreach ($mcProcess in $mcProcesses) {
        $javaPid = $mcProcess.PID
        $commandLine = $mcProcess.CommandLine
        if (-not $commandLine) { continue }

        $agentMatches = [regex]::Matches($commandLine, '-javaagent:([^\s"]+)')
        foreach ($match in $agentMatches) {
            $agentPath = $match.Groups[1].Value.Trim('"').Trim("'")
            $agentName = [System.IO.Path]::GetFileName($agentPath)
            $safe = $false
            foreach ($allowed in $agentWhitelist) {
                if ($agentName -match $allowed) {
                    $safe = $true
                    break
                }
            }
            if (-not $safe) {
                $key = "AGENT|$agentName|$javaPid"
                if ($foundFlags.Add($key)) {
                    $findings.Add([PSCustomObject]@{
                        Type     = "JAVA_AGENT"
                        Detail   = "Untrusted javaagent loaded: $agentName"
                        Severity = "HIGH"
                        PID      = $javaPid
                    })
                }
            }
        }

        foreach ($argSpec in $suspiciousArgsList) {
            if ($commandLine -match $argSpec[0]) {
                $key = "$($argSpec[1])|$javaPid"
                if ($foundFlags.Add($key)) {
                    $findings.Add([PSCustomObject]@{
                        Type     = $argSpec[1]
                        Detail   = $argSpec[3]
                        Severity = $argSpec[2]
                        PID      = $javaPid
                    })
                }
            }
        }

        if ($commandLine -match "(%3B|%26%26|%7C%7C|%7C|%60|%24|%3C|%3E)") {
            $key = "URL_ENCODE|$javaPid"
            if ($foundFlags.Add($key)) {
                $findings.Add([PSCustomObject]@{
                    Type     = "ENCODED_INJECTION"
                    Detail   = "URL-encoded shell metacharacters in JVM args"
                    Severity = "HIGH"
                    PID      = $javaPid
                })
            }
        }

        try {
            $listeners = Get-NetTCPConnection -OwningProcess $javaPid -ErrorAction Stop |
                Where-Object { $_.LocalAddress -eq "127.0.0.1" -and $_.State -eq "Listen" }
            if ($listeners) {
                $ports = $listeners.LocalPort -join ", "
                $key = "LOCAL_LISTEN|$javaPid"
                if ($foundFlags.Add($key)) {
                    $findings.Add([PSCustomObject]@{
                        Type     = "LOCAL_LISTEN"
                        Detail   = "Java opened localhost listener(s): $ports"
                        Severity = "HIGH"
                        PID      = $javaPid
                    })
                }
            }
        } catch {}
    }

    return $findings
}

function Add-InjectorFinding {
    param(
        [System.Collections.Generic.List[object]]$Findings,
        [System.Collections.Generic.HashSet[string]]$Seen,
        [string]$Type,
        [string]$Detail,
        [string]$Severity,
        [Alias("PID")]
        [int]$ProcessId = 0
    )

    $key = "$Type|$ProcessId|$Detail"
    if ($Seen.Add($key)) {
        $Findings.Add([PSCustomObject]@{
            Type     = $Type
            Detail   = $Detail
            Severity = $Severity
            PID      = $ProcessId
        })
    }
}

function Test-InjectorThreats {
    $findings = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $mcProcesses = Get-MinecraftJavaProcessInfo

    $trustedModules = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    Add-HashSetValues -Set $trustedModules -Values @(
        "discordhook.dll","discordhook64.dll","gameoverlayrenderer.dll","gameoverlayrenderer64.dll",
        "nvspcap.dll","nvspcap64.dll","rtsshook.dll","rtsshook64.dll","owclient.dll","overwolfhook.dll"
    )

    $suspiciousHelperTokens = @(
        "cheatengine","cheat engine","gh injector","extreme injector","xenos","loadlibrayy",
        "manualmap","blackbone","x64dbg","x32dbg","ollydbg","megadumper","scylla",
        "processhacker","process hacker","dnspy","javaagent injector","jvmti injector"
    )

    $suspiciousModuleTokens = @(
        "detour","minhook","easyhook","blackbone","manualmap",
        "ghinjector","xenos","cheatengine","jnihook","jvmti","loadlibrayy",
        "d3d11hook","dxgihook","kiero","imgui"
    )

    $highConfidenceModuleTokens = @(
        "minhook","easyhook","blackbone","manualmap","ghinjector","xenos",
        "cheatengine","jvmti","loadlibrayy","d3d11hook","dxgihook"
    )

    $riskyLocationRegex = "\\AppData\\Local\\Temp\\|\\Downloads\\|\\Desktop\\|\\Temp\\"
    $safeAgentTokens = @("jmxremote","yjp","jrebel","newrelic","jacoco","hotswapagent","theseus","lunar","appney")

    try {
        $allProcesses = Get-WmiObject Win32_Process -ErrorAction Stop
        foreach ($process in $allProcesses) {
            $joined = (([string]$process.Name) + " " + ([string]$process.CommandLine)).ToLowerInvariant()
            foreach ($token in $suspiciousHelperTokens) {
                if ($joined.Contains($token)) {
                    Add-InjectorFinding -Findings $findings -Seen $seen -Type "INJECTOR_HELPER" `
                        -Detail "Suspicious helper process '$($process.Name)' matches '$token'" `
                        -Severity "MEDIUM" -PID ([int]$process.ProcessId)
                    break
                }
            }
        }
    } catch {}

    foreach ($mcProcess in $mcProcesses) {
        $minecraftPid = $mcProcess.PID
        $commandLine = [string]$mcProcess.CommandLine
        $executablePath = [string]$mcProcess.ExecutablePath

        if ($executablePath -and $executablePath -match $riskyLocationRegex) {
            Add-InjectorFinding -Findings $findings -Seen $seen -Type "RISKY_JAVA_PATH" `
                -Detail "Minecraft Java executable is running from a risky location: $executablePath" `
                -Severity "HIGH" -PID $minecraftPid
        }

        foreach ($match in [regex]::Matches($commandLine, '-javaagent:(".*?"|\S+)')) {
            $agentPath = $match.Groups[1].Value.Trim('"')
            $isSafe = $false
            foreach ($safeToken in $safeAgentTokens) {
                if ($agentPath.ToLowerInvariant().Contains($safeToken)) {
                    $isSafe = $true
                    break
                }
            }

            if (-not $isSafe) {
                $severity = if ($agentPath -match $riskyLocationRegex) { "HIGH" } else { "MEDIUM" }
                Add-InjectorFinding -Findings $findings -Seen $seen -Type "JAVA_AGENT_PATH" `
                    -Detail "Minecraft launched with javaagent: $agentPath" `
                    -Severity $severity -PID $minecraftPid
            }
        }

        foreach ($match in [regex]::Matches($commandLine, '-agentpath:(".*?"|\S+)')) {
            $agentPath = $match.Groups[1].Value.Trim('"')
            Add-InjectorFinding -Findings $findings -Seen $seen -Type "NATIVE_AGENT_PATH" `
                -Detail "Minecraft launched with native agent path: $agentPath" `
                -Severity "HIGH" -PID $minecraftPid
        }

        try {
            $processHandle = Get-Process -Id $minecraftPid -ErrorAction Stop
            foreach ($module in $processHandle.Modules) {
                $moduleName = [string]$module.ModuleName
                $modulePath = [string]$module.FileName
                if ($trustedModules.Contains($moduleName)) { continue }

                $joined = ($moduleName + " " + $modulePath).ToLowerInvariant()
                $matchedToken = $null
                foreach ($token in $suspiciousModuleTokens) {
                    if ($joined.Contains($token)) {
                        $matchedToken = $token
                        break
                    }
                }
                if ($null -eq $matchedToken) { continue }

                if ($modulePath -match "\\Windows\\System32\\" -and $matchedToken -in @("hook", "inject")) {
                    continue
                }

                $severity = "MEDIUM"
                foreach ($token in $highConfidenceModuleTokens) {
                    if ($joined.Contains($token)) {
                        $severity = "HIGH"
                        break
                    }
                }
                if ($modulePath -match $riskyLocationRegex) {
                    $severity = "HIGH"
                }

                Add-InjectorFinding -Findings $findings -Seen $seen -Type "INJECTED_MODULE" `
                    -Detail "Suspicious module loaded into Minecraft: $moduleName ($modulePath)" `
                    -Severity $severity -PID $minecraftPid
            }
        } catch {}
    }

    return $findings
}

function Show-IntegrityReport {
    param([pscustomobject]$Report)

    Clear-Host
    Show-MineTiersBanner -Subtitle "Scan Results"

    $flaggedColor = if ($Report.Flagged.Count -gt 0) { [System.ConsoleColor]::Red } else { [System.ConsoleColor]::Cyan }
    $injectorColor = if ($Report.InjectorFindings.Count -gt 0) { [System.ConsoleColor]::Red } else { [System.ConsoleColor]::Cyan }
    $jvmColor = if ($Report.JvmResults.Count -gt 0) { [System.ConsoleColor]::Red } else { [System.ConsoleColor]::Cyan }
    $disallowedColor = if ($Report.DisallowedFound.Count -gt 0) { [System.ConsoleColor]::Red } else { [System.ConsoleColor]::Cyan }

    Write-ReportBorder Top
    Write-ReportText "  MINE TIERS SCAN REPORT  -  $($Report.ScanTimestamp)" Magenta
    Write-ReportBorder Sep
    Write-ReportRow "  Modules        : " ($Report.ActiveModules -join " | ") Magenta White
    Write-ReportRow "  Path           : " $Report.ModsPath DarkGray Gray
    Write-ReportRow "  Files          : " "$($Report.Jars.Count) scanned" DarkGray White
    Write-ReportRow "  Clean          : " "$($Report.Clean.Count)" DarkGray Cyan
    Write-ReportRow "  JVM Issues     : " "$($Report.JvmResults.Count)" DarkGray $jvmColor
    Write-ReportRow "  Injector Alerts: " "$($Report.InjectorFindings.Count)" DarkGray $injectorColor
    Write-ReportRow "  Flagged Mods   : " "$($Report.Flagged.Count)" DarkGray $flaggedColor
    Write-ReportRow "  Disallowed Mods: " "$($Report.DisallowedFound.Count)" DarkGray $disallowedColor
    if ($Report.MinecraftStatus.Running) {
        Write-ReportRow "  Minecraft      : " "RUNNING | PID $($Report.MinecraftStatus.PID) | $($Report.MinecraftStatus.Uptime) | $($Report.MinecraftStatus.RAM) RAM" DarkGray Cyan
    } else {
        Write-ReportRow "  Minecraft      : " "not running" DarkGray DarkGray
    }
    Write-ReportBorder Bot

    if ($Report.JvmResults.Count -gt 0) {
        Write-Host ""
        Write-ReportBorder Top Red
        Write-ReportText "  JVM ARGUMENT ISSUES ($($Report.JvmResults.Count) finding(s))" Red Red
        Write-ReportBorder Sep Red
        foreach ($finding in ($Report.JvmResults | Sort-Object Severity, Type)) {
            $color = switch ($finding.Severity) {
                "HIGH" { [System.ConsoleColor]::Red }
                "MEDIUM" { [System.ConsoleColor]::Yellow }
                default { [System.ConsoleColor]::DarkGray }
            }
            Write-ReportRow "  [$($finding.Severity.PadRight(6))] " "$($finding.Type) | PID $($finding.PID) | $($finding.Detail)" $color DarkGray Red
        }
        Write-ReportBorder Bot Red
    }

    if ($Report.InjectorFindings.Count -gt 0) {
        Write-Host ""
        Write-ReportBorder Top Red
        Write-ReportText "  INJECTOR AND RUNTIME FINDINGS ($($Report.InjectorFindings.Count) finding(s))" Red Red
        Write-ReportBorder Sep Red
        foreach ($finding in ($Report.InjectorFindings | Sort-Object Severity, Type)) {
            $color = switch ($finding.Severity) {
                "HIGH" { [System.ConsoleColor]::Red }
                "MEDIUM" { [System.ConsoleColor]::Yellow }
                default { [System.ConsoleColor]::DarkGray }
            }
            Write-ReportRow "  [$($finding.Severity.PadRight(6))] " "$($finding.Type) | PID $($finding.PID) | $($finding.Detail)" $color DarkGray Red
        }
        Write-ReportBorder Bot Red
    }

    if ($Report.CriticalThreats.Count -gt 0) {
        Write-Host ""
        Write-ReportBorder Top Red
        Write-ReportText "  CRITICAL THREATS - CONFIRMED CHEAT INDICATORS ($($Report.CriticalThreats.Count) file(s))" Red Red
        foreach ($mod in $Report.CriticalThreats) {
            Write-ReportBorder Sep Red
            Write-ReportRow "  [CRITICAL] " $mod.Name White Red Red
            Write-ReportRow "             " "Size: $($mod.Size) KB | Hits: $($mod.HitCount)" DarkGray DarkGray Red
            if ($mod.FilenameToken) {
                Write-ReportRow "             " "Filename token: $($mod.FilenameToken)" DarkGray Red Red
            }
            $allHits = @($mod.Strings) + @($mod.Patterns) + @($mod.DeepHits) + @($mod.Fullwidth)
            foreach ($hit in ($allHits | Select-Object -First 6)) {
                Write-ReportRow "             " "- $hit" DarkGray Red Red
            }
            if ($mod.MixinHits -and $mod.MixinHits.Count -gt 0) {
                foreach ($hit in ($mod.MixinHits | Select-Object -First 3)) {
                    Write-ReportRow "             " "[MIX] $hit" DarkGray Magenta Red
                }
            }
            if ($mod.BytecodeHits -and $mod.BytecodeHits.Count -gt 0) {
                foreach ($hit in ($mod.BytecodeHits | Select-Object -First 3)) {
                    Write-ReportRow "             " "[BYT] $hit" DarkGray Magenta Red
                }
            }
            if ($mod.NetworkHits -and $mod.NetworkHits.Count -gt 0) {
                foreach ($hit in ($mod.NetworkHits | Select-Object -First 3)) {
                    Write-ReportRow "             " "[NET] $hit" DarkGray Magenta Red
                }
            }
            if ($mod.ObfResult) {
                foreach ($hit in ($mod.ObfResult | Select-Object -First 3)) {
                    Write-ReportRow "             " "[OBF] $hit" DarkGray Yellow Red
                }
            }
        }
        Write-ReportBorder Bot Red
    }

    if ($Report.SuspiciousFiles.Count -gt 0) {
        Write-Host ""
        Write-ReportBorder Top Yellow
        Write-ReportText "  SUSPICIOUS FILES ($($Report.SuspiciousFiles.Count) file(s))" Yellow Yellow
        foreach ($mod in $Report.SuspiciousFiles) {
            Write-ReportBorder Sep Yellow
            Write-ReportRow "  [WARN] " $mod.Name White Yellow Yellow
            Write-ReportRow "         " "Size: $($mod.Size) KB | Hits: $($mod.HitCount)" DarkGray DarkGray Yellow
            if ($mod.FilenameToken) {
                Write-ReportRow "         " "Filename token: $($mod.FilenameToken)" DarkGray Yellow Yellow
            }
            $allHits = @($mod.Strings) + @($mod.Patterns) + @($mod.DeepHits) + @($mod.Fullwidth)
            foreach ($hit in ($allHits | Select-Object -First 4)) {
                Write-ReportRow "         " "- $hit" DarkGray DarkGray Yellow
            }
            if ($mod.MixinHits -and $mod.MixinHits.Count -gt 0) {
                foreach ($hit in ($mod.MixinHits | Select-Object -First 2)) {
                    Write-ReportRow "         " "[MIX] $hit" DarkGray DarkYellow Yellow
                }
            }
            if ($mod.BytecodeHits -and $mod.BytecodeHits.Count -gt 0) {
                foreach ($hit in ($mod.BytecodeHits | Select-Object -First 2)) {
                    Write-ReportRow "         " "[BYT] $hit" DarkGray DarkYellow Yellow
                }
            }
            if ($mod.NetworkHits -and $mod.NetworkHits.Count -gt 0) {
                foreach ($hit in ($mod.NetworkHits | Select-Object -First 2)) {
                    Write-ReportRow "         " "[NET] $hit" DarkGray DarkYellow Yellow
                }
            }
            if ($mod.ObfResult) {
                foreach ($hit in ($mod.ObfResult | Select-Object -First 2)) {
                    Write-ReportRow "         " "[OBF] $hit" DarkGray DarkYellow Yellow
                }
            }
            if ($mod.Entropy.Count -gt 0) {
                Write-ReportRow "         " "[ENT] High entropy classes detected" DarkGray DarkYellow Yellow
            }
        }
        Write-ReportBorder Bot Yellow
    }

    if ($Report.DisallowedFound.Count -gt 0) {
        Write-Host ""
        Write-ReportBorder Top Yellow
        Write-ReportText "  DISALLOWED MODS DETECTED ($($Report.DisallowedFound.Count))" Yellow Yellow
        Write-ReportBorder Sep Yellow
        foreach ($mod in $Report.DisallowedFound) {
            Write-ReportRow "  [BLOCK] " $mod.FileName White Yellow Yellow
            Write-ReportRow "          " "Mod: $($mod.ModName) | Matched by: $($mod.MatchedBy)" DarkGray DarkYellow Yellow
            if ($mod -ne $Report.DisallowedFound[-1]) {
                Write-ReportBorder Sep DarkYellow
            }
        }
        Write-ReportBorder Bot Yellow
    }

    $totalIssues = $Report.JvmResults.Count + $Report.InjectorFindings.Count + $Report.Flagged.Count + $Report.DisallowedFound.Count
    if ($totalIssues -eq 0) {
        Write-Host ""
        Write-ReportBorder Top Cyan
        Write-ReportText "  ALL CLEAR - No issues detected across all scan phases" Cyan Cyan
        Write-ReportBorder Bot Cyan
    }

    Write-Host ""
    Write-Host "  Analysis complete." -ForegroundColor Green
}

function Invoke-IntegrityScan {
    param([string]$RequestedModsPath)

    Clear-Host
    Show-MineTiersBanner -Subtitle "Mod, JVM, and Injector Analyzer"

    $resolvedModsPath = Resolve-ModsPath -InputPath $RequestedModsPath
    if (-not (Test-Path $resolvedModsPath -PathType Container)) {
        Write-Host ""
        Write-Host "  Invalid mods path: $resolvedModsPath" -ForegroundColor Red
        return $null
    }

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
    } catch {}

    try {
        $jars = Get-ChildItem -Path $resolvedModsPath -Filter *.jar -ErrorAction Stop
    } catch {
        Write-Host "  Cannot read directory." -ForegroundColor Red
        return $null
    }

    if ($jars.Count -eq 0) {
        Write-Host "  No JAR files found." -ForegroundColor Yellow
        return $null
    }

    $scanTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $mcStatus = Get-MinecraftStatus
    $activeModules = @("JVM Scan", "Injector Detection", "Mod Analysis", "Macro Monitor Ready")

    Write-Host ""
    Write-Host "  $scanTimestamp" -ForegroundColor DarkGray
    Write-Host "  $resolvedModsPath" -ForegroundColor DarkGray
    Write-Host "  $($jars.Count) file(s) found" -ForegroundColor DarkGray
    Write-Host ""
    if ($mcStatus.Running) {
        Write-Host "  Minecraft  " -ForegroundColor DarkGray -NoNewline
        Write-Host "[RUNNING] " -ForegroundColor Magenta -NoNewline
        Write-Host "PID $($mcStatus.PID) | $($mcStatus.Uptime) | $($mcStatus.RAM) RAM" -ForegroundColor White
    } else {
        Write-Host "  Minecraft  " -ForegroundColor DarkGray -NoNewline
        Write-Host "[OFFLINE] " -ForegroundColor DarkGray -NoNewline
        Write-Host "Runtime checks will be limited." -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "  Phase 1 - JVM argument injection detection" -ForegroundColor Magenta
    Write-Host "    scanning..." -ForegroundColor DarkGray -NoNewline
    $jvmResults = @(Test-JvmArguments)
    if ($jvmResults.Count -gt 0) {
        $jvmHigh = @($jvmResults | Where-Object { $_.Severity -eq "HIGH" }).Count
        $jvmMed = @($jvmResults | Where-Object { $_.Severity -eq "MEDIUM" }).Count
        $parts = @()
        if ($jvmHigh -gt 0) { $parts += "$jvmHigh HIGH" }
        if ($jvmMed -gt 0) { $parts += "$jvmMed MEDIUM" }
        Write-Host " $($jvmResults.Count) issue(s) ($($parts -join ', '))" -ForegroundColor Red
    } else {
        Write-Host " clean" -ForegroundColor Cyan
    }

    Write-Host ""
    Write-Host "  Phase 2 - Injector and runtime manipulation detection" -ForegroundColor Magenta
    Write-Host "    scanning..." -ForegroundColor DarkGray -NoNewline
    $injectorFindings = @(Test-InjectorThreats)
    if ($injectorFindings.Count -gt 0) {
        $highCount = @($injectorFindings | Where-Object { $_.Severity -eq "HIGH" }).Count
        $mediumCount = @($injectorFindings | Where-Object { $_.Severity -eq "MEDIUM" }).Count
        $parts = @()
        if ($highCount -gt 0) { $parts += "$highCount HIGH" }
        if ($mediumCount -gt 0) { $parts += "$mediumCount MEDIUM" }
        Write-Host " $($injectorFindings.Count) finding(s) ($($parts -join ', '))" -ForegroundColor Red
    } else {
        Write-Host " clean" -ForegroundColor Cyan
    }

    $total = $jars.Count
    $index = 0
    $flagged = [System.Collections.Generic.List[PSObject]]::new()
    $clean = [System.Collections.Generic.List[string]]::new()

    Write-Host ""
    Write-Host "  Phase 3 - String analysis, deep scan, and filename tokens" -ForegroundColor Magenta
    foreach ($jar in $jars) {
        $index++
        $percent = [Math]::Floor(($index / $total) * 100)
        $paddedName = $jar.Name.PadRight(45).Substring(0, [Math]::Min(45, $jar.Name.Length))
        [Console]::Write("    $percent% $paddedName`r")

        $baseName = Get-ModBaseName -FileName $jar.Name
        $isWhitelisted = $script:cleanModWhitelist.Contains($baseName)
        $modInfo = Get-Mod-Info-From-Jar -JarPath $jar.FullName
        if ($modInfo.ModId -and $script:cleanModWhitelist.Contains($modInfo.ModId)) {
            $isWhitelisted = $true
        }

        $signature = Get-ModSignature -Path $jar.FullName -ScanStrings $true -ScanDeep $true
        $fileNameMatch = if (-not $isWhitelisted) { $script:tokenRegex.Match($jar.Name.ToLowerInvariant()) } else { [System.Text.RegularExpressions.Match]::Empty }
        if ($signature.Count -gt 0 -or $fileNameMatch.Success) {
            $patterns = @($signature | Where-Object { $_ -match "^P\|" } | ForEach-Object { $_.Substring(2) })
            $strings = @($signature | Where-Object { $_ -match "^S\|" } | ForEach-Object { $_.Substring(2) })
            $fullwidth = @($signature | Where-Object { $_ -match "^F\|" } | ForEach-Object { $_.Substring(2) })
            $deepHits = @($signature | Where-Object { $_ -match "^D\|" } | ForEach-Object { $_.Substring(2) })
            $entropy = @($signature | Where-Object { $_ -match "^E\|" } | ForEach-Object { $_.Substring(2) })
            $sources = Get-ModSources -Path $jar.FullName
            $flagged.Add([PSCustomObject]@{
                Name          = $jar.Name
                Path          = $jar.FullName
                Size          = [Math]::Round($jar.Length / 1KB, 1)
                Patterns      = $patterns
                Strings       = $strings
                Fullwidth     = $fullwidth
                DeepHits      = $deepHits
                Entropy       = $entropy
                HitCount      = $signature.Count
                Sources       = $sources
                ObfResult     = $null
                MixinHits     = $null
                BytecodeHits  = $null
                NetworkHits   = $null
                FilenameToken = if ($fileNameMatch.Success) { $fileNameMatch.Value } else { $null }
                IsWhitelisted = $isWhitelisted
            })
        } else {
            $clean.Add($jar.Name)
        }
    }
    Write-Host "    100% done" -ForegroundColor DarkMagenta
    Write-Host "    $($flagged.Count) flagged | $($clean.Count) clean" -ForegroundColor DarkMagenta

    Write-Host ""
    Write-Host "  Phase 4 - Advanced obfuscation detection" -ForegroundColor Magenta
    $obfIndex = 0
    foreach ($jar in $jars) {
        $obfIndex++
        $percent = [Math]::Floor(($obfIndex / $total) * 100)
        $paddedName = $jar.Name.PadRight(45).Substring(0, [Math]::Min(45, $jar.Name.Length))
        [Console]::Write("    $percent% $paddedName`r")

        $obfFlags = Invoke-ObfuscationFlags -FilePath $jar.FullName
        $existing = $flagged | Where-Object { $_.Name -eq $jar.Name } | Select-Object -First 1
        if ($existing) {
            $existing.ObfResult = $obfFlags
        } elseif ($obfFlags.Count -gt 0) {
            $baseName = Get-ModBaseName -FileName $jar.Name
            $flagged.Add([PSCustomObject]@{
                Name          = $jar.Name
                Path          = $jar.FullName
                Size          = [Math]::Round($jar.Length / 1KB, 1)
                Patterns      = @()
                Strings       = @()
                Fullwidth     = @()
                DeepHits      = @()
                Entropy       = @()
                HitCount      = 0
                Sources       = @()
                ObfResult     = $obfFlags
                MixinHits     = $null
                BytecodeHits  = $null
                NetworkHits   = $null
                FilenameToken = $null
                IsWhitelisted = $script:cleanModWhitelist.Contains($baseName)
            })
            $clean.Remove($jar.Name) | Out-Null
        }
    }
    Write-Host "    100% done" -ForegroundColor DarkMagenta
    $obfHeavy = ($flagged | Where-Object { $_.ObfResult -and $_.ObfResult.Count -gt 0 }).Count
    Write-Host "    $obfHeavy jar(s) with obfuscation flags" -ForegroundColor DarkMagenta

    Write-Host ""
    Write-Host "  Phase 5 - Mixin injection, bytecode hooks, and network exfil" -ForegroundColor Magenta
    $phaseFiveIndex = 0
    foreach ($jar in $jars) {
        $phaseFiveIndex++
        $percent = [Math]::Floor(($phaseFiveIndex / $total) * 100)
        $paddedName = $jar.Name.PadRight(45).Substring(0, [Math]::Min(45, $jar.Name.Length))
        [Console]::Write("    $percent% $paddedName`r")

        $baseName = Get-ModBaseName -FileName $jar.Name
        $isWhitelisted = $script:cleanModWhitelist.Contains($baseName)
        $modInfo = Get-Mod-Info-From-Jar -JarPath $jar.FullName
        if ($modInfo.ModId -and $script:cleanModWhitelist.Contains($modInfo.ModId)) {
            $isWhitelisted = $true
        }

        $mixinHits = Invoke-MixinInjectionScan -FilePath $jar.FullName -IsWhitelisted $isWhitelisted
        $bytecodeHits = Invoke-BytecodeHookScan -FilePath $jar.FullName -IsWhitelisted $isWhitelisted
        $networkHits = Invoke-NetworkExfilScan -FilePath $jar.FullName -IsWhitelisted $isWhitelisted
        $anyNew = ($mixinHits.Count + $bytecodeHits.Count + $networkHits.Count) -gt 0

        $existing = $flagged | Where-Object { $_.Name -eq $jar.Name } | Select-Object -First 1
        if ($existing) {
            $existing.MixinHits = $mixinHits
            $existing.BytecodeHits = $bytecodeHits
            $existing.NetworkHits = $networkHits
        } elseif ($anyNew) {
            $flagged.Add([PSCustomObject]@{
                Name          = $jar.Name
                Path          = $jar.FullName
                Size          = [Math]::Round($jar.Length / 1KB, 1)
                Patterns      = @()
                Strings       = @()
                Fullwidth     = @()
                DeepHits      = @()
                Entropy       = @()
                HitCount      = 0
                Sources       = @()
                ObfResult     = $null
                MixinHits     = $mixinHits
                BytecodeHits  = $bytecodeHits
                NetworkHits   = $networkHits
                FilenameToken = $null
                IsWhitelisted = $isWhitelisted
            })
            $clean.Remove($jar.Name) | Out-Null
        }
    }
    Write-Host "    100% done" -ForegroundColor DarkMagenta
    $phaseFiveCount = ($flagged | Where-Object {
        ($_.MixinHits -and $_.MixinHits.Count -gt 0) -or
        ($_.BytecodeHits -and $_.BytecodeHits.Count -gt 0) -or
        ($_.NetworkHits -and $_.NetworkHits.Count -gt 0)
    }).Count
    Write-Host "    $phaseFiveCount jar(s) with mixin, bytecode, or network flags" -ForegroundColor DarkMagenta

    Write-Host ""
    Write-Host "  Phase 6 - Disallowed mod detection" -ForegroundColor Magenta
    Write-Host "    scanning..." -ForegroundColor DarkGray -NoNewline
    $disallowedFound = Find-DisallowedMods -JarFiles $jars
    if ($disallowedFound.Count -gt 0) {
        Write-Host " $($disallowedFound.Count) disallowed mod(s)" -ForegroundColor Red
    } else {
        Write-Host " clean" -ForegroundColor Cyan
    }

    $criticalThreats = [System.Collections.Generic.List[PSObject]]::new()
    $suspiciousFiles = [System.Collections.Generic.List[PSObject]]::new()
    foreach ($mod in $flagged) {
        $isBlatant = $false
        if ($mod.HitCount -ge 20) { $isBlatant = $true }

        foreach ($stringHit in $mod.Strings) {
            if ($stringHit -match "SelfDestruct|AutoCrystal|Dqrkis Client|POT_CHEATS|Donut|cancelPacket|dropPacket|spoofPacket|setTimerSpeed|timerSpeed|grimBypass|ncpBypass|aacBypass|bypassAC|selfdestruct|reverseShell|sendWebhook|TokenGrabber|SessionStealer|discord\.com/api/webhooks|pastebin\.com/raw|grabify|FINDING_SPAWNER|OPENING_SPAWNER|WAITING_SPAWNER_GUI|LOOTING_BONES|CLOSING_SPAWNER|ORDER_COMMAND|WAIT_ORDER_GUI|SELECT_ORDER_ITEM|WAIT_DELIVERY_GUI|DELIVERING_BONES|WAIT_AFTER_DELIVERY_1|CLOSING_DELIVERY|WAIT_AFTER_CLOSE_DELIVERY|WAIT_CONFIRM_GUI|WAIT_CONFIRM_SETTLE|CLICK_CONFIRM_SLOT|WAIT_AFTER_CONFIRM_1|WAIT_AFTER_CONFIRM_2|WAIT_AFTER_CONFIRM_3|DOUBLE_ESCAPE|DOUBLE_RIGHTCLICK_FIRST|DOUBLE_RIGHTCLICK_SECOND|POST_CYCLE_DELAY") {
                $isBlatant = $true
                break
            }
        }

        if ($mod.FilenameToken -and $mod.HitCount -eq 0) {
            foreach ($token in @("vape","meteor","liquidbounce","wurst","futureclient","rusherhack","impactclient","aristois","dqrkis","doomsday","kamiblue","vapelite","novaclient","wolframclient","bleachhack")) {
                if ($mod.FilenameToken -match $token) {
                    $isBlatant = $true
                    break
                }
            }
        }

        if ($mod.ObfResult -and ($mod.ObfResult | Where-Object { $_ -match "Runtime\.exec|HTTP POST|Fake mod identity" }).Count -gt 0) {
            $isBlatant = $true
        }
        if ($mod.NetworkHits -and ($mod.NetworkHits | Where-Object { $_ -match "discord\.com/api/webhooks|discordapp\.com/api/webhooks|pastebin\.com/raw|grabify|TokenGrabber|SessionStealer|ReverseShell|sendWebhook" }).Count -gt 0) {
            $isBlatant = $true
        }
        if ($mod.MixinHits -and ($mod.MixinHits | Where-Object { $_ -match "EndCrystalEntityMixin|ExplosionMixinAccessor|PlayerMoveC2SPacketMixin|ClientConnectionMixin|Excessive mixin count" }).Count -gt 0) {
            $isBlatant = $true
        }

        if ($isBlatant) {
            $hasRealHits = ($mod.HitCount -gt 0) -or
                ($mod.MixinHits -and $mod.MixinHits.Count -gt 0) -or
                ($mod.BytecodeHits -and $mod.BytecodeHits.Count -gt 0) -or
                ($mod.NetworkHits -and $mod.NetworkHits.Count -gt 0) -or
                ($mod.FilenameToken)
            $obfOnlyTrigger = (-not $hasRealHits) -and ($mod.ObfResult -and $mod.ObfResult.Count -gt 0)
            if ($obfOnlyTrigger) { $isBlatant = $false }
        }

        if ($isBlatant) {
            $criticalThreats.Add($mod)
        } else {
            $suspiciousFiles.Add($mod)
        }
    }

    $report = [PSCustomObject]@{
        ScanTimestamp    = $scanTimestamp
        ModsPath         = $resolvedModsPath
        Jars             = $jars
        ActiveModules    = $activeModules
        MinecraftStatus  = $mcStatus
        JvmResults       = $jvmResults
        InjectorFindings = $injectorFindings
        Flagged          = $flagged
        Clean            = $clean
        CriticalThreats  = $criticalThreats
        SuspiciousFiles  = $suspiciousFiles
        DisallowedFound  = $disallowedFound
    }

    Show-IntegrityReport -Report $report
    return $report
}

$script:MonitorScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
$script:MonitorLogFile = $null
$script:MonitorStats = $null
$script:MonitorLogLock = [System.Threading.SpinLock]::new($false)
$script:FileCache = [System.Collections.Concurrent.ConcurrentDictionary[string, string]]::new()

$script:RxMacroTiming = [regex]::new('"delay"\s*:\s*\d+', [System.Text.RegularExpressions.RegexOptions]::Compiled -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$script:RxRepeat = [regex]::new('"repeat"', [System.Text.RegularExpressions.RegexOptions]::Compiled -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$script:RxSequence = [regex]::new('"sequence"', [System.Text.RegularExpressions.RegexOptions]::Compiled -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$script:RxOnboard = [regex]::new('"onboard"', [System.Text.RegularExpressions.RegexOptions]::Compiled -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$script:RxDevice = [regex]::new('"device"', [System.Text.RegularExpressions.RegexOptions]::Compiled -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$script:RxEngine = [regex]::new('"engine"', [System.Text.RegularExpressions.RegexOptions]::Compiled -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

$script:IgnorePaths = @(
    "\sentry\", "\User Data\", "\Cache\", "\GPUCache\", "\Code Cache\",
    "\Session Storage\", "\Local Storage\", "\IndexedDB\", "\Dictionaries\",
    "\Crashpad\", "\GrpcChann", "\logs\", "\Log\", "\CrashReports\"
)

function Test-IsNoise {
    param([string]$Path)

    $upperPath = $Path.ToUpperInvariant()
    foreach ($ignore in $script:IgnorePaths) {
        if ($upperPath.Contains($ignore.ToUpperInvariant())) {
            return $true
        }
    }
    return $false
}

$script:SoftwareProfiles = @(
    @{
        Name         = "Logitech G HUB"
        Paths        = @("$env:LOCALAPPDATA\LGHUB", "$env:APPDATA\LGHUB", "$env:PROGRAMDATA\LGHUB")
        Extensions   = @("*.json")
        Parser       = "Parse-LGHUB"
        MacroKeys    = @("macros", "assignments", "commands")
        ProcessNames = @("LGHUB", "LGHUB Agent")
    },
    @{
        Name         = "Logitech Gaming Software (Legacy)"
        Paths        = @("$env:APPDATA\Logitech\Logitech Gaming Software", "$env:LOCALAPPDATA\Logitech")
        Extensions   = @("*.json", "*.xml")
        Parser       = "Parse-Generic"
        MacroKeys    = @("macro", "assignment", "script")
        ProcessNames = @("LCore")
    },
    @{
        Name         = "Razer Synapse 3"
        Paths        = @(
            "$env:APPDATA\Razer\Synapse3",
            "$env:APPDATA\Razer\Synapse",
            "$env:LOCALAPPDATA\Razer\Synapse3",
            "$env:PROGRAMDATA\Razer\Synapse3"
        )
        Extensions   = @("*.json", "*.xml")
        Parser       = "Parse-Razer"
        MacroKeys    = @("Macro", "Action", "Script", "macro")
        ProcessNames = @("Razer Synapse", "RazerCentralService", "RazerStats")
    },
    @{
        Name         = "Razer Synapse 2 (Legacy)"
        Paths        = @("$env:APPDATA\Razer\Synapse2")
        Extensions   = @("*.json", "*.xml", "*.dat")
        Parser       = "Parse-Razer"
        MacroKeys    = @("Macro", "Action", "Script", "macro")
        ProcessNames = @("Razer Synapse", "RazerCentralService")
    },
    @{
        Name         = "SteelSeries GG"
        Paths        = @("$env:APPDATA\SteelSeries\SteelSeries GG", "$env:LOCALAPPDATA\SteelSeries\SteelSeries GG", "$env:LOCALAPPDATA\SteelSeries")
        Extensions   = @("*.json")
        Parser       = "Parse-SteelSeries"
        MacroKeys    = @("macro", "action", "binding")
        ProcessNames = @("SteelSeriesGG", "SteelSeriesEngine")
    },
    @{
        Name         = "SteelSeries Engine 3 (Legacy)"
        Paths        = @("$env:APPDATA\SteelSeries Engine 3")
        Extensions   = @("*.json")
        Parser       = "Parse-SteelSeries"
        MacroKeys    = @("macro", "action", "binding")
        ProcessNames = @("SteelSeriesEngine3")
    },
    @{
        Name         = "SteelSeries Engine 2 (Legacy)"
        Paths        = @("$env:APPDATA\SteelSeries Engine 2")
        Extensions   = @("*.json", "*.xml")
        Parser       = "Parse-SteelSeries"
        MacroKeys    = @("macro", "action", "binding")
        ProcessNames = @("SteelSeriesEngine2")
    },
    @{
        Name         = "Corsair iCUE"
        Paths        = @("$env:APPDATA\Corsair\CUE5", "$env:APPDATA\Corsair\CUE4", "$env:APPDATA\Corsair", "$env:LOCALAPPDATA\Corsair")
        Extensions   = @("*.cueprofile", "*.json")
        Parser       = "Parse-Generic"
        MacroKeys    = @("macro", "action", "command")
        ProcessNames = @("iCUE", "CorsairService")
    },
    @{
        Name         = "Corsair CUE 3 (Legacy)"
        Paths        = @("$env:APPDATA\Corsair\CUE3")
        Extensions   = @("*.cueprofile", "*.json")
        Parser       = "Parse-Generic"
        MacroKeys    = @("macro", "action", "command")
        ProcessNames = @("Cue")
    },
    @{
        Name         = "ASUS Armoury Crate"
        Paths        = @("$env:LOCALAPPDATA\ASUS\ArmouryCrate", "$env:LOCALAPPDATA\ASUS\AURA", "$env:APPDATA\ASUS\ArmouryCrate", "$env:PROGRAMDATA\ASUS\ArmouryCrate")
        Extensions   = @("*.json", "*.xml")
        Parser       = "Parse-Generic"
        MacroKeys    = @("macro", "key", "action")
        ProcessNames = @("ArmouryCrate", "ASUSOptimization")
    },
    @{
        Name         = "HyperX NGENUITY"
        Paths        = @("$env:LOCALAPPDATA\HyperX NGENUITY", "$env:APPDATA\HyperX NGENUITY", "$env:LOCALAPPDATA\HyperX")
        Extensions   = @("*.json")
        Parser       = "Parse-Generic"
        MacroKeys    = @("macro", "action", "binding")
        ProcessNames = @("NGENUITY")
    },
    @{
        Name         = "Wooting"
        Paths        = @("$env:LOCALAPPDATA\Wooting", "$env:APPDATA\Wooting")
        Extensions   = @("*.json")
        Parser       = "Parse-Generic"
        MacroKeys    = @("macro", "analog", "action")
        ProcessNames = @("WootingUACHelper", "Wooting")
    },
    @{
        Name         = "Glorious CORE"
        Paths        = @("$env:LOCALAPPDATA\Glorious\Glorious CORE", "$env:APPDATA\Glorious", "$env:LOCALAPPDATA\Glorious")
        Extensions   = @("*.json")
        Parser       = "Parse-Generic"
        MacroKeys    = @("macro", "key", "assignment", "sequence")
        ProcessNames = @("GloriousCORE")
    },
    @{
        Name         = "Bloody / A4Tech"
        Paths        = @("$env:LOCALAPPDATA\Bloody", "$env:PROGRAMDATA\Bloody", "$env:LOCALAPPDATA\A4Tech", "$env:PROGRAMDATA\A4Tech")
        Extensions   = @("*.dat", "*.json", "*.xml", "*.bin")
        Parser       = "Parse-Generic"
        MacroKeys    = @("macro", "Macro", "script", "Script", "shot")
        ProcessNames = @("Bloody7", "A4Tech")
    },
    @{
        Name         = "Cooler Master MasterPlus+"
        Paths        = @("$env:LOCALAPPDATA\Cooler Master", "$env:APPDATA\Cooler Master")
        Extensions   = @("*.json", "*.xml")
        Parser       = "Parse-Generic"
        MacroKeys    = @("macro", "assignment", "action")
        ProcessNames = @("MasterPlus")
    },
    @{
        Name         = "Roccat Swarm / Titan"
        Paths        = @("$env:APPDATA\Roccat", "$env:LOCALAPPDATA\Roccat")
        Extensions   = @("*.xml", "*.json")
        Parser       = "Parse-Generic"
        MacroKeys    = @("macro", "Macro", "sequence", "command")
        ProcessNames = @("Roccat Swarm", "Titan")
    }
)

function Get-FileContentFast {
    param([string]$Path)
    try { return [System.IO.File]::ReadAllText($Path) } catch { return $null }
}

function Test-MacroStringsFast {
    param(
        [string]$Text,
        [string[]]$Keys
    )

    $hits = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $Keys) {
        if ($Text.IndexOf($key, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $hits.Add("  [!] Key: '$key'")
        }
    }
    if ($script:RxMacroTiming.IsMatch($Text)) { $hits.Add("  [!] Timed delays detected") }
    if ($script:RxRepeat.IsMatch($Text)) { $hits.Add("  [!] Repeat or loop detected") }
    if ($script:RxSequence.IsMatch($Text)) { $hits.Add("  [!] Key sequence detected") }
    if ($script:RxOnboard.IsMatch($Text)) { $hits.Add("  [!] Onboard memory flag") }
    return ,$hits
}

function Parse-Generic {
    param(
        [string]$FilePath,
        [string[]]$MacroKeys
    )

    $text = Get-FileContentFast $FilePath
    if (-not $text) { return @("  [~] File locked or unreadable") }
    $hits = Test-MacroStringsFast -Text $text -Keys $MacroKeys
    if ($hits.Count -gt 0) { return ,$hits }
    return @()
}

function Parse-LGHUB {
    param(
        [string]$FilePath,
        [string[]]$MacroKeys
    )

    $text = Get-FileContentFast $FilePath
    if (-not $text) { return @("  [~] File locked or unreadable") }
    $hits = Test-MacroStringsFast -Text $text -Keys $MacroKeys
    try {
        $json = $text | ConvertFrom-Json -ErrorAction Stop
        if ($json.macros) {
            $hits.Add("  [!] $($json.macros.Count) macro(s) defined")
            foreach ($macro in $json.macros) {
                if ($macro.name) { $hits.Add("      - '$($macro.name)'") }
            }
        }
        if ($json.assignments) {
            $hits.Add("  [!] $($json.assignments.Count) button assignment(s)")
        }
    } catch {}
    return ,$hits
}

function Parse-Razer {
    param(
        [string]$FilePath,
        [string[]]$MacroKeys
    )

    $text = Get-FileContentFast $FilePath
    if (-not $text) { return @("  [~] File locked or unreadable") }

    if ([System.IO.Path]::GetExtension($FilePath) -eq ".xml") {
        $hits = [System.Collections.Generic.List[string]]::new()
        try {
            [xml]$xml = $text
            $nodes = $xml.SelectNodes("//Macro")
            if ($nodes.Count -gt 0) {
                $hits.Add("  [!] $($nodes.Count) Razer macro(s)")
                foreach ($node in $nodes) {
                    $hits.Add("      - $($node.Name): $($node.ChildNodes.Count) steps")
                }
            }
        } catch {}
        if ($hits.Count -eq 0) { return @() }
        return ,$hits
    }

    $hits = Test-MacroStringsFast -Text $text -Keys $MacroKeys
    return ,$hits
}

function Parse-SteelSeries {
    param(
        [string]$FilePath,
        [string[]]$MacroKeys
    )

    $text = Get-FileContentFast $FilePath
    if (-not $text) { return @("  [~] File locked or unreadable") }
    $hits = Test-MacroStringsFast -Text $text -Keys $MacroKeys
    if ($script:RxDevice.IsMatch($text)) { $hits.Add("  [i] Device profile") }
    if ($script:RxEngine.IsMatch($text)) { $hits.Add("  [i] Engine-linked") }
    return ,$hits
}

$script:ParserMap = @{
    "Parse-Generic"     = ${function:Parse-Generic}
    "Parse-LGHUB"       = ${function:Parse-LGHUB}
    "Parse-Razer"       = ${function:Parse-Razer}
    "Parse-SteelSeries" = ${function:Parse-SteelSeries}
}
foreach ($software in $script:SoftwareProfiles) {
    $software.ParserBlock = $script:ParserMap[$software.Parser]
}

function Get-MD5Fast {
    param([string]$Path)

    try {
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $hash = $md5.ComputeHash($bytes)
        $md5.Dispose()
        return [System.BitConverter]::ToString($hash).Replace("-", "").ToUpperInvariant()
    } catch {
        return $null
    }
}

function Get-FileSizeString {
    param([long]$Bytes)

    if ($Bytes -gt 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -gt 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Get-RunningSoftwareProcess {
    param([string[]]$Names)

    foreach ($name in $Names) {
        if (Get-Process -Name $name -ErrorAction SilentlyContinue) {
            return $name
        }
    }
    return $null
}

function Invoke-AlertSound {
    param([string]$Type = "Info")

    try {
        if ($Type -eq "Critical") {
            [System.Media.SystemSounds]::Hand.Play()
        } else {
            [System.Media.SystemSounds]::Asterisk.Play()
        }
    } catch {}
}

function Update-WindowTitle {
    $Host.UI.RawUI.WindowTitle = "Mine Tiers | Del:$($script:MonitorStats.Deleted) Mod:$($script:MonitorStats.Changed) Macros:$($script:MonitorStats.Macros) Filtered:$($script:MonitorStats.Filtered)"
}

function Write-MonitorLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [ConsoleColor]$Color = [ConsoleColor]::White
    )

    $timestamp = [DateTime]::Now.ToString("HH:mm:ss.fff")
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line -ForegroundColor $Color

    $taken = $false
    try {
        $script:MonitorLogLock.Enter([ref]$taken)
        [System.IO.File]::AppendAllText($script:MonitorLogFile, "$line`r`n")
    } finally {
        if ($taken) { $script:MonitorLogLock.Exit() }
    }
}

function Invoke-FastSnapshot {
    param($SoftwareList)

    $results = [System.Collections.Generic.List[string]]::new()
    foreach ($software in $SoftwareList) {
        foreach ($basePath in $software._LivePaths) {
            if (-not (Test-Path $basePath)) { continue }
            foreach ($extension in $software.Extensions) {
                try {
                    $files = [System.IO.Directory]::GetFiles($basePath, $extension, [System.IO.SearchOption]::AllDirectories)
                    foreach ($file in $files) {
                        if (-not (Test-IsNoise -Path $file)) {
                            $results.Add("SCAN|$($software.Name)|$file")
                        }
                    }
                } catch {}
            }
        }
    }
    return ,$results
}

function Wait-FileAvailable {
    param(
        [string]$Path,
        [int]$MaxMs = 50
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($stopwatch.ElapsedMilliseconds -lt $MaxMs) {
        try {
            $fileStream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $fileStream.Close()
            return $true
        } catch {
            [System.Threading.Thread]::Sleep(1)
        }
    }
    return $false
}

function Build-InitialCache {
    param($SoftwareList)

    $script:FileCache.Clear()
    foreach ($software in $SoftwareList) {
        foreach ($basePath in $software._LivePaths) {
            if (-not (Test-Path $basePath)) { continue }
            foreach ($extension in $software.Extensions) {
                try {
                    $files = [System.IO.Directory]::GetFiles($basePath, $extension, [System.IO.SearchOption]::AllDirectories)
                    foreach ($file in $files) {
                        if (Test-IsNoise -Path $file) { continue }
                        $hash = Get-MD5Fast -Path $file
                        if ($hash) {
                            $size = (New-Object System.IO.FileInfo($file)).Length
                            $null = $script:FileCache.TryAdd($file.ToUpperInvariant(), "$hash|$size")
                        }
                    }
                } catch {}
            }
        }
    }
}

function New-InstantHandler {
    param($Software)

    return {
        $filePath = $Event.SourceEventArgs.FullPath
        $changeType = $Event.SourceEventArgs.ChangeType
        $sw = $Event.MessageData.SW
        $logFile = $Event.MessageData.Log
        $parserBlock = $Event.MessageData.ParserBlock
        $timestamp = [DateTime]::Now.ToString("HH:mm:ss.fff")

        if (Test-IsNoise -Path $filePath) {
            $script:MonitorStats.Filtered++
            return
        }

        if ($changeType -eq "Deleted") {
            $script:MonitorStats.Deleted++

            $oldValue = $null
            $sizeText = "Unknown"
            if ($script:FileCache.TryRemove($filePath.ToUpperInvariant(), [ref]$oldValue)) {
                if ($oldValue -match '\|(\d+)$') {
                    $sizeText = Get-FileSizeString -Bytes ([long]$Matches[1])
                }
            }

            $message = "[$timestamp] [DELETED] [$($sw.Name)] $filePath (Size: $sizeText)"
            Write-Host $message -ForegroundColor Red
            [System.IO.File]::AppendAllText($logFile, "$message`r`n")

            $processName = Get-RunningSoftwareProcess -Names $sw.ProcessNames
            $processMessage = if ($processName) {
                "    [!] Process '$processName.exe' is actively running."
            } else {
                "    [!] Software process is not running."
            }
            Write-Host $processMessage -ForegroundColor Red
            [System.IO.File]::AppendAllText($logFile, "$processMessage`r`n")

            $warning = "    [!] Possible evidence removal - macro pushed to onboard memory?"
            Write-Host $warning -ForegroundColor Red
            [System.IO.File]::AppendAllText($logFile, "$warning`r`n")

            Invoke-AlertSound -Type "Critical"
            Update-WindowTitle
            return
        }

        if (-not [System.IO.File]::Exists($filePath)) { return }

        if ($changeType -eq "Created") {
            $script:MonitorStats.Created++
        } else {
            $script:MonitorStats.Changed++
        }

        $color = if ($changeType -eq "Created") { "Green" } else { "Magenta" }
        $message = "[$timestamp] [$changeType] [$($sw.Name)] $filePath"
        Write-Host $message -ForegroundColor $color
        [System.IO.File]::AppendAllText($logFile, "$message`r`n")

        if (-not (Wait-FileAvailable -Path $filePath -MaxMs 50)) {
            Update-WindowTitle
            return
        }

        try {
            $newHash = Get-MD5Fast -Path $filePath
            $fileSize = (New-Object System.IO.FileInfo($filePath)).Length
            if (-not $newHash) {
                Update-WindowTitle
                return
            }

            $oldValue = $null
            $oldHash = $null
            if ($script:FileCache.TryGetValue($filePath.ToUpperInvariant(), [ref]$oldValue)) {
                $oldHash = $oldValue -split '\|', 2 | Select-Object -First 1
                if ($oldHash -eq $newHash) { return }
            }
            $null = $script:FileCache.AddOrUpdate($filePath.ToUpperInvariant(), "$newHash|$fileSize", { "$newHash|$fileSize" })
        } catch {
            Update-WindowTitle
            return
        }

        try {
            if ($null -ne $parserBlock) {
                $results = & $parserBlock -FilePath $filePath -MacroKeys $sw.MacroKeys
                if ($results.Count -gt 0) {
                    $script:MonitorStats.Macros++
                    Invoke-AlertSound -Type "Info"

                    $processName = Get-RunningSoftwareProcess -Names $sw.ProcessNames
                    if ($processName) {
                        $processMessage = "    [i] Software process '$processName.exe' is running."
                        Write-Host $processMessage -ForegroundColor DarkMagenta
                        [System.IO.File]::AppendAllText($logFile, "$processMessage`r`n")
                    }

                    $macroMessage = "    [!] MACROS DETECTED:"
                    Write-Host $macroMessage -ForegroundColor Yellow
                    [System.IO.File]::AppendAllText($logFile, "$macroMessage`r`n")
                    foreach ($result in $results) {
                        Write-Host $result -ForegroundColor Yellow
                        [System.IO.File]::AppendAllText($logFile, "$result`r`n")
                    }
                }
            }
        } catch {}

        Update-WindowTitle
    }
}

function New-FastWatcher {
    param(
        [string]$Path,
        [string]$Filter,
        $Software
    )

    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = $Path
    $watcher.Filter = $Filter
    $watcher.IncludeSubdirectories = $true
    $watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName `
        -bor [System.IO.NotifyFilters]::LastWrite `
        -bor [System.IO.NotifyFilters]::Size
    $watcher.InternalBufferSize = 65536
    $watcher.EnableRaisingEvents = $true

    $messageData = @{
        SW          = $Software
        Log         = $script:MonitorLogFile
        ParserBlock = $Software.ParserBlock
    }
    $handler = New-InstantHandler -Software $Software

    Register-ObjectEvent -InputObject $watcher -EventName "Deleted" -Action $handler -MessageData $messageData | Out-Null
    Register-ObjectEvent -InputObject $watcher -EventName "Created" -Action $handler -MessageData $messageData | Out-Null
    Register-ObjectEvent -InputObject $watcher -EventName "Changed" -Action $handler -MessageData $messageData | Out-Null

    return $watcher
}

function Start-MacroMonitor {
    $script:MonitorLogFile = Join-Path -Path $script:MonitorScriptDir -ChildPath ("MineTiers_MacroMonitor_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    $script:MonitorStats = @{
        Deleted  = 0
        Created  = 0
        Changed  = 0
        Macros   = 0
        Filtered = 0
    }

    Clear-Host
    Show-MineTiersBanner -Subtitle "Live Macro Monitor"
    Write-Host "  Log: $script:MonitorLogFile" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  [*] Probing software paths..." -ForegroundColor Cyan
    $foundAnySoftware = $false
    foreach ($software in $script:SoftwareProfiles) {
        $livePaths = @()
        foreach ($path in $software.Paths) {
            if (Test-Path $path) {
                $livePaths += $path
                Write-Host "      [+] $($software.Name) -> $path" -ForegroundColor DarkGreen
            }
        }
        if ($livePaths.Count -gt 0) {
            $software._LivePaths = $livePaths
            $foundAnySoftware = $true
        } else {
            Write-Host "      [ ] $($software.Name) - no paths found" -ForegroundColor DarkGray
            $software._LivePaths = @()
        }
    }
    Write-Host ""

    if (-not $foundAnySoftware) {
        Write-MonitorLog "No supported mouse software directories found. Exiting." -Level "WARN" -Color Yellow
        return
    }

    Write-Host "  [*] Scanning files and building cache..." -ForegroundColor Cyan
    $scanResults = Invoke-FastSnapshot -SoftwareList $script:SoftwareProfiles
    Build-InitialCache -SoftwareList $script:SoftwareProfiles
    Write-Host "  [*] Found $($scanResults.Count) relevant file(s)" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "  [*] Scanning for existing macros..." -ForegroundColor DarkCyan
    $macroFoundCount = 0
    foreach ($entry in $scanResults) {
        $parts = $entry -split "\|", 3
        if ($parts.Count -lt 3) { continue }
        $softwareName = $parts[1]
        $filePath = $parts[2]
        $software = $script:SoftwareProfiles | Where-Object { $_.Name -eq $softwareName } | Select-Object -First 1
        if (-not $software -or $null -eq $software.ParserBlock) { continue }

        $results = & $software.ParserBlock -FilePath $filePath -MacroKeys $software.MacroKeys
        if ($results.Count -gt 0) {
            $macroFoundCount++
            $script:MonitorStats.Macros++
            Write-Host "      [$softwareName] " -ForegroundColor White -NoNewline
            Write-Host "$(Split-Path $filePath -Leaf)" -ForegroundColor Yellow -NoNewline
            Write-Host " - MACROS FOUND" -ForegroundColor Yellow
            foreach ($result in $results) {
                Write-Host $result -ForegroundColor DarkYellow
            }
        }
    }
    if ($macroFoundCount -eq 0) {
        Write-Host "      No active macros found." -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "  [*] Initial scan complete." -ForegroundColor Magenta
    Write-Host ""

    $activeWatchers = @()
    $watcherCreated = $false
    foreach ($software in $script:SoftwareProfiles) {
        if ($software._LivePaths.Count -eq 0) { continue }
        Write-Host "      [+] $($software.Name)" -ForegroundColor Green
        foreach ($path in $software._LivePaths) {
            foreach ($extension in $software.Extensions) {
                $watcher = New-FastWatcher -Path $path -Filter $extension -Software $software
                $activeWatchers += $watcher
                Write-Host "          -> $extension @ $path" -ForegroundColor DarkGray
            }
        }
        $watcherCreated = $true
    }
    Write-Host ""

    if (-not $watcherCreated) { return }

    Write-Host "  Mine Tiers monitor is live. Press Ctrl+C to stop." -ForegroundColor Magenta
    Update-WindowTitle

    try {
        while ($true) {
            [System.Threading.Thread]::Sleep(50)
        }
    } finally {
        foreach ($watcher in $activeWatchers) {
            try {
                $watcher.EnableRaisingEvents = $false
                $watcher.Dispose()
            } catch {}
        }
        Get-EventSubscriber | Unregister-Event -ErrorAction SilentlyContinue

        $Host.UI.RawUI.WindowTitle = "Mine Tiers | Monitor stopped"
        Write-Host ""
        Write-ReportBorder Top Magenta
        Write-ReportText "  MINE TIERS MONITOR SESSION ENDED" Magenta Magenta
        Write-ReportBorder Sep Magenta
        Write-ReportRow "  Files Created : " $script:MonitorStats.Created DarkGray White Magenta
        Write-ReportRow "  Files Modified: " $script:MonitorStats.Changed DarkGray White Magenta
        Write-ReportRow "  Files Deleted : " $script:MonitorStats.Deleted Red White Magenta
        Write-ReportRow "  Macros Found  : " $script:MonitorStats.Macros Yellow White Magenta
        Write-ReportRow "  Noise Filtered: " $script:MonitorStats.Filtered DarkGray White Magenta
        Write-ReportBorder Bot Magenta
        Write-MonitorLog "Session ended. Log saved to: $script:MonitorLogFile" -Color Magenta
    }
}

Initialize-Console

$selectedMode = if ($Mode -eq "Menu") { Select-RunMode } else { $Mode }
if ($selectedMode -eq "Exit") { return }

switch ($selectedMode) {
    "Scan" {
        $null = Invoke-IntegrityScan -RequestedModsPath $ModsPath
        Pause-ForExit
    }
    "Monitor" {
        Start-MacroMonitor
    }
    "Full" {
        $scanReport = Invoke-IntegrityScan -RequestedModsPath $ModsPath
        if ($null -ne $scanReport) {
            Pause-ForExit
        }
        Start-MacroMonitor
    }
}
