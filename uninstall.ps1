<#
.SYNOPSIS
    Удаление cline-toolkit, установленного через install.ps1.
.DESCRIPTION
    Работает строго по манифесту установки (.cline-toolkit-manifest.json):
    удаляются только файлы, которые положил toolkit. Посторонние файлы в целевых
    каталогах не трогаются.

    Файл, изменённый после установки (хеш не совпадает с манифестом), по
    умолчанию остаётся — для принудительного удаления используйте -Force.

    -RestoreMcpBackup возвращает самый свежий из cline_mcp_settings.json.bak-*,
    созданных установщиком (текущий конфиг перед этим сохраняется в
    cline_mcp_settings.json.pre-restore-<timestamp>).
.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\uninstall.ps1 -DryRun
.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\uninstall.ps1
.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\uninstall.ps1 -RestoreMcpBackup
.PARAMETER ClineDir
    Каталог ~/.cline (по умолчанию $HOME\.cline или $env:CLINE_DIR).
.PARAMETER DocumentsDir
    Каталог «Мои документы» (по умолчанию — системный, или $env:CLINE_DOCUMENTS_DIR).
.PARAMETER RulesDir
    Override каталога глобальных правил.
.PARAMETER WorkflowsDir
    Override каталога глобальных воркфлоу.
.PARAMETER SkillsDir
    Override каталога глобальных навыков.
.PARAMETER McpFile
    Override пути cline_mcp_settings.json.
.PARAMETER ManifestFile
    Override пути манифеста установки.
.PARAMETER Force
    Удалять файлы даже если они изменены после установки.
.PARAMETER RestoreMcpBackup
    Восстановить MCP-конфиг из самого свежего бэкапа установщика.
.PARAMETER DryRun
    Показать план удаления без изменения файлов.
#>
param(
    [string]$ClineDir,
    [string]$DocumentsDir,
    [string]$RulesDir,
    [string]$WorkflowsDir,
    [string]$SkillsDir,
    [string]$McpFile,
    [string]$ManifestFile,
    [switch]$Force,
    [switch]$RestoreMcpBackup,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Step($msg) { Write-Host "==> $msg" }
function Write-Ok($msg)   { Write-Host "    [OK] $msg" }
function Write-Info($msg) { Write-Host "    [i]  $msg" }
function Write-Warn2($msg){ Write-Host "    [!]  $msg" -ForegroundColor Yellow }

function Get-DocumentsDir {
    if (-not [string]::IsNullOrWhiteSpace($env:CLINE_DOCUMENTS_DIR)) { return $env:CLINE_DOCUMENTS_DIR.Trim() }
    try {
        $p = [Environment]::GetFolderPath('MyDocuments')
        if (-not [string]::IsNullOrWhiteSpace($p)) { return $p }
    } catch { }
    return (Join-Path $HOME 'Documents')
}

function Get-ClineDirPath {
    if (-not [string]::IsNullOrWhiteSpace($ClineDir)) { return $ClineDir }
    if (-not [string]::IsNullOrWhiteSpace($env:CLINE_DIR)) { return $env:CLINE_DIR.Trim() }
    return (Join-Path $HOME '.cline')
}

function Test-PathInsideTargets {
    param([string]$Child, [string[]]$Roots)
    try { $c = [IO.Path]::GetFullPath($Child) } catch { return $false }
    foreach ($root in $Roots) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $r = [IO.Path]::GetFullPath($root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        if ($c.StartsWith($r, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

$cline     = Get-ClineDirPath
$documents = if (-not [string]::IsNullOrWhiteSpace($DocumentsDir)) { $DocumentsDir } else { Get-DocumentsDir }
$clineDocs = Join-Path $documents 'Cline'

$rulesTarget     = if (-not [string]::IsNullOrWhiteSpace($RulesDir))     { $RulesDir }     else { Join-Path $clineDocs 'Rules' }
$workflowsTarget = if (-not [string]::IsNullOrWhiteSpace($WorkflowsDir)) { $WorkflowsDir } else { Join-Path $clineDocs 'Workflows' }
$skillsTarget    = if (-not [string]::IsNullOrWhiteSpace($SkillsDir))    { $SkillsDir }    else { Join-Path $cline 'skills' }
$mcpTarget       = if (-not [string]::IsNullOrWhiteSpace($McpFile))      { $McpFile }      else { Join-Path $cline 'data\settings\cline_mcp_settings.json' }
$manifestPath    = if (-not [string]::IsNullOrWhiteSpace($ManifestFile)) { $ManifestFile } else { Join-Path $cline '.cline-toolkit-manifest.json' }

Write-Step ' cline-toolkit uninstaller'
Write-Host ("     manifest: {0}" -f $manifestPath)
Write-Host ("     cline dir: {0}" -f $cline)
Write-Host ""

$manifest = $null
if (Test-Path -LiteralPath $manifestPath) {
    try { $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json }
    catch { Write-Warn2 ("манифест не читается: {0}" -f $manifestPath) }
}

if ($null -eq $manifest) {
    if (-not $RestoreMcpBackup) {
        Write-Warn2 'манифест установки не найден — удалять по нему нечего.'
        Write-Info ("Проверьте путь или удалите вручную: {0}; {1}; {2}" -f $rulesTarget, $workflowsTarget, $skillsTarget)
        exit 1
    }
    Write-Info 'манифест не найден — будет только восстановление MCP из бэкапа'
}

$removed = 0
$kept    = 0
$missing = 0

if ($null -ne $manifest -and $null -ne $manifest.files) {
    Write-Step ("Удаление файлов из манифеста (v{0}, {1} записей)" -f $manifest.version, @($manifest.files).Count)
    foreach ($entry in @($manifest.files)) {
        if ([string]::IsNullOrWhiteSpace($entry.path)) { continue }
        if (-not (Test-PathInsideTargets -Child $entry.path -Roots @($rulesTarget, $workflowsTarget, $skillsTarget))) {
            Write-Warn2 ("пропущен путь вне целевых каталогов: {0}" -f $entry.path)
            $kept++
            continue
        }
        if (-not (Test-Path -LiteralPath $entry.path)) { $missing++; continue }
        if (-not $Force -and $entry.sha256) {
            $current = (Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash
            if ($current -ne $entry.sha256) {
                Write-Info ("оставлен (изменён после установки): {0}" -f $entry.path)
                $kept++
                continue
            }
        }
        if ($DryRun) {
            Write-Info ("будет удалён ({0}): {1}" -f $entry.kind, $entry.path)
        } else {
            Remove-Item -LiteralPath $entry.path -Force
            Write-Ok ("удалён ({0}): {1}" -f $entry.kind, $entry.path)
        }
        $removed++
    }
}

# Пустые каталоги навыков: после удаления переименованного навыка не должно оставаться пустых папок
if (-not $DryRun -and (Test-Path -LiteralPath $skillsTarget)) {
    $dirs = @(Get-ChildItem -LiteralPath $skillsTarget -Directory -Recurse -ErrorAction SilentlyContinue)
    foreach ($d in ($dirs | Sort-Object { $_.FullName.Length } -Descending)) {
        if ((Test-Path -LiteralPath $d.FullName) -and @(Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0) {
            Remove-Item -LiteralPath $d.FullName -Force
        }
    }
}

if ($RestoreMcpBackup) {
    Write-Step 'Восстановление MCP-конфига из бэкапа'
    $mcpDir = Split-Path -Parent $mcpTarget
    $backups = @(Get-ChildItem -LiteralPath $mcpDir -Filter 'cline_mcp_settings.json.bak-*' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)
    if ($backups.Count -eq 0) {
        Write-Warn2 ("бэкапы не найдены в {0}" -f $mcpDir)
    } else {
        $latest = $backups[0]
        Write-Info ("источник: {0} ({1})" -f $latest.FullName, $latest.LastWriteTime)
        if ($DryRun) {
            Write-Info ("будет восстановлен MCP-конфиг -> {0}" -f $mcpTarget)
        } else {
            if (Test-Path -LiteralPath $mcpTarget) {
                $preRestore = ("{0}.pre-restore-{1}" -f $mcpTarget, (Get-Date -Format 'yyyyMMdd-HHmmss'))
                Copy-Item -LiteralPath $mcpTarget -Destination $preRestore -Force
                Write-Info ("текущий конфиг сохранён: {0}" -f $preRestore)
            }
            New-Item -ItemType Directory -Force -Path $mcpDir | Out-Null
            Copy-Item -LiteralPath $latest.FullName -Destination $mcpTarget -Force
            Write-Ok ("MCP-конфиг восстановлен: {0}" -f $mcpTarget)
        }
    }
}

if (-not $DryRun -and (Test-Path -LiteralPath $manifestPath)) {
    Remove-Item -LiteralPath $manifestPath -Force
    Write-Ok ("манифест удалён: {0}" -f $manifestPath)
}

Write-Host ""
Write-Step ($(if ($DryRun) { 'Проверка завершена (dry-run, файлы не изменены)' } else { 'Удаление завершено' }))
Write-Host ("     Удалено: {0} | Изменено вручную (оставлено): {1} | Уже отсутствовало: {2}" -f $removed, $kept, $missing)
Write-Host "     Перезапустите Cline, чтобы он перестал видеть удалённые правила/навыки." -ForegroundColor Cyan
exit 0
