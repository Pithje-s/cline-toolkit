<#
.SYNOPSIS
    Запуск тестов cline-toolkit (Pester 3.x и 5.x).
.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
#>
param()

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$pester = Get-Module -ListAvailable Pester | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pester) { throw 'Pester не установлен. Установите: Install-Module Pester -Scope CurrentUser' }
Import-Module $pester.Path -ErrorAction Stop
$major = (Get-Module Pester).Version.Major
Write-Host ("== Pester {0} ({1}) ==" -f (Get-Module Pester).Version, $pester.Path) -ForegroundColor Cyan

if ($major -ge 5) {
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = $here
    $cfg.Run.PassThru = $true
    $cfg.Output.Verbosity = 'Detailed'
    $result = Invoke-Pester -Configuration $cfg
} else {
    $result = Invoke-Pester -Script $here -PassThru
}

$total   = if ($null -ne $result.TotalCount)   { $result.TotalCount }   else { 0 }
$passed  = if ($null -ne $result.PassedCount)  { $result.PassedCount }  else { 0 }
$failed  = if ($null -ne $result.FailedCount)  { $result.FailedCount }  else { 0 }
$skipped = if ($null -ne $result.SkippedCount) { $result.SkippedCount } else { 0 }

Write-Host ""
Write-Host ("RESULT: total={0} passed={1} failed={2} skipped={3}" -f $total, $passed, $failed, $skipped)

if ($failed -gt 0) {
    # Pester 5 отдаёт упавшие блоки в .Failed, Pester 3 — в .TestResult
    $failedItems = @()
    if ($result.PSObject.Properties.Name -contains 'Failed') { $failedItems = @($result.Failed) }
    if ($failedItems.Count -gt 0) {
        foreach ($f in $failedItems) {
            Write-Host ("FAILED: {0}" -f $f.ExpandedPath) -ForegroundColor Red
            foreach ($e in @($f.ErrorRecord)) {
                Write-Host ("        " + $e.Exception.Message) -ForegroundColor Red
            }
        }
    } else {
        foreach ($t in @($result.TestResult)) {
            if ($t.Passed -eq $false) {
                Write-Host ("FAILED: {0}`n        {1}" -f $t.Name, $t.FailureMessage) -ForegroundColor Red
            }
        }
    }
    exit 1
}
exit 0
