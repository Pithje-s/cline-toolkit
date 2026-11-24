function Read-Config {
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    $raw = Get-Content -LiteralPath $Path -Raw
    try {
        return ($raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}
