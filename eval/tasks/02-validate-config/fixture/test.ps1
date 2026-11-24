$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'src\Config.ps1')

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('cfg-' + [guid]::NewGuid().ToString('N') + '.json')

try {
    Set-Content -LiteralPath $tmp -Value '{"name":"ok","retries":3}' -NoNewline
    $cfg = Read-Config -Path $tmp
    if ($cfg.name -ne 'ok') { throw 'исправный конфиг не прочитан: поле name' }
    if ($cfg.retries -ne 3) { throw 'исправный конфиг не прочитан: поле retries' }

    Set-Content -LiteralPath $tmp -Value '{ broken' -NoNewline
    $threw = $false
    try { Read-Config -Path $tmp | Out-Null } catch {
        $threw = $true
        if ($_.Exception.Message -notmatch 'JSON') { throw "в сообщении об ошибке нет слова JSON: $($_.Exception.Message)" }
    }
    if (-not $threw) { throw 'битый JSON не привёл к исключению' }

    $missing = Join-Path ([IO.Path]::GetTempPath()) ('nope-' + [guid]::NewGuid().ToString('N') + '.json')
    $threw = $false
    try { Read-Config -Path $missing | Out-Null } catch {
        $threw = $true
        if ($_.Exception.Message -notmatch 'найден') { throw "в сообщении нет слова 'найден': $($_.Exception.Message)" }
    }
    if (-not $threw) { throw 'отсутствующий файл не привёл к исключению' }

    Write-Output 'TESTS PASS'
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $missing -Force -ErrorAction SilentlyContinue
}
