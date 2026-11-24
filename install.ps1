<#
.SYNOPSIS
    Установка cline-toolkit в глобальные каталоги Cline.
.DESCRIPTION
    Раскладка целевых каталогов проверена по коду расширения Cline 4.1.x:

      • глобальные правила  -> <Мои документы>\Cline\Rules
      • глобальные воркфлоу  -> <Мои документы>\Cline\Workflows
      • глобальные навыки    -> <CLINE_DIR>\skills   (по умолчанию ~/.cline/skills)
      • MCP-настройки        -> <CLINE_DIR>\data\settings\cline_mcp_settings.json

    Скиллы Cline дополнительно читает из ~/.agents/skills, правила и воркфлоу —
    только из папки Cline в «Моих документах» (плоские *.md в ~/.cline и папка
    ~/.cline/workflows современными версиями Cline НЕ читаются).

    Скрипт сохраняет существующий рабочий ключ Tavily, не трогает посторонние
    файлы, пишет JSON без BOM и (если не указан -KeepLegacyCopies) убирает
    устаревшие копии, оставшиеся от прежних версий установщика — только те,
    что побайтово совпадают с файлами репозитория.
.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\install.ps1
.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
.PARAMETER ClineDir
    Каталог ~/.cline (по умолчанию $HOME\.cline или $env:CLINE_DIR).
    Здесь живут skills/ и data/settings/.
.PARAMETER DocumentsDir
    Каталог «Мои документы» (по умолчанию — системный, или $env:CLINE_DOCUMENTS_DIR).
.PARAMETER RulesDir
    Override каталога глобальных правил (по умолчанию <DocumentsDir>\Cline\Rules).
.PARAMETER WorkflowsDir
    Override каталога глобальных воркфлоу (по умолчанию <DocumentsDir>\Cline\Workflows).
.PARAMETER SkillsDir
    Override каталога глобальных навыков (по умолчанию <ClineDir>\skills).
.PARAMETER McpFile
    Override пути cline_mcp_settings.json (по умолчанию <ClineDir>\data\settings\...).
.PARAMETER KeepLegacyCopies
    Не удалять устаревшие копии из ~/.cline (плоские *.md и ~/.cline/workflows).
.PARAMETER DryRun
    Показать план установки без записи на диск.
#>
param(
    [string]$ClineDir,
    [string]$DocumentsDir,
    [string]$RulesDir,
    [string]$WorkflowsDir,
    [string]$SkillsDir,
    [string]$McpFile,
    [switch]$KeepLegacyCopies,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

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

function Test-SamePath {
    param([string]$A, [string]$B)
    if ([string]::IsNullOrWhiteSpace($A) -or [string]::IsNullOrWhiteSpace($B)) { return $false }
    try {
        $a = [IO.Path]::GetFullPath($A).TrimEnd('\', '/')
        $b = [IO.Path]::GetFullPath($B).TrimEnd('\', '/')
        return [string]::Equals($a, $b, [StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}


Write-Step " cline-toolkit installer"
Write-Host "     repo:      $repoRoot"
Write-Host "     home:      $HOME"
Write-Host "     cline dir: $(Get-ClineDirPath)"
Write-Host ""

# 1. Проверка исходников
$src = @{
    rules     = Join-Path $repoRoot 'rules'
    workflows = Join-Path $repoRoot 'workflows'
    skills    = Join-Path $repoRoot 'skills'
    mcpFile   = Join-Path $repoRoot 'mcp\cline_mcp_settings.json'
}
foreach ($k in @('rules','workflows','skills','mcpFile')) {
    if (-not (Test-Path -LiteralPath $src[$k])) { throw "Не найден источник '$k': $($src[$k])" }
}

# 2. Целевые каталоги
$cline     = Get-ClineDirPath
$documents = if (-not [string]::IsNullOrWhiteSpace($DocumentsDir)) { $DocumentsDir } else { Get-DocumentsDir }
$clineDocs = Join-Path $documents 'Cline'

$rulesTarget     = if (-not [string]::IsNullOrWhiteSpace($RulesDir))     { $RulesDir }     else { Join-Path $clineDocs 'Rules' }
$workflowsTarget = if (-not [string]::IsNullOrWhiteSpace($WorkflowsDir)) { $WorkflowsDir } else { Join-Path $clineDocs 'Workflows' }
$skillsTarget    = if (-not [string]::IsNullOrWhiteSpace($SkillsDir))    { $SkillsDir }    else { Join-Path $cline 'skills' }
$mcpTarget       = if (-not [string]::IsNullOrWhiteSpace($McpFile))      { $McpFile }      else { Join-Path $cline 'data\settings\cline_mcp_settings.json' }

# Устаревшие (нечитаемые Cline 4.1.x) места, куда ставили прежние версии установщика
$legacyRulesDir     = $cline
$legacyWorkflowsDir = Join-Path $cline 'workflows'

Write-Step "Целевые расположения:"
Write-Host ("     rules     -> {0}" -f $rulesTarget)
Write-Host ("     workflows -> {0}" -f $workflowsTarget)
Write-Host ("     skills    -> {0}" -f $skillsTarget)
Write-Host ("     mcp       -> {0}" -f $mcpTarget)
Write-Host ""

if (-not $DryRun) {
    foreach ($d in @($rulesTarget, $workflowsTarget, $skillsTarget, (Split-Path -Parent $mcpTarget))) {
        if (-not [string]::IsNullOrWhiteSpace($d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    }
}

function Remove-LegacyCopy {
    param([string]$Path, [string]$SourceHash, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $h = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($h -ne $SourceHash) {
        Write-Info ("оставлен (изменён вручную, не трогаю): {0}" -f $Path)
        return
    }
    if (-not $DryRun) { Remove-Item -LiteralPath $Path -Force }
    if ($DryRun) {
        Write-Info ("будет удалена устаревшая копия ({0}): {1}" -f $Label, $Path)
    } else {
        Write-Ok ("устаревшая копия удалена ({0}): {1}" -f $Label, $Path)
    }
}

# 3. rules/*.md -> <Documents>\Cline\Rules
$rulesCount = 0
Get-ChildItem -Path $src['rules'] -Filter '*.md' -File | ForEach-Object {
    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    if (-not $DryRun) {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $rulesTarget $_.Name) -Force
    }
    $rulesCount++
    if (-not $KeepLegacyCopies -and -not (Test-SamePath $legacyRulesDir $rulesTarget)) {
        Remove-LegacyCopy -Path (Join-Path $legacyRulesDir $_.Name) -SourceHash $hash -Label 'rules (плоско в ~/.cline)'
    }
}
Write-Ok ("rules: {0} файлов -> {1}{2}" -f $rulesCount, $rulesTarget, $(if ($DryRun) { ' (dry-run)' } else { '' }))

# 4. workflows/*.md -> <Documents>\Cline\Workflows
$wfCount = 0
Get-ChildItem -Path $src['workflows'] -Filter '*.md' -File | ForEach-Object {
    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    if (-not $DryRun) {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $workflowsTarget $_.Name) -Force
    }
    $wfCount++
    if (-not $KeepLegacyCopies -and -not (Test-SamePath $legacyWorkflowsDir $workflowsTarget)) {
        Remove-LegacyCopy -Path (Join-Path $legacyWorkflowsDir $_.Name) -SourceHash $hash -Label 'workflows (~/.cline/workflows)'
    }
}
Write-Ok ("workflows: {0} файлов -> {1}{2}" -f $wfCount, $workflowsTarget, $(if ($DryRun) { ' (dry-run)' } else { '' }))

# 4a. Убрать пустой устаревший каталог ~/.cline/workflows
if (-not $KeepLegacyCopies -and -not (Test-SamePath $legacyWorkflowsDir $workflowsTarget) -and (Test-Path -LiteralPath $legacyWorkflowsDir)) {
    $rest = @(Get-ChildItem -LiteralPath $legacyWorkflowsDir -Force -ErrorAction SilentlyContinue)
    if ($rest.Count -eq 0) {
        if (-not $DryRun) { Remove-Item -LiteralPath $legacyWorkflowsDir -Force }
        if ($DryRun) {
            Write-Info ("пустой устаревший каталог будет удалён: {0}" -f $legacyWorkflowsDir)
        } else {
            Write-Ok ("пустой устаревший каталог удалён: {0}" -f $legacyWorkflowsDir)
        }
    } else {
        Write-Info ("в {0} остались посторонние файлы — каталог оставлен" -f $legacyWorkflowsDir)
    }
}

# 5. skills/* -> <ClineDir>\skills (рекурсивно, ничего не удаляя)
if (-not $DryRun) {
    Copy-Item -Path (Join-Path $src['skills'] '*') -Destination $skillsTarget -Recurse -Force
}
$skillsCount = @(Get-ChildItem -Path $src['skills'] -Directory).Count
$skillFiles  = @(Get-ChildItem -Path $src['skills'] -Recurse -File).Count
Write-Ok ("skills: {0} папок / {1} файлов -> {2}{3}" -f $skillsCount, $skillFiles, $skillsTarget, $(if ($DryRun) { ' (dry-run)' } else { '' }))

# 6. MCP: сохранить существующий рабочий ключ Tavily
$existingKey = $null
if (Test-Path -LiteralPath $mcpTarget) {
    try {
        $old = Get-Content -LiteralPath $mcpTarget -Raw | ConvertFrom-Json
        $url = $old.mcpServers.tavily.url
        if ($url -and $url -match 'tavilyApiKey=([^&"]+)') {
            $candidate = $Matches[1].Trim()
            if ($candidate -and $candidate -ne 'YOUR_TAVILY_API_KEY') { $existingKey = $candidate }
        }
    } catch {
        Write-Info "старый MCP-конфиг не распарсен — беру шаблон"
    }
}

$mcpRaw = [IO.File]::ReadAllText($src['mcpFile'])
if ($existingKey) { $mcpRaw = $mcpRaw -replace 'YOUR_TAVILY_API_KEY', $existingKey }

if (-not $DryRun) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($mcpTarget, $mcpRaw, $utf8NoBom)

    $bytes = [IO.File]::ReadAllBytes($mcpTarget)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    if ($hasBom) { throw "MCP JSON записан с BOM: $mcpTarget" }
    [IO.File]::ReadAllText($mcpTarget) | ConvertFrom-Json | Out-Null
}

if ($existingKey) {
    Write-Ok "mcp: существующий ключ Tavily сохранён"
    $keyNeeded = $false
} else {
    Write-Ok "mcp: установлен из шаблона (ключ Tavily — плейсхолдер)"
    $keyNeeded = $true
}

# 7. Итоговый отчёт
Write-Host ""
if ($DryRun) {
    Write-Step "Проверка завершена (dry-run, файлы не записаны)"
} else {
    Write-Step "Установка завершена"
    $installed = 0
    $installed += @(Get-ChildItem -Path $rulesTarget -File -Filter '*.md' -ErrorAction SilentlyContinue).Count
    $installed += @(Get-ChildItem -Path $workflowsTarget -File -Filter '*.md' -ErrorAction SilentlyContinue).Count
    $installed += @(Get-ChildItem -Path $skillsTarget -Recurse -File -Filter 'SKILL.md' -ErrorAction SilentlyContinue).Count
    Write-Host "     Файлов правил/воркфлоу/SKILL.md в целевых каталогах: $installed"
    Write-Host "     Cline 4.1.x читает: Rules/Workflows из $clineDocs, навыки из $skillsTarget"
}
if ($keyNeeded) {
    Write-Warn2 "укажите ключ Tavily в $mcpTarget (вместо YOUR_TAVILY_API_KEY)"
}
Write-Host "     Перезапустите Cline, чтобы он подхватил изменения." -ForegroundColor Cyan
