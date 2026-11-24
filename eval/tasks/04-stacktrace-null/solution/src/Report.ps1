function Get-ReportSummary {
    param($Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return [pscustomobject]@{ lines = 0; words = 0 }
    }

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
