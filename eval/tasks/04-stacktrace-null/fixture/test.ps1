$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'src\Report.ps1')

$summary = Get-ReportSummary -Text "первая строка`nвторая строка"
if ($summary.lines -ne 2) { throw "ожидалось lines=2, получено $($summary.lines)" }
if ($summary.words -ne 4) { throw "ожидалось words=4, получено $($summary.words)" }

$empty = Get-ReportSummary -Text ''
if ($empty.lines -ne 0) { throw "пустая строка: ожидалось lines=0, получено $($empty.lines)" }
if ($empty.words -ne 0) { throw "пустая строка: ожидалось words=0, получено $($empty.words)" }

$nullText = Get-ReportSummary -Text $null
if ($nullText.lines -ne 0) { throw "null: ожидалось lines=0, получено $($nullText.lines)" }

Write-Output 'TESTS PASS'
