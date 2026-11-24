<#
.SYNOPSIS
    Стоимость набора в контексте: сколько символов/токенов уходит в каждый диалог,
    а сколько грузится только по требованию.
.DESCRIPTION
    Считает по слоям:
      rules     — always-on: Cline подставляет их в каждый запрос;
      skills    — on-demand: в контекст всегда идут только name+description (frontmatter),
                  тело SKILL.md грузится при активации навыка;
      workflows — on-demand: инъекция только при вызове /команды;
      mcp config — не уходит в промпт, но участвует в описании инструментов.

    Токены оцениваются диапазоном (символы/4 … символы/2.2): точное число зависит
    от токенизатора модели, поэтому одно число здесь было бы враньём.
.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\eval\measure-context.ps1
.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\eval\measure-context.ps1 -Json
#>
param(
    [string]$RepoRoot,
    [string]$RulesDir,
    [string]$SkillsDir,
    [string]$WorkflowsDir,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = Split-Path -Parent $PSScriptRoot }
if ([string]::IsNullOrWhiteSpace($RulesDir))     { $RulesDir = Join-Path $RepoRoot 'rules' }
if ([string]::IsNullOrWhiteSpace($SkillsDir))    { $SkillsDir = Join-Path $RepoRoot 'skills' }
if ([string]::IsNullOrWhiteSpace($WorkflowsDir)) { $WorkflowsDir = Join-Path $RepoRoot 'workflows' }

function Get-TextChars {
    param([string]$Path)
    return ([IO.File]::ReadAllText($Path)).Length
}

function Get-FrontmatterChars {
    param([string]$Path)

    $text = [IO.File]::ReadAllText($Path)
    if (-not $text.StartsWith('---')) { return 0 }
    $end = $text.IndexOf("`n---", 3)
    if ($end -lt 0) { return 0 }
    return $end + 4
}

function New-LayerMetric {
    param([string]$Layer, [string]$Load, [int]$Files, [int]$Chars)

    return [pscustomobject]@{
        layer     = $Layer
        load      = $Load
        files     = $Files
        chars     = $Chars
        tokensMin = [math]::Round($Chars / 4)
        tokensMax = [math]::Round($Chars / 2.2)
    }
}

$layers = @()

$ruleFiles = @(Get-ChildItem -LiteralPath $RulesDir -Filter '*.md' -File -ErrorAction SilentlyContinue)
$ruleChars = 0
foreach ($f in $ruleFiles) { $ruleChars += Get-TextChars -Path $f.FullName }
$layers += New-LayerMetric -Layer 'rules' -Load 'always-on' -Files $ruleFiles.Count -Chars $ruleChars

$skillFiles = @(Get-ChildItem -LiteralPath $SkillsDir -Recurse -File -Filter 'SKILL.md' -ErrorAction SilentlyContinue)
$metaChars = 0
$bodyChars = 0
foreach ($f in $skillFiles) {
    $total = Get-TextChars -Path $f.FullName
    $meta = Get-FrontmatterChars -Path $f.FullName
    $metaChars += $meta
    $bodyChars += ($total - $meta)
}
$layers += New-LayerMetric -Layer 'skills metadata' -Load 'always-on'  -Files $skillFiles.Count -Chars $metaChars
$layers += New-LayerMetric -Layer 'skills body'     -Load 'on-demand' -Files $skillFiles.Count -Chars $bodyChars

$wfFiles = @(Get-ChildItem -LiteralPath $WorkflowsDir -Filter '*.md' -File -ErrorAction SilentlyContinue)
$wfChars = 0
foreach ($f in $wfFiles) { $wfChars += Get-TextChars -Path $f.FullName }
$layers += New-LayerMetric -Layer 'workflows' -Load 'on-demand' -Files $wfFiles.Count -Chars $wfChars

$alwaysOn = 0
foreach ($l in $layers) { if ($l.load -eq 'always-on') { $alwaysOn += $l.chars } }

$result = [pscustomobject]@{
    repoRoot        = $RepoRoot
    layers          = $layers
    alwaysOnChars   = $alwaysOn
    alwaysOnTokMin  = [math]::Round($alwaysOn / 4)
    alwaysOnTokMax  = [math]::Round($alwaysOn / 2.2)
    onDemandChars   = ($wfChars + $bodyChars)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6
    exit 0
}

Write-Host ('== Контекст cline-toolkit: {0}' -f $RepoRoot) -ForegroundColor Cyan
Write-Host ''
foreach ($l in $layers) {
    Write-Host ('{0,-18} {1,-10} files={2,-4} chars={3,-7} tokens~{4}-{5}' -f $l.layer, $l.load, $l.files, $l.chars, $l.tokensMin, $l.tokensMax)
}
Write-Host ''
Write-Host ('ALWAYS-ON ИТОГО: {0} символов ~ {1}-{2} токенов в каждом диалоге' -f $result.alwaysOnChars, $result.alwaysOnTokMin, $result.alwaysOnTokMax) -ForegroundColor Yellow
Write-Host ('ON-DEMAND (по вызову): {0} символов — не занимают контекст, пока не активированы' -f $result.onDemandChars)
exit 0
