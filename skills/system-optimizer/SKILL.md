---
name: system-optimizer
description: Execute Windows system, game and software optimization tasks directly via PowerShell, registry edits and config-file changes - never via user advice. Trigger on any request to speed up, tweak, debloat, optimize or configure the OS, a game or an app. Always backs up before changing, applies the change by script/file, and offers the ready script to run.
---

# System Optimizer (решала, не консультант)

The user does not want advice - they want the machine changed. You apply optimization by writing and running PowerShell, editing the registry, or patching config files. You never end with "open settings and click X". If you know a fix as a script, you write the script, explain it in two words, and offer to run it.

## When to activate

- Any request to ускорить / оптимизировать / настроить систему, игру или программу
- FPS, лаги, фризы, разгон, debloat, отключение служб/телеметрии/оверлеев, правка реестра
- Phrases like: настрой под слабый ПК, убери лаги, отключи оверлей, выключи службу, правь реестр, оптимизируй Windows

## When NOT to activate

- Pure project-repo code changes (use the normal edit + `verify-changes` flow)
- Installing/removing packages (use skill `safe-dependency`)
- Any change that is purely informational and the user only asked to understand (not to change)

## Non-negotiables

1. BACK UP before you change anything - registry key, service startup type, or config file.
2. Apply by code, never by advice. No "go to Settings and click..." endings.
3. Prove the change with output (before/after, `Get-Service`, file diff).
4. System-wide or admin changes require explicit user go-ahead. Offer the ready script and ask "Запускаю?".
5. Always state the rollback path (the backup you just made).

## Script header (every generated .ps1)

Always start system-change scripts with these two lines to avoid unexpected hangs from errors or progress bars:

```powershell
$ErrorActionPreference = 'Stop'             # abort on any error instead of silently continuing
$ProgressPreference    = 'SilentlyContinue' # suppress progress bars that can hang redirected runs
```

Report status with `Write-Host` so the user sees what is happening when the script runs in its own window:

```powershell
Write-Host "[1/3] Backing up..."     -ForegroundColor Cyan
Write-Host "[2/3] Applying change..." -ForegroundColor Cyan
Write-Host "[3/3] Done."              -ForegroundColor Green
```

## Step 1 - Locate the target

Config files (per-user, no admin needed):

```powershell
# Find game/app config files
Get-ChildItem "$env:LOCALAPPDATA\Genshin Impact" -Recurse -Include *.ini,*.cfg,*.json,*.xml -ErrorAction SilentlyContinue |
  Select-Object FullName, Length, LastWriteTime
```

Services / telemetry / startup targets:

```powershell
Get-Service DiagTrack, SysMain, WSearch -ErrorAction SilentlyContinue |
  Select-Object Name, Status, StartType
```

Registry targets - read the current value BEFORE editing:

```powershell
Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "HubMode" -ErrorAction SilentlyContinue
```

## Step 2 - Back up (always, before any change)

```powershell
$stamp  = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = Join-Path $env:USERPROFILE "optimization-backup-$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null

# Registry key -> .reg file (reg export works without admin for HKCU; HKLM needs admin)
reg export "HKLM\SYSTEM\CurrentControlSet\Services\DiagTrack" "$backup\DiagTrack.reg" /y

# Config file -> copy
Copy-Item "$env:LOCALAPPDATA\Genshin Impact\config.ini" "$backup\config.ini.bak" -Force

# System restore point (requires admin)
Checkpoint-Computer -Description "Before optimization $stamp" -RestorePointType MODIFY_SETTINGS
```

Record `$backup` in the report - it is the rollback plan.

## Step 3 - Apply the change (PowerShell, not clicks)

Disable a service (telemetry, search, etc.):

```powershell
Stop-Service -Name DiagTrack -Force -ErrorAction SilentlyContinue
Set-Service  -Name DiagTrack -StartupType Disabled
Get-Service  -Name DiagTrack | Select-Object Name, Status, StartType
```

Registry tweak (create value if missing, otherwise update - both paths covered):

```powershell
$path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
if (Get-ItemProperty -Path $path -Name "AllowGameDVR" -ErrorAction SilentlyContinue) {
  Set-ItemProperty -Path $path -Name "AllowGameDVR" -Value 0
} else {
  New-ItemProperty -Path $path -Name "AllowGameDVR" -Value 0 -PropertyType DWord -Force | Out-Null
}
Get-ItemProperty -Path $path -Name "AllowGameDVR"
```

Config-file edit (read -> replace -> write; backup already taken in Step 2):

```powershell
$cfg = "$env:LOCALAPPDATA\Genshin Impact\config.ini"
(Get-Content $cfg) -replace '^RenderResolution=.*','RenderResolution=0.8' |
  Set-Content $cfg -Encoding UTF8
Get-Content $cfg | Select-String 'RenderResolution'
```

## Step 4 - Report & offer (do not end with instructions)

```
OPTIMIZED: <target>
- Backup:   <path>
- Change:   <what was set, from -> to>
- Proof:    <command output / before-after>
- Rollback: <how to restore from the backup>
```

Then offer and act - never a checklist:

> Я подготовил скрипт для <цель>. Он делает бэкап в `<path>` и применяет <изменение>. Запускаю?

## Hard rules

- No change without a backup taken first.
- No "go to settings and click" endings - produce the script, explain it in two words, offer to run it.
- System-wide/admin changes only after the user confirms.
- Always provide the rollback path.
- If a change genuinely cannot be safely automated, say so explicitly and why - never disguise advice as a completed action.
- Every generated `.ps1` starts with `$ErrorActionPreference = 'Stop'` and `$ProgressPreference = 'SilentlyContinue'`, and reports progress via `Write-Host` so a windowed run stays visible and does not hang.