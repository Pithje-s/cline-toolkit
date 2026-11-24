<#
.SYNOPSIS
    Валидация репозитория cline-toolkit (frontmatter, JSON, секреты, CJK).
.DESCRIPTION
    Проверяет инженерную целостность набора: наличие и корректность frontmatter
    у skills/workflows, валидность MCP JSON, отсутствие реальных секретов и
    иероглифов. Завершается кодом 0 (PASS) или 1 (FAIL).
.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\validate.ps1
#>
param(
    [string]$RepoRoot = (Split-Path -Parent $MyInvocation.MyCommand.Path)
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$fail = 0
$script:failCount = 0
function Ok($m)   { Write-Host "  [OK]   $m" }
function Bad($m)  { Write-Host "  [FAIL] $m"; $script:failCount++ }

function Get-Frontmatter($path) {
    $lines = Get-Content -Path $path -ErrorAction Stop
    if ($lines.Count -lt 1 -or $lines[0].Trim() -ne '---') { return $null }
    $end = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') { $end = $i; break }
    }
    if ($end -lt 1) { return $null }
    return ($lines[1..($end - 1)] -join "`n")
}

Write-Host "== validate.ps1: $RepoRoot ==" -ForegroundColor Cyan

# 1. rules
Write-Host "[1/5] rules/" -ForegroundColor Cyan
foreach ($r in '01-core.md','02-quality-git.md','03-workflow-search.md') {
    $p = Join-Path $RepoRoot "rules\$r"
    if (Test-Path $p) { Ok "rules/$r" } else { Bad "rules/$r отсутствует" }
}

# 2. skills frontmatter
Write-Host "[2/5] skills/" -ForegroundColor Cyan
$skillsDir = Join-Path $RepoRoot 'skills'
if (-not (Test-Path $skillsDir)) { Bad "skills/ отсутствует" }
else {
    Get-ChildItem -Path $skillsDir -Directory | ForEach-Object {
        $skillMd = Join-Path $_.FullName 'SKILL.md'
        if (-not (Test-Path $skillMd)) { Bad "$($_.Name): нет SKILL.md"; return }
        $fm = Get-Frontmatter $skillMd
        if ($null -eq $fm) { Bad "$($_.Name): нет/битый frontmatter ---"; return }
        if ($fm -notmatch '(?m)^name:')       { Bad "$($_.Name): нет 'name:'"; return }
        if ($fm -notmatch '(?m)^description:') { Bad "$($_.Name): нет 'description:'"; return }
        Ok "$($_.Name)/SKILL.md"
    }
}

# 3. workflows frontmatter
Write-Host "[3/5] workflows/" -ForegroundColor Cyan
$wfDir = Join-Path $RepoRoot 'workflows'
if (-not (Test-Path $wfDir)) { Bad "workflows/ отсутствует" }
else {
    Get-ChildItem -Path $wfDir -Filter '*.md' -File | ForEach-Object {
        $fm = Get-Frontmatter $_.FullName
        if ($null -eq $fm) { Bad "workflows/$($_.Name): нет/битый frontmatter ---"; return }
        if ($fm -notmatch '(?m)^description:') { Bad "workflows/$($_.Name): нет 'description:'"; return }
        Ok "workflows/$($_.Name)"
    }
}

# 4. MCP JSON + секреты
Write-Host "[4/5] mcp/ + секреты" -ForegroundColor Cyan
$mcp = Join-Path $RepoRoot 'mcp\cline_mcp_settings.json'
if (-not (Test-Path $mcp)) { Bad "mcp/cline_mcp_settings.json отсутствует" }
else {
    try { Get-Content $mcp -Raw | ConvertFrom-Json | Out-Null; Ok "mcp JSON валиден" }
    catch { Bad "mcp JSON невалиден: $($_.Exception.Message)" }
}

# Реальные ключи (tvly- кроме плейсхолдера) по всему репозиторию
$allFiles = Get-ChildItem -Path $RepoRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.Name -notlike '_*' }
$realLeak = $allFiles | Select-String -Pattern 'tvly-[A-Za-z0-9]' -AllMatches -ErrorAction SilentlyContinue |
    Where-Object { $_.Line -notmatch 'YOUR_TAVILY_API_KEY' }
if ($realLeak) { $realLeak | ForEach-Object { Bad "возможный секрет: $($_.Filename):$($_.LineNumber)" } }
else { Ok "реальных ключей tvly- не найдено" }

# 5. CJK-иероглифы в .md
Write-Host "[5/5] CJK-проверка .md" -ForegroundColor Cyan
$mdFiles = $allFiles | Where-Object { $_.Extension -eq '.md' }
$cjk = $mdFiles | Select-String -Pattern '[\u4e00-\u9fff\u3040-\u30ff]' -AllMatches -ErrorAction SilentlyContinue
if ($cjk) { $cjk | ForEach-Object { Bad "CJK в $($_.Filename):$($_.LineNumber)" } }
else { Ok "иероглифов нет" }

Write-Host ""
if ($script:failCount -eq 0) {
    Write-Host "RESULT: PASS" -ForegroundColor Green
    exit 0
} else {
    Write-Host "RESULT: FAIL ($($script:failCount) проблем)" -ForegroundColor Red
    exit 1
}