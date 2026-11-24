<#
.SYNOPSIS
    Acceptance-проверка задачи 03-add-real-tests.
.DESCRIPTION
    Проверяет не только «тесты зелёные», но и что они реально ловят регресс:
    во временную копию workspace вносится три намеренные поломки, и тесты агента
    обязаны на каждой упасть.
#>
param([string]$Workspace = '.')

$ErrorActionPreference = 'Stop'
$taskRoot = $PSScriptRoot

function Invoke-TestsIn {
    param([string]$Dir)

    $script = Join-Path $Dir 'test.ps1'
    # Нативный процесс пишет упавший тест в stderr; при ErrorActionPreference=Stop
    # это превращается в terminating error и ломает разбор результата. Поэтому здесь
    # на время вызова ослабляем политику: падение теста — ожидаемый исход, а не сбой.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
    }

    return [pscustomobject]@{
        code = $code
        text = (($output | ForEach-Object { [string]$_ }) -join "`n")
    }
}

function Test-MutationDetected {
    param([string]$Name, [string]$Find, [string]$Replace)

    $copy = Join-Path ([IO.Path]::GetTempPath()) ('eval03-' + [guid]::NewGuid().ToString('N'))
    try {
        Copy-Item -LiteralPath $Workspace -Destination $copy -Recurse -Force
        $slugPath = Join-Path $copy 'src\Slug.ps1'
        $original = [IO.File]::ReadAllText($slugPath)
        if (-not $original.Contains($Find)) {
            throw "поломка '$Name' неприменима: в src/Slug.ps1 нет ожидаемого фрагмента (код меняли?)"
        }
        $mutated = $original.Replace($Find, $Replace)
        [IO.File]::WriteAllText($slugPath, $mutated, (New-Object System.Text.UTF8Encoding($true)))

        $run = Invoke-TestsIn -Dir $copy
        if ($run.code -eq 0) {
            throw "тесты не заметили поломку '$Name': они проходят на сломанном коде"
        }
        return $true
    } finally {
        Remove-Item -LiteralPath $copy -Recurse -Force -ErrorAction SilentlyContinue
    }
}

try {
    $expectedSrc = Join-Path (Join-Path $taskRoot 'fixture') 'src\Slug.ps1'
    $actualSrc   = Join-Path $Workspace 'src\Slug.ps1'
    if (-not (Test-Path -LiteralPath $actualSrc)) { throw 'src/Slug.ps1 отсутствует' }
    if ((Get-FileHash -LiteralPath $expectedSrc).Hash -ne (Get-FileHash -LiteralPath $actualSrc).Hash) {
        throw 'src/Slug.ps1 изменён, а по условию задачи его менять нельзя'
    }

    $run = Invoke-TestsIn -Dir $Workspace
    if ($run.code -ne 0) { throw ("test.ps1 упал (exit {0}):`n{1}" -f $run.code, $run.text) }
    if ($run.text -notmatch 'TESTS PASS') { throw "test.ps1 не вывел TESTS PASS:`n$($run.text)" }

    $null = Test-MutationDetected -Name 'пробелы -> подчёркивание' -Find "-replace '\s+', '-'" -Replace "-replace '\s+', '_'"
    $null = Test-MutationDetected -Name 'кириллица вырезается'    -Find '[^a-z0-9\-а-яё]'      -Replace '[^a-z0-9\-]'
    $null = Test-MutationDetected -Name 'спецсимволы не чистятся' -Find '[^a-z0-9\-а-яё]'      -Replace '[^a-z0-9\-а-яё!?]'

    Write-Output 'ACCEPTED: 03-add-real-tests'
    exit 0
} catch {
    Write-Output ('REJECTED: 03-add-real-tests -> ' + $_.Exception.Message)
    exit 1
}
