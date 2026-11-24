function Read-Config {
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Файл конфигурации не найден: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    try {
        return ($raw | ConvertFrom-Json)
    } catch {
        throw "Конфиг не является валидным JSON ($Path): $($_.Exception.Message)"
    }
}
