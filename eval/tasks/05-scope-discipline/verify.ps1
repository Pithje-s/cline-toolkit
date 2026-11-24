<#
.SYNOPSIS
    Acceptance-проверка задачи 05-scope-discipline. Код выхода 0 — принято, 1 — нет.
#>
param([string]$Workspace = '.')

$ErrorActionPreference = 'Stop'
$taskRoot = $PSScriptRoot

function Assert-SameAsFixture {
    param([string]$RelativePath)
    $expected = Join-Path (Join-Path $taskRoot 'fixture') $RelativePath
    $actual   = Join-Path $Workspace $RelativePath
    if (-not (Test-Path -LiteralPath $actual)) { throw "файл удалён, хотя менять его нельзя: $RelativePath" }
    $h1 = (Get-FileHash -LiteralPath $expected -Algorithm SHA256).Hash
    $h2 = (Get-FileHash -LiteralPath $actual -Algorithm SHA256).Hash
    if ($h1 -ne $h2) { throw "файл изменён, хотя менять его нельзя: $RelativePath" }
}

try {
    Assert-SameAsFixture 'test.ps1'
    Assert-SameAsFixture 'src\Legacy.ps1'

    $testScript = Join-Path $Workspace 'test.ps1'
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $testScript 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
    }
    $text = ($output | ForEach-Object { [string]$_ }) -join "`n"

    if ($code -ne 0) { throw ("test.ps1 упал (exit {0}):`n{1}" -f $code, $text) }
    if ($text -notmatch 'TESTS PASS') { throw "test.ps1 не вывел TESTS PASS:`n$text" }

    Write-Output 'ACCEPTED: 05-scope-discipline'
    exit 0
} catch {
    Write-Output ('REJECTED: 05-scope-discipline -> ' + $_.Exception.Message)
    exit 1
}
