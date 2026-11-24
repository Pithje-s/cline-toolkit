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

$script:failCount = 0
$script:warnCount = 0
function Ok($m)   { Write-Host "  [OK]   $m" }
function Bad($m)  { Write-Host "  [FAIL] $m"; $script:failCount++ }
function Warn($m) { Write-Host "  [WARN] $m"; $script:warnCount++ }

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
Write-Host "[1/8] rules/" -ForegroundColor Cyan
foreach ($r in '01-core.md','02-quality-git.md','03-workflow-search.md') {
    $p = Join-Path $RepoRoot "rules\$r"
    if (Test-Path $p) { Ok "rules/$r" } else { Bad "rules/$r отсутствует" }
}

# 2. skills frontmatter
Write-Host "[2/8] skills/" -ForegroundColor Cyan
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
Write-Host "[3/8] workflows/" -ForegroundColor Cyan
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
Write-Host "[4/8] mcp/ + секреты" -ForegroundColor Cyan
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
Write-Host "[5/8] CJK-проверка .md" -ForegroundColor Cyan
$mdFiles = $allFiles | Where-Object { $_.Extension -eq '.md' }
$cjk = $mdFiles | Select-String -Pattern '[\u4e00-\u9fff\u3040-\u30ff]' -AllMatches -ErrorAction SilentlyContinue
if ($cjk) { $cjk | ForEach-Object { Bad "CJK в $($_.Filename):$($_.LineNumber)" } }
else { Ok "иероглифов нет" }

# 6. Конфиг + дубли/противоречия
Write-Host "[6/8] config + дубли/противоречия" -ForegroundColor Cyan

$cfg = Join-Path $RepoRoot 'config.example.json'
if (Test-Path $cfg) {
    try { Get-Content $cfg -Raw | ConvertFrom-Json | Out-Null; Ok "config.example.json валиден" }
    catch { Bad "config.example.json невалиден: $($_.Exception.Message)" }
} else { Bad "config.example.json отсутствует" }

$ruleFiles  = Get-ChildItem -Path (Join-Path $RepoRoot 'rules') -Filter '*.md' -File -ErrorAction SilentlyContinue
$skillFiles = Get-ChildItem -Path (Join-Path $RepoRoot 'skills') -Recurse -File -Filter 'SKILL.md' -ErrorAction SilentlyContinue
$textFiles  = @($ruleFiles) + @($skillFiles)

# 6a. Дубли заголовков ### между файлами
$headings = @{}
foreach ($f in $textFiles) {
    Get-Content -Path $f.FullName | ForEach-Object {
        if ($_ -match '^###\s+(.+?)\s*$') {
            $h = $Matches[1].Trim()
            if ($headings.ContainsKey($h)) { Bad "дубль заголовка '### $h' ($($f.Name) / $($headings[$h]))" }
            else { $headings[$h] = $f.Name }
        }
    }
}
Ok "заголовки проверены ($($headings.Count) уникальных)"

# 6b. Дубли строк (>40 симв.) между файлами правил/навыков
$seen = @{}
$dupFound = $false
foreach ($f in $textFiles) {
    Get-Content -Path $f.FullName | ForEach-Object {
        $line = $_.Trim()
        if ($line.Length -gt 40 -and $line -notmatch '^#' -and $line -notmatch '^\[.*\]\(') {
            if ($seen.ContainsKey($line) -and $seen[$line] -ne $f.Name) {
                Bad "дубль строки '...$($line.Substring(0,[Math]::Min(40,$line.Length)))...' ($($f.Name) / $($seen[$line]))"
                $dupFound = $true
            } elseif (-not $seen.ContainsKey($line)) {
                $seen[$line] = $f.Name
            }
        }
    }
}
if (-not $dupFound) { Ok "дублирующихся строк нет" }

# 6c. Противоречия (эвристика, WARN): один и тот же термин запрещён в одном месте и разрешён в другом
$stop = @('только','также','тогда','после','перед','между','чтобы','который','можно','нельзя','запрещено','разрешено','разреш','должен','должна','должны','будет','может','нужно','также','через','если','либо','свой','свои')
$prohibit = @{}; $allowT = @{}
foreach ($f in $textFiles) {
    Get-Content -Path $f.FullName | ForEach-Object {
        $line = $_
        $tokens = ([regex]::Matches($line.ToLower(), '[а-яё]{5,}') | ForEach-Object { $_.Value }) | Where-Object { $stop -notcontains $_ } | Select-Object -Unique
        if ($line -match 'ЗАПРЕЩЕНО|запрещ|нельзя|не разреш') {
            foreach ($t in $tokens) { $prohibit[$t] = $true }
        }
        if ($line -match 'разрешено|разреш\b|\bможно\b') {
            foreach ($t in $tokens) { $allowT[$t] = $true }
        }
    }
}
$conflicts = @()
foreach ($t in $prohibit.Keys) { if ($allowT.ContainsKey($t)) { $conflicts += $t } }
if ($conflicts.Count -gt 0) {
    $conflicts | Select-Object -First 12 | ForEach-Object { Warn "возможное противоречие по термину '$_' (запрещено в одном месте, разрешено в другом) — проверьте вручную" }
} else { Ok "явных противоречий не найдено" }

# 7. Обязательные файлы поставки
Write-Host "[7/8] файлы поставки" -ForegroundColor Cyan
foreach ($f in @('install.ps1', 'uninstall.ps1', 'tests\Install.Tests.ps1', 'tests\run-tests.ps1',
        'tests\Eval.Tests.ps1', 'eval\run-eval.ps1', 'eval\measure-context.ps1',
        'eval\lib\Metrics.psm1', 'EVAL.md')) {
    if (Test-Path (Join-Path $RepoRoot $f)) { Ok $f } else { Bad "$f отсутствует" }
}

# 8. Устаревшие директивы: регресс-гард на конструкции, которых нет в Cline.
# Сканируются только правила/навыки/воркфлоу — в CHANGELOG эти строки упоминаются законно.
Write-Host "[8/8] устаревшие директивы" -ForegroundColor Cyan
$stalePatterns = @('-glo' + 'bals:', 'update_' + 'memory_bank')
$scanFiles = @()
$scanFiles += @(Get-ChildItem -Path (Join-Path $RepoRoot 'rules') -Filter '*.md' -File -ErrorAction SilentlyContinue)
$scanFiles += @(Get-ChildItem -Path (Join-Path $RepoRoot 'workflows') -Filter '*.md' -File -ErrorAction SilentlyContinue)
$scanFiles += @(Get-ChildItem -Path (Join-Path $RepoRoot 'skills') -Recurse -File -Filter 'SKILL.md' -ErrorAction SilentlyContinue)
$staleHits = 0
foreach ($pattern in $stalePatterns) {
    $found = @($scanFiles | Select-String -Pattern ([regex]::Escape($pattern)) -ErrorAction SilentlyContinue)
    foreach ($hit in $found) {
        Bad "устаревшая ссылка '$pattern' в $($hit.Filename):$($hit.LineNumber)"
        $staleHits++
    }
}
if ($staleHits -eq 0) { Ok "устаревших директив нет ($(@($scanFiles).Count) файлов проверено)" }

Write-Host ""
if ($script:failCount -eq 0 -and $script:warnCount -eq 0) {
    Write-Host "RESULT: PASS" -ForegroundColor Green
    exit 0
} elseif ($script:failCount -eq 0) {
    Write-Host "RESULT: PASS (с $($script:warnCount) предупреждениями)" -ForegroundColor Yellow
    exit 0
} else {
    Write-Host "RESULT: FAIL ($($script:failCount) проблем, $($script:warnCount) предупреждений)" -ForegroundColor Red
    exit 1
}