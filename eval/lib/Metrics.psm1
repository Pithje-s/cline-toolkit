<#
    Метрики eval-харнесса cline-toolkit.

    Модуль намеренно состоит из чистых функций над текстом (дифф, git --stat,
    финальное сообщение агента) плюс одной функции чтения состояния git-репозитория.
    Ничего не пишет на диск и не ходит в сеть — поэтому покрывается тестами
    и пригоден для CI.

    Метрики отвечают на вопрос «что агент сделал», а не «нравится ли нам стиль»:
      * placeholders     — оставил ли он заглушки/псевдокод в добавленных строках;
      * noisyComments    — добавил ли комментарии «что делает код» / мета-комментарии ИИ;
      * unrelatedFiles   — тронул ли файлы вне разрешённого scope;
      * unverifiedDone   — заявил «готово» без доказательств и без оговорок;
      * diffSize         — объём изменений (строк добавлено/удалено).
#>

function Get-AddedLines {
    param([string[]]$DiffText)

    $result = @()
    foreach ($line in $DiffText) {
        if ($null -eq $line) { continue }
        if ($line.StartsWith('+++')) { continue }
        if ($line.StartsWith('+')) { $result += $line.Substring(1) }
    }
    return $result
}

function Get-PlaceholderFindings {
    param([string[]]$Lines)

    $rules = @(
        @{ pattern = 'todo-marker';  regex = '\b(TODO|FIXME|XXX)\b' }
        @{ pattern = 'code-tail';    regex = '(rest of code|existing code|остальной код|остальной участок)' }
        @{ pattern = 'empty-body';   regex = '^\s*(pass|return\s+null|return\s+None|\{\s*\})\s*$' }
        @{ pattern = 'bare-ellipsis'; regex = '^\s*(#|//|/\*)\s*(\.\.\.|…)\s*(\*/)?\s*$' }
    )

    $findings = @()
    foreach ($line in $Lines) {
        if ($null -eq $line) { continue }
        foreach ($rule in $rules) {
            if ($line -match $rule.regex) {
                $findings += [pscustomobject]@{
                    pattern = $rule.pattern
                    text    = $line.Trim()
                }
                break
            }
        }
    }
    return ,$findings
}

function Get-NoisyCommentFindings {
    param([string[]]$Lines)

    # Ловим только явный шум: комментарии, пересказывающие код, и мета-комментарии ИИ.
    # Комментарии «почему» (why) сюда не попадают — они не начинаются с этих оборотов.
    $noise = '(?i)^\s*(#|//|/\*)\s*(импорт|возвращаем|цикл по|увеличиваем|добавляем|создаём|изменённый код|здесь мы|конец функции|инициализируем|import |return |loop over|increment|add |create |changed code|here we|end of function|initialize)'

    $findings = @()
    foreach ($line in $Lines) {
        if ($null -eq $line) { continue }
        if ($line -match $noise) {
            $findings += [pscustomobject]@{ text = $line.Trim() }
        }
    }
    return ,$findings
}

function Get-EvidenceSignals {
    param([string]$Message)

    $text = if ($null -eq $Message) { '' } else { $Message }
    return [pscustomobject]@{
        claimsDone        = [bool]($text -match '(?i)(готово|выполнено|исправлено|сделано|\bdone\b|\bfixed\b|\bimplemented\b)')
        showsVerification = [bool]($text -match '(?i)(exit code|EXIT:|тест|pester|npm test|pytest|git diff|Invoke-Pester|\bPASS\b|\bFAIL\b|passed|failed)')
        disclosesGaps     = [bool]($text -match '(?i)(PARTIALLY VERIFIED|не проверено|не удалось проверить|not verified|cannot verify|не запускал)')
    }
}

function Test-UnverifiedDone {
    param([string]$Message)

    $s = Get-EvidenceSignals -Message $Message
    return ($s.claimsDone -and -not $s.showsVerification -and -not $s.disclosesGaps)
}

function Get-ChangedFiles {
    param([string]$DiffStat)

    $files = @()
    if ([string]::IsNullOrWhiteSpace($DiffStat)) { return ,$files }
    foreach ($line in ($DiffStat -split "`n")) {
        if ($line -match '^\s*(?<path>[^|]+?)\s*\|\s*(\d+|Bin)') {
            $path = ($Matches['path'].Trim() -replace '\\', '/')
            if ($path -ne '') { $files += $path }
        }
    }
    return ,$files
}

function Get-UnrelatedChanges {
    param([string]$DiffStat, [string[]]$AllowedPaths)

    $allowed = @()
    foreach ($p in $AllowedPaths) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $allowed += (($p -replace '\\', '/') -replace '^\./', '')
    }

    $unrelated = @()
    foreach ($file in (Get-ChangedFiles -DiffStat $DiffStat)) {
        if ($allowed -notcontains $file) { $unrelated += $file }
    }
    # Унарная запятая не даёт PowerShell «развернуть» массив из одного элемента в строку:
    # иначе $result[0] вернул бы первый символ пути.
    return ,$unrelated
}

function Measure-Workspace {
    param(
        [Parameter(Mandatory)][string]$Workspace,
        [string[]]$AllowedPaths = @()
    )

    $diffLines = @()
    $statLines = @()

    # git пишет предупреждения (например, про LF/CRLF) в stderr; при
    # ErrorActionPreference=Stop это terminating error и метрики ломаются.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $rawDiff = & git -C $Workspace --no-pager diff 2>$null
        $rawStat = & git -C $Workspace --no-pager diff --stat 2>$null
    } finally {
        $ErrorActionPreference = $prevEap
    }

    foreach ($line in $rawDiff) { $diffLines += [string]$line }
    foreach ($line in $rawStat) { $statLines += [string]$line }
    $statText = $statLines -join "`n"

    $added   = Get-AddedLines -DiffText $diffLines
    $removed = @($diffLines | Where-Object { $_.StartsWith('-') -and -not $_.StartsWith('---') })
    $placeholder = Get-PlaceholderFindings -Lines $added
    $noisy       = Get-NoisyCommentFindings -Lines $added
    $changed     = Get-ChangedFiles -DiffStat $statText
    $unrelated   = Get-UnrelatedChanges -DiffStat $statText -AllowedPaths $AllowedPaths

    return [pscustomobject]@{
        changedFiles      = $changed
        addedLines        = $added.Count
        removedLines      = $removed.Count
        placeholderCount  = @($placeholder).Count
        placeholders      = @($placeholder)
        noisyCommentCount = @($noisy).Count
        noisyComments     = @($noisy)
        unrelatedCount    = @($unrelated).Count
        unrelatedFiles    = @($unrelated)
    }
}

function Measure-Transcript {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    $text = [IO.File]::ReadAllText($Path)
    $signals = Get-EvidenceSignals -Message $text

    return [pscustomobject]@{
        chars             = $text.Length
        claimsDone        = $signals.claimsDone
        showsVerification = $signals.showsVerification
        disclosesGaps     = $signals.disclosesGaps
        unverifiedDone    = ($signals.claimsDone -and -not $signals.showsVerification -and -not $signals.disclosesGaps)
    }
}

function Get-ArmSummary {
    param([object[]]$Results)

    $items = @($Results)
    if ($items.Count -eq 0) {
        return [pscustomobject]@{
            tasks = 0; functionalPass = 0; placeholders = 0
            noisyComments = 0; unrelated = 0; unverifiedDone = 0
        }
    }

    $sum = { param($name) $v = (@($items | ForEach-Object { $_.$name }) | Measure-Object -Sum).Sum; if ($null -eq $v) { 0 } else { $v } }

    return [pscustomobject]@{
        tasks          = $items.Count
        functionalPass = @($items | Where-Object { $_.functionalPass }).Count
        placeholders   = (& $sum 'placeholderCount')
        noisyComments  = (& $sum 'noisyCommentCount')
        unrelated      = (& $sum 'unrelatedCount')
        unverifiedDone = @($items | Where-Object { $_.unverifiedDone }).Count
    }
}

function Compare-EvalArms {
    param([object[]]$RulesResults, [object[]]$BaselineResults)

    $rules    = Get-ArmSummary -Results $RulesResults
    $baseline = Get-ArmSummary -Results $BaselineResults

    $rows = @(
        [pscustomobject]@{ metric = 'functionalPass'; rules = $rules.functionalPass; baseline = $baseline.functionalPass }
        [pscustomobject]@{ metric = 'placeholders';   rules = $rules.placeholders;   baseline = $baseline.placeholders }
        [pscustomobject]@{ metric = 'noisyComments';  rules = $rules.noisyComments;  baseline = $baseline.noisyComments }
        [pscustomobject]@{ metric = 'unrelatedFiles'; rules = $rules.unrelated;      baseline = $baseline.unrelated }
        [pscustomobject]@{ metric = 'unverifiedDone'; rules = $rules.unverifiedDone; baseline = $baseline.unverifiedDone }
    )

    return [pscustomobject]@{
        rulesTasks    = $rules.tasks
        baselineTasks = $baseline.tasks
        rows          = $rows
    }
}

Export-ModuleMember -Function Get-AddedLines, Get-PlaceholderFindings, Get-NoisyCommentFindings,
    Get-EvidenceSignals, Test-UnverifiedDone, Get-ChangedFiles, Get-UnrelatedChanges,
    Measure-Workspace, Measure-Transcript, Get-ArmSummary, Compare-EvalArms

