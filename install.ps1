<#
.SYNOPSIS
    Установка cline-toolkit в глобальные каталоги Cline.
.DESCRIPTION
    Раскладывает rules/, workflows/, skills/ и mcp/ по глобальным папкам Cline
    (~/.cline). Сохраняет существующий рабочий ключ Tavily из старого конфига,
    не удаляет постороннее содержимое и не трогает секреты.
.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\install.ps1
.PARAMETER ClineDir
    Целевой каталог .cline. По умолчанию — $HOME\.cline. Параметр для
    тестирования и нестандартных расположений.
#>
param(
    [string]$ClineDir,
    [string]$RulesDir,
    [string]$WorkflowsDir,
    [string]$SkillsDir,
    [string]$McpFile,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$home86  = $HOME

function Write-Step($msg) { Write-Host "==> $msg" }
function Write-Ok($msg)   { Write-Host "    [OK] $msg" }

Write-Step " cline-toolkit installer"
Write-Host "     repo:  $repoRoot"
Write-Host "     home:  $home86"
Write-Host ""

# 1. Проверка исходных папок
$src = @{
    rules     = Join-Path $repoRoot 'rules'
    workflows = Join-Path $repoRoot 'workflows'
    skills    = Join-Path $repoRoot 'skills'
    mcpFile   = Join-Path $repoRoot 'mcp\cline_mcp_settings.json'
}
foreach ($k in $src.Keys) {
    if (-not (Test-Path $src[$k])) { throw "Не найден источник '$k': $($src[$k])" }
}

# 2. Определение целевых расположений (автодетект)
$sigMd = { param($p) (Get-ChildItem -Path $p -Filter '*.md' -File -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0 }
$sigSkills = { param($p) (Get-ChildItem -Path $p -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') } | Measure-Object).Count -gt 0 }

function Resolve-Target {
    param([string]$Override,[string[]]$Candidates,[scriptblock]$HasSig,[string]$DefaultNew,[string]$Label)
    if ($Override) { return [pscustomobject]@{ Path=$Override; Reason='задан явно (override)' } }
    $best = $null; $bestScore = -1; $bestHas = $false
    foreach ($c in $Candidates) {
        if (-not (Test-Path $c)) { continue }
        $has = & $HasSig $c
        $score = 10
        if ($has) { $score += 100 }
        if ($score -gt $bestScore) { $bestScore = $score; $best = $c; $bestHas = $has }
    }
    if ($null -eq $best) {
        return [pscustomobject]@{ Path=$DefaultNew; Reason='нет существующих папок — создаю по умолчанию' }
    }
    if ($bestHas) { $reason = "существующая папка с файлами $Label" }
    else { $reason = "существующая папка (пока без файлов $Label)" }
    return [pscustomobject]@{ Path=$best; Reason=$reason }
}

if (-not [string]::IsNullOrWhiteSpace($ClineDir)) {
    $rRules = [pscustomobject]@{ Path=$ClineDir; Reason='ClineDir задан явно' }
    $rWf    = [pscustomobject]@{ Path=(Join-Path $ClineDir 'workflows'); Reason='ClineDir задан явно' }
    $rSk    = [pscustomobject]@{ Path=(Join-Path $ClineDir 'skills'); Reason='ClineDir задан явно' }
    $mcpTarget = Join-Path $ClineDir 'data\settings\cline_mcp_settings.json'
} else {
    $rRules = Resolve-Target -Override $RulesDir -Candidates @(
        (Join-Path $home86 '.clinerules\Rules'),
        (Join-Path $home86 'Documents\Cline\Rules'),
        (Join-Path $home86 '.cline\rules')
    ) -HasSig $sigMd -DefaultNew (Join-Path $home86 '.clinerules\Rules') -Label 'rules'

    $rWf = Resolve-Target -Override $WorkflowsDir -Candidates @(
        (Join-Path $home86 '.clinerules\workflows'),
        (Join-Path $home86 '.cline\workflows'),
        (Join-Path $home86 'Documents\Cline\Workflows')
    ) -HasSig $sigMd -DefaultNew (Join-Path $home86 '.clinerules\workflows') -Label 'workflows'

    $rSk = Resolve-Target -Override $SkillsDir -Candidates @(
        (Join-Path $home86 '.cline\skills'),
        (Join-Path $home86 '.clinerules\skills')
    ) -HasSig $sigSkills -DefaultNew (Join-Path $home86 '.cline\skills') -Label 'skills'

    if ($McpFile) { $mcpTarget = $McpFile }
    else { $mcpTarget = Join-Path $home86 '.cline\data\settings\cline_mcp_settings.json' }
}

Write-Host ""
Write-Step "Обнаруженные расположения:"
Write-Host ("     rules     -> {0}  [{1}]" -f $rRules.Path, $rRules.Reason)
Write-Host ("     workflows -> {0}  [{1}]" -f $rWf.Path, $rWf.Reason)
Write-Host ("     skills    -> {0}  [{1}]" -f $rSk.Path, $rSk.Reason)
Write-Host ("     mcp       -> {0}" -f $mcpTarget)
Write-Host ""

# Создание целевых папок (кроме dry-run)
if (-not $DryRun) {
    foreach ($d in @($rRules.Path, $rWf.Path, $rSk.Path, (Split-Path -Parent $mcpTarget))) {
        if (-not [string]::IsNullOrWhiteSpace($d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    }
}

# 3. rules/*.md
$rulesCount = 0
Get-ChildItem -Path $src['rules'] -Filter '*.md' -File | ForEach-Object {
    if (-not $DryRun) { Copy-Item -Path $_.FullName -Destination $rRules.Path -Force }
    $rulesCount++
}
Write-Ok ("rules: {0} -> {1}{2}" -f $rulesCount, $rRules.Path, $(if ($DryRun) { ' (dry-run)' } else { '' }))

# 4. workflows/*.md
$wfCount = 0
Get-ChildItem -Path $src['workflows'] -Filter '*.md' -File | ForEach-Object {
    if (-not $DryRun) { Copy-Item -Path $_.FullName -Destination $rWf.Path -Force }
    $wfCount++
}
Write-Ok ("workflows: {0} -> {1}{2}" -f $wfCount, $rWf.Path, $(if ($DryRun) { ' (dry-run)' } else { '' }))

# 5. skills/* (рекурсивно)
if (-not $DryRun) {
    Copy-Item -Path (Join-Path $src['skills'] '*') -Destination $rSk.Path -Recurse -Force
}
$skillsCount = (Get-ChildItem -Path $src['skills'] -Directory).Count
Write-Ok ("skills: {0} папок -> {1}{2}" -f $skillsCount, $rSk.Path, $(if ($DryRun) { ' (dry-run)' } else { '' }))

# 6. MCP: сохранить существующий ключ Tavily
$existingKey = $null
if (Test-Path $mcpTarget) {
    try {
        $old = Get-Content -Path $mcpTarget -Raw | ConvertFrom-Json
        $candidate = $old.mcpServers.tavily.url
        if ($candidate -and $candidate -match 'tavilyApiKey=([^&]+)') {
            $k = $Matches[1]
            if ($k -and $k -ne 'YOUR_TAVILY_API_KEY') { $existingKey = $k }
        }
    } catch { Write-Host "    [i] Старый MCP-конфиг не распарсен, беру шаблон" }
}

if (-not $DryRun) {
    Copy-Item -Path $src['mcpFile'] -Destination $mcpTarget -Force
    if ($existingKey) {
        $raw = Get-Content -Path $mcpTarget -Raw
        $raw = $raw -replace 'YOUR_TAVILY_API_KEY', $existingKey
        Set-Content -Path $mcpTarget -Value $raw -Encoding UTF8 -NoNewline
        Write-Ok "MCP обновлён, СУЩЕСТВУЮЩИЙ ключ Tavily сохранён"
        $keyNeeded = $false
    } else {
        Write-Ok "MCP установлен из шаблона (ключ Tavily — плейсхолдер)"
        $keyNeeded = $true
    }
} else {
    $keyNeeded = (-not $existingKey)
    Write-Ok ("mcp -> {0} (dry-run)" -f $mcpTarget)
}

# 7. Итоговый отчёт
Write-Host ""
if ($DryRun) {
    Write-Step "Проверка завершена (dry-run, файлы не записаны)"
    Write-Host ("     Будет скопировано: rules {0}, workflows {1}, skills {2} папок" -f $rulesCount, $wfCount, $skillsCount)
} else {
    Write-Step "Установка завершена"
    $installed = (Get-ChildItem -Path $rRules.Path -File -Filter '*.md' -ErrorAction SilentlyContinue | Measure-Object).Count `
               + (Get-ChildItem -Path $rWf.Path -File -Filter '*.md' -ErrorAction SilentlyContinue | Measure-Object).Count `
               + (Get-ChildItem -Path $rSk.Path -Recurse -File -Filter 'SKILL.md' -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-Host "     Всего файлов правил/воркфлоу/скиллов: $installed"
}
if ($keyNeeded) {
    Write-Host "     ВНИМАНИЕ: укажите ключ Tavily в $mcpTarget" -ForegroundColor Yellow
}
Write-Host "     Перезапустите Cline, чтобы он подхватил изменения." -ForegroundColor Cyan