$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'src\Math.ps1')

$r1 = Add-Percent -Value 200 -Percent 10
if ($r1 -ne 20) { throw "200 + 10%: ожидалось 20, получено $r1" }

$r2 = Add-Percent -Value 50 -Percent 50
if ($r2 -ne 25) { throw "50 + 50%: ожидалось 25, получено $r2" }

$r3 = Add-Percent -Value 0 -Percent 10
if ($r3 -ne 0) { throw "0 + 10%: ожидалось 0, получено $r3" }

Write-Output 'TESTS PASS'
