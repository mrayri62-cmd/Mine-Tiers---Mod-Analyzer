# Mine Tiers - Mod Analyzer

Mine Tiers is a Windows PowerShell integrity tool for Minecraft clients. It combines live mod folder detection, mod JAR scanning, JVM argument checks, injector/runtime checks, and mouse macro monitoring in one script.

## Features

- Detects the mods folder used by the currently running Minecraft instance through `--gameDir`.
- Scans Minecraft mod JARs for suspicious strings, mixins, bytecode hooks, network exfiltration markers, and heavy obfuscation.
- Checks live JVM arguments for suspicious Java agents, Fabric/Forge runtime mod injection flags, debugger agents, and unsafe runtime options.
- Checks for injector-style runtime indicators around the running Minecraft process.
- Monitors common mouse software profiles for macro creation, modification, deletion, and onboard-memory evidence removal.

## Requirements

- Windows
- Windows PowerShell 5.1 or newer
- Minecraft must be running for best live mod and injector detection
- Administrator PowerShell is recommended for stronger runtime/module inspection

## Quick Start

Open PowerShell as Administrator, start Minecraft, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Mine-Tiers.ps1" -Mode Full -ModsPath live
```

## Modes

```powershell
# Full scan, then live macro monitor
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Mine-Tiers.ps1" -Mode Full -ModsPath live

# Scan mods, JVM arguments, and injector/runtime indicators only
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Mine-Tiers.ps1" -Mode Scan -ModsPath live

# Start only the live macro monitor
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Mine-Tiers.ps1" -Mode Monitor
```

`-ModsPath live` tells Mine Tiers to scan the mods folder used by the Minecraft process that is currently open. You can also pass a specific folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Mine-Tiers.ps1" -Mode Scan -ModsPath "C:\Path\To\mods"
```

## Notes

Mine Tiers is an analysis tool, not a replacement for an antivirus or professional malware analysis. Some mods can trigger false positives, especially combat optimizers, mixin-heavy mods, and mods that hook Minecraft networking or interaction internals.

Review findings carefully before taking action.
