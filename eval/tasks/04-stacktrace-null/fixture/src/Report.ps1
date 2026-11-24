function Get-ReportSummary {
    param($Text)

    $lines = $Text.Split("`n")
    $words = 0
    $nonEmpty = 0
    foreach ($line in $lines) {
        if (-not [string]::IsNullOrWhiteSpace($line)) { $nonEmpty++ }
        $words += @($line -split '\s+' | Where-Object { $_ -ne '' }).Count
    }

    return [pscustomobject]@{
        lines = $nonEmpty
        words = $words
    }
}
