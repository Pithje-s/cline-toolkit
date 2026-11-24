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

    MCP-конфиг НЕ перезаписывается: шаблон сливается с существующим файлом.
    Серверы, которые уже настроены у пользователя (ключи, autoApprove, disabled,
    URL), сохраняются как есть; из шаблона добавляются только отсутствующие.
    Перед записью создаётся бэкап cline_mcp_settings.json.bak-<timestamp>, а после
    записи каждый сохранённый сервер сверяется с исходным — при расхождении
    файл восстанавливается из бэкапа и установка останавливается.

    Каждая установка пишет манифест (.cline-toolkit-manifest.json) со списком
    путей и их SHA256. Файлы прошлой установки, которых больше нет в репозитории,
    удаляются только при совпадении хеша; изменённые вручную остаются и
    перечисляются в отчёте. Обратная операция — uninstall.ps1.

    Скрипт не трогает посторонние файлы, пишет JSON без BOM и (если не указан
    -KeepLegacyCopies) убирает устаревшие копии, оставшиеся от прежних версий
    установщика — только те, что побайтово совпадают с файлами репозитория.
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
.PARAMETER ManifestFile
    Override пути манифеста установки (по умолчанию <ClineDir>\.cline-toolkit-manifest.json).
.PARAMETER ForceMcpTemplate
    Если существующий MCP-конфиг не парсится как JSON — заменить его шаблоном
    (бэкап всё равно создаётся). По умолчанию установка останавливается, чтобы
    не потерять рабочий конфиг.
.PARAMETER NoPrune
    Не удалять файлы прошлой установки, которых больше нет в репозитории.
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
    [string]$ManifestFile,
    [switch]$KeepLegacyCopies,
    [switch]$ForceMcpTemplate,
    [switch]$NoPrune,
    [switch]$DryRun
)

$toolkitVersion = '0.5.1'

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
$manifestPath    = if (-not [string]::IsNullOrWhiteSpace($ManifestFile)) { $ManifestFile } else { Join-Path $cline '.cline-toolkit-manifest.json' }

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

$script:installedFiles = New-Object System.Collections.Generic.List[object]

function Copy-TrackedFile {
    param([string]$Source, [string]$Destination, [string]$Kind)
    $hash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
    if (-not $DryRun) {
        $dir = Split-Path -Parent $Destination
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
    $script:installedFiles.Add([pscustomobject]@{ path = $Destination; sha256 = $hash; kind = $Kind })
}

function Read-Manifest {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) }
    catch {
        Write-Warn2 ("манифест не читается, устаревшие файлы не удаляются: {0}" -f $Path)
        return $null
    }
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

# Удаляет только файлы прошлой установки, которых нет в новой, и только если они
# не правились вручную (хеш совпадает с манифестом). Посторонние файлы не трогает.
function Invoke-Prune {
    param($Manifest, [string[]]$NewPaths, [string[]]$Roots)
    if ($null -eq $Manifest -or $null -eq $Manifest.files) { return 0 }
    $newSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $NewPaths) { [void]$newSet.Add([IO.Path]::GetFullPath($p)) }
    $removed = 0
    foreach ($entry in @($Manifest.files)) {
        if ([string]::IsNullOrWhiteSpace($entry.path)) { continue }
        if (-not (Test-PathInsideTargets -Child $entry.path -Roots $Roots)) {
            Write-Warn2 ("пропущен путь вне целевых каталогов: {0}" -f $entry.path)
            continue
        }
        try { $alreadyInstalled = $newSet.Contains([IO.Path]::GetFullPath($entry.path)) } catch { $alreadyInstalled = $false }
        if ($alreadyInstalled) { continue }
        if (-not (Test-Path -LiteralPath $entry.path)) { continue }
        $current = (Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash
        if ($entry.sha256 -and $current -ne $entry.sha256) {
            Write-Info ("оставлен (изменён вручную): {0}" -f $entry.path)
            continue
        }
        if ($DryRun) {
            Write-Info ("будет удалён устаревший файл ({0}): {1}" -f $entry.kind, $entry.path)
        } else {
            Remove-Item -LiteralPath $entry.path -Force
            Write-Ok ("удалён устаревший файл ({0}): {1}" -f $entry.kind, $entry.path)
        }
        $removed++
    }
    return $removed
}

# Убирает опустевшие каталоги навыков, чтобы переименованный навык не оставлял пустую папку
function Remove-EmptySkillDirs {
    param([string]$Root)
    if ($DryRun -or -not (Test-Path -LiteralPath $Root)) { return }
    $dirs = @(Get-ChildItem -LiteralPath $Root -Directory -Recurse -ErrorAction SilentlyContinue)
    foreach ($d in ($dirs | Sort-Object { $_.FullName.Length } -Descending)) {
        if (-not (Test-Path -LiteralPath $d.FullName)) { continue }
        if (@(Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0) {
            Remove-Item -LiteralPath $d.FullName -Force
        }
    }
}

# Шаблон — база (порядок серверов и новые заготовки), существующий конфиг перекрывает
# всё, что уже настроено. Ни один существующий сервер не удаляется и не изменяется.
function Merge-McpConfig {
    param($Template, $Existing)
    $servers = [ordered]@{}
    $added = New-Object System.Collections.Generic.List[string]
    $preserved = New-Object System.Collections.Generic.List[string]
    foreach ($name in @($Template.mcpServers.PSObject.Properties.Name)) { $servers[$name] = $Template.mcpServers.$name }
    if ($null -ne $Existing -and $null -ne $Existing.mcpServers) {
        foreach ($name in @($Existing.mcpServers.PSObject.Properties.Name)) {
            $servers[$name] = $Existing.mcpServers.$name
            $preserved.Add($name)
        }
    }
    foreach ($name in @($Template.mcpServers.PSObject.Properties.Name)) {
        if (-not $preserved.Contains($name)) { $added.Add($name) }
    }
    $result = [ordered]@{}
    if ($null -ne $Existing) {
        foreach ($p in $Existing.PSObject.Properties) {
            if ($p.Name -ne 'mcpServers') { $result[$p.Name] = $p.Value }
        }
    }
    $result['mcpServers'] = [pscustomobject]$servers
    return [pscustomobject]@{ Config = [pscustomobject]$result; Added = $added; Preserved = $preserved }
}

# 3. Сверка с прошлой установкой: убрать файлы, которых больше нет в репозитории
$newPaths = New-Object System.Collections.Generic.List[string]
foreach ($f in Get-ChildItem -Path $src['rules'] -Filter '*.md' -File) { $newPaths.Add((Join-Path $rulesTarget $f.Name)) }
foreach ($f in Get-ChildItem -Path $src['workflows'] -Filter '*.md' -File) { $newPaths.Add((Join-Path $workflowsTarget $f.Name)) }
$skillsRootFull = [IO.Path]::GetFullPath($src['skills']).TrimEnd('\', '/')
foreach ($f in Get-ChildItem -Path $src['skills'] -Recurse -File) {
    $rel = $f.FullName.Substring($skillsRootFull.Length).TrimStart('\', '/')
    $newPaths.Add((Join-Path $skillsTarget $rel))
}

if ($NoPrune) {
    Write-Info 'prune отключён (-NoPrune): файлы прошлой установки не удаляются'
} else {
    Write-Step 'Сверка с прошлой установкой (манифест)'
    $previous = Read-Manifest -Path $manifestPath
    if ($null -ne $previous -and $null -ne $previous.files) {
        $pruned = Invoke-Prune -Manifest $previous -NewPaths $newPaths -Roots @($rulesTarget, $workflowsTarget, $skillsTarget)
        Write-Ok ("prune: удалено {0} из {1} записей манифеста" -f $pruned, @($previous.files).Count)
    } else {
        Write-Info 'прошлый манифест не найден — удалять нечего'
    }
}

# 4. rules/*.md -> <Documents>\Cline\Rules
$rulesCount = 0
Get-ChildItem -Path $src['rules'] -Filter '*.md' -File | ForEach-Object {
    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    Copy-TrackedFile -Source $_.FullName -Destination (Join-Path $rulesTarget $_.Name) -Kind 'rules'
    $rulesCount++
    if (-not $KeepLegacyCopies -and -not (Test-SamePath $legacyRulesDir $rulesTarget)) {
        Remove-LegacyCopy -Path (Join-Path $legacyRulesDir $_.Name) -SourceHash $hash -Label 'rules (плоско в ~/.cline)'
    }
}
Write-Ok ("rules: {0} файлов -> {1}{2}" -f $rulesCount, $rulesTarget, $(if ($DryRun) { ' (dry-run)' } else { '' }))

# 5. workflows/*.md -> <Documents>\Cline\Workflows
$wfCount = 0
Get-ChildItem -Path $src['workflows'] -Filter '*.md' -File | ForEach-Object {
    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    Copy-TrackedFile -Source $_.FullName -Destination (Join-Path $workflowsTarget $_.Name) -Kind 'workflows'
    $wfCount++
    if (-not $KeepLegacyCopies -and -not (Test-SamePath $legacyWorkflowsDir $workflowsTarget)) {
        Remove-LegacyCopy -Path (Join-Path $legacyWorkflowsDir $_.Name) -SourceHash $hash -Label 'workflows (~/.cline/workflows)'
    }
}
Write-Ok ("workflows: {0} файлов -> {1}{2}" -f $wfCount, $workflowsTarget, $(if ($DryRun) { ' (dry-run)' } else { '' }))

# 5a. Убрать пустой устаревший каталог ~/.cline/workflows
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

# 6. skills/* -> <ClineDir>\skills (рекурсивно)
Get-ChildItem -Path $src['skills'] -Recurse -File | ForEach-Object {
    $rel  = $_.FullName.Substring($skillsRootFull.Length).TrimStart('\', '/')
    Copy-TrackedFile -Source $_.FullName -Destination (Join-Path $skillsTarget $rel) -Kind 'skills'
}
Remove-EmptySkillDirs -Root $skillsTarget
$skillsCount = @(Get-ChildItem -Path $src['skills'] -Directory).Count
$skillFiles  = @(Get-ChildItem -Path $src['skills'] -Recurse -File).Count
Write-Ok ("skills: {0} папок / {1} файлов -> {2}{3}" -f $skillsCount, $skillFiles, $skillsTarget, $(if ($DryRun) { ' (dry-run)' } else { '' }))

# 7. MCP: неразрушающий merge (шаблон как база, существующие серверы главнее) + бэкап
$existingMcp = $null
if (Test-Path -LiteralPath $mcpTarget) {
    $rawOld = [IO.File]::ReadAllText($mcpTarget)
    if ([string]::IsNullOrWhiteSpace($rawOld)) {
        Write-Info 'MCP-конфиг пуст — будет заполнен из шаблона'
    } else {
        try {
            $existingMcp = $rawOld | ConvertFrom-Json
        } catch {
            if (-not $ForceMcpTemplate) {
                throw ("существующий MCP-конфиг не парсится как JSON: {0}`nИсправьте файл вручную или запустите с -ForceMcpTemplate (бэкап будет создан)." -f $mcpTarget)
            }
            Write-Warn2 ("MCP-конфиг не парсится — заменяю шаблоном (бэкап сохраняется): {0}" -f $mcpTarget)
        }
    }
}

$templateMcp = [IO.File]::ReadAllText($src['mcpFile']) | ConvertFrom-Json
$merge       = Merge-McpConfig -Template $templateMcp -Existing $existingMcp
$mcpJson     = $merge.Config | ConvertTo-Json -Depth 20
$tavilyUrl   = $merge.Config.mcpServers.tavily.url
$keyNeeded   = [string]::IsNullOrWhiteSpace($tavilyUrl) -or ($tavilyUrl -match 'YOUR_TAVILY_API_KEY')

if ($DryRun) {
    Write-Ok ("mcp (dry-run): сохранено серверов {0}, добавлено из шаблона {1}" -f $merge.Preserved.Count, $merge.Added.Count)
    if ($merge.Added.Count -gt 0) { Write-Info ("будут добавлены: {0}" -f ($merge.Added -join ', ')) }
    if ($merge.Preserved.Count -gt 0) { Write-Info ("останутся без изменений: {0}" -f ($merge.Preserved -join ', ')) }
} else {
    $backupPath = $null
    if (Test-Path -LiteralPath $mcpTarget) {
        $backupPath = ("{0}.bak-{1}" -f $mcpTarget, (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Copy-Item -LiteralPath $mcpTarget -Destination $backupPath -Force
        Write-Ok ("mcp: бэкап -> {0}" -f $backupPath)
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($mcpTarget, $mcpJson, $utf8NoBom)

    $verifyError = $null
    $bytes = [IO.File]::ReadAllBytes($mcpTarget)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $verifyError = 'MCP JSON записан с BOM'
    }
    $written = $null
    if (-not $verifyError) {
        try { $written = [IO.File]::ReadAllText($mcpTarget) | ConvertFrom-Json }
        catch { $verifyError = "записанный MCP JSON не парсится: $($_.Exception.Message)" }
    }
    if (-not $verifyError -and $null -ne $existingMcp -and $null -ne $existingMcp.mcpServers) {
        foreach ($name in @($existingMcp.mcpServers.PSObject.Properties.Name)) {
            $before = $existingMcp.mcpServers.$name | ConvertTo-Json -Depth 20 -Compress
            $after  = $written.mcpServers.$name | ConvertTo-Json -Depth 20 -Compress
            if ($before -ne $after) { $verifyError = "сервер '$name' изменился при записи"; break }
        }
    }
    if ($verifyError) {
        if ($backupPath) {
            Copy-Item -LiteralPath $backupPath -Destination $mcpTarget -Force
            Write-Warn2 ("восстановлен бэкап: {0}" -f $backupPath)
        }
        throw ("{0}: {1}" -f $verifyError, $mcpTarget)
    }

    $addedText = if ($merge.Added.Count -gt 0) { ': ' + ($merge.Added -join ', ') } else { '' }
    Write-Ok ("mcp: сохранено серверов {0}{1}" -f $merge.Preserved.Count, $(if ($merge.Preserved.Count -gt 0) { ' (' + ($merge.Preserved -join ', ') + ')' } else { '' }))
    Write-Ok ("mcp: добавлено из шаблона {0}{1}" -f $merge.Added.Count, $addedText)
}

# 8. Манифест установки (по нему работают prune при следующей установке и uninstall.ps1)
if (-not $DryRun) {
    $manifest = [pscustomobject]@{
        toolkit     = 'cline-toolkit'
        version     = $toolkitVersion
        installedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        files       = $script:installedFiles.ToArray()
    }
    $manifestDir = Split-Path -Parent $manifestPath
    if ($manifestDir -and -not (Test-Path -LiteralPath $manifestDir)) {
        New-Item -ItemType Directory -Force -Path $manifestDir | Out-Null
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 10), $utf8NoBom)
    Write-Ok ("манифест -> {0} ({1} файлов, v{2})" -f $manifestPath, $script:installedFiles.Count, $toolkitVersion)
}

# 9. Итоговый отчёт
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
