<#
.SYNOPSIS
    Раннер eval-харнесса cline-toolkit.

.DESCRIPTION
    Три режима:

    1. -ValidateTasks — проверка самих задач без агента:
       сломанная фикстура обязана ПАДАТЬ на verify, эталонное решение — ПРОХОДИТЬ.
       Это же гоняется в CI: задачи не должны «сгнить».

    2. -ScoreOnly -Task <имя> -Workspace <каталог> [-Transcript <файл>] —
       оценить уже готовое решение (например, после работы в UI Cline):
       метрики по диффу, acceptance-проверка, метрики по финальному сообщению.

    3. Полный прогон: -AgentExe <путь> -AgentArgs '<arg1>','<arg2>' ...
       Для каждой задачи создаётся временный git-репозиторий из fixture, вызывается
       агент, затем считаются метрики. Плечи: -Arm rules|baseline|both.
       «rules» и «baseline» отличаются только тем, что ты сам готовишь окружение
       агента (с установленным набором / без него) — харнесс это не подменяет,
       чтобы не врать о результате.

    Плейсхолдеры в -AgentArgs: {workspace} — каталог задачи, {prompt} — путь к task.md,
    {log} — путь для лога. Флаги конкретного CLI харнесс не выдумывает.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\eval\run-eval.ps1 -ValidateTasks

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\eval\run-eval.ps1 `
        -ScoreOnly -Task 01-off-by-one -Workspace C:\work\t01 -Transcript C:\work\t01.log
#>
param(
    [string]$TasksRoot,
    [string[]]$Task,
    [ValidateSet('rules', 'baseline', 'both')][string]$Arm = 'rules',
    [string]$AgentExe,
    [string[]]$AgentArgs = @(),
    [int]$TimeoutSec = 900,
    [string]$OutDir,
    [switch]$ValidateTasks,
    [switch]$ScoreOnly,
    [string]$Workspace,
    [string]$Transcript,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($TasksRoot)) { $TasksRoot = Join-Path $PSScriptRoot 'tasks' }
if ([string]::IsNullOrWhiteSpace($OutDir))    { $OutDir    = Join-Path $PSScriptRoot 'results' }
Import-Module (Join-Path $PSScriptRoot 'lib\Metrics.psm1') -Force

$runId = (Get-Date).ToString('yyyyMMdd-HHmmss')

function Get-TaskList {
    $dirs = @(Get-ChildItem -LiteralPath $TasksRoot -Directory | Sort-Object Name)
    if ($Task -and $Task.Count -gt 0) {
        $dirs = @($dirs | Where-Object { $Task -contains $_.Name })
        if ($dirs.Count -eq 0) { throw ("задачи не найдены: {0}" -f ($Task -join ', ')) }
    }
    return $dirs
}

function Copy-Fixture {
    param([string]$TaskDir, [string]$Destination)
    if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Copy-Item -Path (Join-Path $TaskDir 'fixture\*') -Destination $Destination -Recurse -Force
}

function Initialize-GitRepo {
    param([string]$Path)
    & git -C $Path init --quiet 2>&1 | Out-Null
    & git -C $Path add -A 2>&1 | Out-Null
    & git -C $Path -c user.email=eval@localhost -c user.name=eval commit --quiet -m 'fixture: baseline state' 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "не удалось зафиксировать базовое состояние в git: $Path" }
}

function Apply-Solution {
    param([string]$TaskDir, [string]$Destination)
    $solution = Join-Path $TaskDir 'solution'
    if (-not (Test-Path -LiteralPath $solution)) { return }
    Copy-Item -Path (Join-Path $solution '*') -Destination $Destination -Recurse -Force
}

function Invoke-TaskVerify {
    param([string]$TaskDir, [string]$WorkspacePath)

    $verify = Join-Path $TaskDir 'verify.ps1'
    # verify возвращает вердикт через код выхода, а текст может попасть в stderr:
    # при ErrorActionPreference=Stop нативный процесс даёт terminating error.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verify -Workspace $WorkspacePath 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
    }
    return [pscustomobject]@{
        code = $code
        text = (($output | ForEach-Object { [string]$_ }) -join "`n")
    }
}

function Invoke-AgentForTask {
    param([string]$TaskDir, [string]$WorkspacePath, [string]$LogPath)

    $promptPath = Join-Path $TaskDir 'task.md'
    $resolved = @()
    foreach ($a in $AgentArgs) {
        $resolved += $a.Replace('{workspace}', $WorkspacePath).Replace('{prompt}', $promptPath).Replace('{log}', $LogPath)
    }

    $cfg = [pscustomobject]@{ exe = $AgentExe; args = $resolved }
    $job = Start-Job -ScriptBlock {
        param($c)
        $argList = @($c.args)
        $out = & $c.exe @argList 2>&1
        $code = $LASTEXITCODE
        foreach ($line in $out) { Write-Output ([string]$line) }
        Write-Output ("AGENT_EXIT:{0}" -f $code)
    } -ArgumentList $cfg

    $finished = Wait-Job -Job $job -Timeout $TimeoutSec
    $timedOut = $false
    if (-not $finished) { $timedOut = $true; Stop-Job -Job $job }

    $lines = @(Receive-Job -Job $job)
    Remove-Job -Job $job -Force

    $exitCode = $null
    $textLines = @()
    foreach ($line in $lines) {
        if ($line -match '^AGENT_EXIT:(-?\d+)$') { $exitCode = [int]$Matches[1]; continue }
        $textLines += $line
    }
    $text = $textLines -join "`n"
    if ($LogPath) { [IO.File]::WriteAllText($LogPath, $text, (New-Object System.Text.UTF8Encoding($false))) }

    return [pscustomobject]@{ exitCode = $exitCode; text = $text; timedOut = $timedOut }
}

function New-TaskResult {
    param(
        [string]$ArmName,
        [string]$TaskDir,
        [string]$WorkspacePath,
        [string]$LogPath,
        [bool]$TimedOut = $false,
        $AgentExit = $null
    )

    $ws = Measure-Workspace -Workspace $WorkspacePath
    $verify = Invoke-TaskVerify -TaskDir $TaskDir -WorkspacePath $WorkspacePath
    $transcript = $null
    if ($LogPath) { $transcript = Measure-Transcript -Path $LogPath }

    return [pscustomobject]@{
        arm               = $ArmName
        task              = (Split-Path -Leaf $TaskDir)
        functionalPass    = ($verify.code -eq 0)
        verifyOutput      = $verify.text
        placeholderCount  = $ws.placeholderCount
        placeholders      = @($ws.placeholders | ForEach-Object { $_.text })
        noisyCommentCount = $ws.noisyCommentCount
        unrelatedCount    = $ws.unrelatedCount
        unrelatedFiles    = @($ws.unrelatedFiles)
        addedLines        = $ws.addedLines
        removedLines      = $ws.removedLines
        unverifiedDone    = [bool]($transcript -and $transcript.unverifiedDone)
        transcriptKnown   = [bool]$transcript
        timedOut          = $TimedOut
        agentExitCode     = $AgentExit
    }
}

function Write-RunResults {
    param([object[]]$Results, [string]$Path)

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $json = ConvertTo-Json -InputObject @($Results) -Depth 8
    [IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))

    Write-Host ''
    Write-Host ('{0,-30} {1,-8} {2,-4} {3,-6} {4,-6} {5,-6}' -f 'task', 'verify', 'ph', 'noise', 'unrel', 'unver') -ForegroundColor Cyan
    foreach ($r in $Results) {
        $unver = if ($r.transcriptKnown) { [int]$r.unverifiedDone } else { 'n/a' }
        Write-Host ('{0,-30} {1,-8} {2,-4} {3,-6} {4,-6} {5,-6}' -f $r.task,
            $(if ($r.functionalPass) { 'PASS' } else { 'FAIL' }),
            $r.placeholderCount, $r.noisyCommentCount, $r.unrelatedCount, $unver)
    }
}

if ($ValidateTasks) {
    Write-Host ("== Валидность задач: {0}" -f $runId) -ForegroundColor Cyan
    $problems = 0
    $rows = @()

    foreach ($taskDir in (Get-TaskList)) {
        $ws = Join-Path ([IO.Path]::GetTempPath()) ('eval-validate-' + [guid]::NewGuid().ToString('N'))
        try {
            Copy-Fixture -TaskDir $taskDir.FullName -Destination $ws
            $broken = Invoke-TaskVerify -TaskDir $taskDir.FullName -WorkspacePath $ws
            Apply-Solution -TaskDir $taskDir.FullName -Destination $ws
            $fixed = Invoke-TaskVerify -TaskDir $taskDir.FullName -WorkspacePath $ws

            $valid = ($broken.code -ne 0) -and ($fixed.code -eq 0)
            if (-not $valid) { $problems++ }

            Write-Host ('{0,-30} broken_exit={1} solution_exit={2} -> {3}' -f $taskDir.Name, $broken.code, $fixed.code, $(if ($valid) { 'OK' } else { 'INVALID' })) -ForegroundColor $(if ($valid) { 'Green' } else { 'Red' })
            if (-not $valid) {
                Write-Host ('    broken:   ' + ($broken.text -replace "`n", ' | '))
                Write-Host ('    solution: ' + ($fixed.text -replace "`n", ' | '))
            }

            $rows += [pscustomobject]@{ task = $taskDir.Name; brokenExit = $broken.code; solutionExit = $fixed.code; valid = $valid }
        } finally {
            Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
    $outFile = Join-Path $OutDir ("tasks-$runId.json")
    [IO.File]::WriteAllText($outFile, (ConvertTo-Json -InputObject @($rows) -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("Отчёт: {0}" -f $outFile)

    if ($problems -gt 0) {
        Write-Host ("НЕВАЛИДНЫХ ЗАДАЧ: {0}" -f $problems) -ForegroundColor Red
        exit 1
    }
    Write-Host 'Все задачи валидны: сломанная фикстура падает, эталонное решение проходит.' -ForegroundColor Green
    exit 0
}

if ($ScoreOnly) {
    if ([string]::IsNullOrWhiteSpace($Workspace)) { throw '-ScoreOnly требует -Workspace <каталог с решением>' }
    if (-not $Task -or $Task.Count -ne 1) { throw '-ScoreOnly требует ровно одну задачу: -Task <имя>' }

    $taskDir = @(Get-TaskList)[0]
    $resolvedWs = (Resolve-Path -LiteralPath $Workspace).Path
    if (-not (Test-Path -LiteralPath (Join-Path $resolvedWs '.git'))) {
        Write-Host '[!] workspace не является git-репозиторием: метрики диффа будут пустыми' -ForegroundColor Yellow
    }

    $r = New-TaskResult -ArmName 'manual' -TaskDir $taskDir.FullName -WorkspacePath $resolvedWs -LogPath $Transcript
    $outFile = Join-Path $OutDir ("score-$runId.json")
    Write-RunResults -Results @($r) -Path $outFile
    Write-Host ("Отчёт: {0}" -f $outFile)
    if (-not $r.functionalPass) { exit 1 }
    exit 0
}

if ([string]::IsNullOrWhiteSpace($AgentExe) -and -not $DryRun) {
    throw 'Нужен -AgentExe (или -DryRun / -ValidateTasks / -ScoreOnly). Харнесс не выбирает агента за тебя.'
}

Write-Host 'Плечи (arms) отличаются ТОЛЬКО окружением агента: с установленным набором правил' -ForegroundColor DarkGray
Write-Host 'и без него. Харнесс не устанавливает и не снимает правила сам — иначе результат был бы фальшивым.' -ForegroundColor DarkGray

$arms = if ($Arm -eq 'both') { @('rules', 'baseline') } else { @($Arm) }
$allResults = @()

foreach ($armName in $arms) {
    Write-Host ''
    Write-Host ("== Плечо: {0}" -f $armName) -ForegroundColor Cyan
    $armResults = @()

    foreach ($taskDir in (Get-TaskList)) {
        $ws  = Join-Path ([IO.Path]::GetTempPath()) ('cline-toolkit-eval\' + $runId + '\' + $armName + '\' + $taskDir.Name)
        $log = Join-Path $OutDir ($runId + '-' + $armName + '-' + $taskDir.Name + '.log')

        Copy-Fixture -TaskDir $taskDir.FullName -Destination $ws
        Initialize-GitRepo -Path $ws

        if ($DryRun) {
            Write-Host ("[dry-run] {0} -> {1}" -f $taskDir.Name, $ws)
            continue
        }

        Write-Host ("--> {0}" -f $taskDir.Name)
        $agent = Invoke-AgentForTask -TaskDir $taskDir.FullName -WorkspacePath $ws -LogPath $log
        if ($agent.timedOut) { Write-Host ("    [!] таймаут {0} с: агент остановлен" -f $TimeoutSec) -ForegroundColor Yellow }

        $r = New-TaskResult -ArmName $armName -TaskDir $taskDir.FullName -WorkspacePath $ws -LogPath $log -TimedOut $agent.timedOut -AgentExit $agent.exitCode
        Write-Host ("    verify={0} placeholders={1} noise={2} unrelated={3} unverifiedDone={4}" -f
            $(if ($r.functionalPass) { 'PASS' } else { 'FAIL' }),
            $r.placeholderCount, $r.noisyCommentCount, $r.unrelatedCount,
            $(if ($r.transcriptKnown) { [int]$r.unverifiedDone } else { 'n/a' }))
        if ($r.unrelatedCount -gt 0) { Write-Host ("    вне scope: " + ($r.unrelatedFiles -join ', ')) -ForegroundColor Yellow }

        $armResults += $r
    }

    if (-not $DryRun -and $armResults.Count -gt 0) {
        $allResults += $armResults
        $file = Join-Path $OutDir ($runId + '-' + $armName + '.json')
        Write-RunResults -Results $armResults -Path $file
        Write-Host ("Отчёт: {0}" -f $file)
    }
}

if ($DryRun) {
    Write-Host ''
    Write-Host 'Dry-run завершён: рабочие каталоги подготовлены, агент не вызывался.' -ForegroundColor Yellow
    exit 0
}

if ($arms.Count -eq 2) {
    $cmp = Compare-EvalArms `
        -RulesResults    @($allResults | Where-Object { $_.arm -eq 'rules' }) `
        -BaselineResults @($allResults | Where-Object { $_.arm -eq 'baseline' })

    Write-Host ''
    Write-Host ("== Сравнение плеч (Δ = rules − baseline), задач: {0} / {1}" -f $cmp.rulesTasks, $cmp.baselineTasks) -ForegroundColor Cyan
    foreach ($row in $cmp.rows) {
        $delta = $row.rules - $row.baseline
        Write-Host ('{0,-16} rules={1,-6} baseline={2,-6} Δ={3}' -f $row.metric, $row.rules, $row.baseline, $delta)
    }
    Write-Host 'functionalPass: больше = лучше. placeholders/noisyComments/unrelatedFiles/unverifiedDone: меньше = лучше.'
}

exit 0
