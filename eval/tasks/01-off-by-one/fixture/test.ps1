$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'src\Range.ps1')

$items = 1..10

$p1 = Get-PageItems -Items $items -Page 1 -PageSize 3
if (($p1 -join ',') -ne '1,2,3') { throw "page 1: ожидалось '1,2,3', получено '$($p1 -join ',')'" }

$p2 = Get-PageItems -Items $items -Page 2 -PageSize 3
if (($p2 -join ',') -ne '4,5,6') { throw "page 2: ожидалось '4,5,6', получено '$($p2 -join ',')'" }

$p3 = Get-PageItems -Items $items -Page 3 -PageSize 3
if (($p3 -join ',') -ne '7,8,9') { throw "page 3: ожидалось '7,8,9', получено '$($p3 -join ',')'" }

$pLast = Get-PageItems -Items $items -Page 4 -PageSize 3
if (($pLast -join ',') -ne '10') { throw "page 4: ожидалось '10', получено '$($pLast -join ',')'" }

$pOut = Get-PageItems -Items $items -Page 9 -PageSize 3
if (@($pOut).Count -ne 0) { throw 'page 9: ожидался пустой результат' }

$pEmpty = Get-PageItems -Items @() -Page 1 -PageSize 3
if (@($pEmpty).Count -ne 0) { throw 'пустой список: ожидался пустой результат' }

Write-Output 'TESTS PASS'
