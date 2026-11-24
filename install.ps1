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
    [string]$ClineDir
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$home86  = $HOME
if ([string]::IsNullOrWhiteSpace($ClineDir)) {
    $ClineDir = Join-Path $home86 '.cline'
}

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

# 2. Создание целевых папок
$dst = @{
    root       = $clineDir
    workflows  = Join-Path $clineDir 'workflows'
    skills     = Join-Path $clineDir 'skills'
    settings   = Join-Path $clineDir 'data\settings'
}
foreach ($d in $dst.Values) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}
Write-Ok "Папки Cline готовы: $($dst.root)"

# 3. rules/*.md
$rulesCount = 0
Get-ChildItem -Path $src['rules'] -Filter '*.md' -File | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $dst['root'] -Force
    $rulesCount++
}
Write-Ok "Скопировано rules: $rulesCount"

# 4. workflows/*.md
$wfCount = 0
Get-ChildItem -Path $src['workflows'] -Filter '*.md' -File | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $dst['workflows'] -Force
    $wfCount++
}
Write-Ok "Скопировано workflows: $wfCount"

# 5. skills/* (рекурсивно)
Copy-Item -Path (Join-Path $src['skills'] '*') -Destination $dst['skills'] -Recurse -Force
$skillsCount = (Get-ChildItem -Path $src['skills'] -Directory).Count
Write-Ok "Скопировано skills (папок): $skillsCount"

# 6. MCP: сохранить существующий ключ Tavily
$targetMcp = Join-Path $dst['settings'] 'cline_mcp_settings.json'
$existingKey = $null
if (Test-Path $targetMcp) {
    try {
        $old = Get-Content -Path $targetMcp -Raw | ConvertFrom-Json
        $candidate = $old.mcpServers.tavily.url
        if ($candidate -and $candidate -match 'tavilyApiKey=([^&]+)') {
            $k = $Matches[1]
            if ($k -and $k -ne 'YOUR_TAVILY_API_KEY') { $existingKey = $k }
        }
    } catch { Write-Host "    [i] Старый MCP-конфиг не распарсен, беру шаблон" }
}

Copy-Item -Path $src['mcpFile'] -Destination $targetMcp -Force
if ($existingKey) {
    $raw = Get-Content -Path $targetMcp -Raw
    $raw = $raw -replace 'YOUR_TAVILY_API_KEY', $existingKey
    Set-Content -Path $targetMcp -Value $raw -Encoding UTF8 -NoNewline
    Write-Ok "MCP обновлён, СУЩЕСТВУЮЩИЙ ключ Tavily сохранён"
    $keyNeeded = $false
} else {
    Write-Ok "MCP установлен из шаблона (ключ Tavily — плейсхолдер)"
    $keyNeeded = $true
}

# 7. Итоговый отчёт
Write-Host ""
Write-Step "Установка завершена"
$installed = (Get-ChildItem -Path $dst['root'] -File -Filter '*.md').Count `
           + (Get-ChildItem -Path $dst['workflows'] -File -Filter '*.md').Count `
           + (Get-ChildItem -Path $dst['skills'] -Recurse -File -Filter 'SKILL.md').Count
Write-Host "     Всего файлов правил/воркфлоу/скиллов: $installed"
if ($keyNeeded) {
    Write-Host "     ВНИМАНИЕ: укажите ключ Tavily в $targetMcp" -ForegroundColor Yellow
}
Write-Host "     Перезапустите Cline, чтобы он подхватил изменения." -ForegroundColor Cyan