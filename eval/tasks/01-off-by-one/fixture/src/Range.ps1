function Get-PageItems {
    param(
        [object[]]$Items = @(),
        [int]$Page = 1,
        [int]$PageSize = 10
    )

    if ($PageSize -le 0) { throw 'PageSize должен быть больше 0' }
    if ($Page -lt 1) { throw 'Page должен быть >= 1' }

    $start = $Page * $PageSize
    $end   = $start + $PageSize - 1

    if ($start -ge $Items.Count) { return @() }
    if ($end -ge $Items.Count) { $end = $Items.Count - 1 }

    return @($Items[$start..$end])
}
