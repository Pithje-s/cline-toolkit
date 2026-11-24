function ConvertTo-Slug {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )

    $s = $Text.Trim().ToLowerInvariant()
    $s = $s -replace '\s+', '-'
    $s = $s -replace '[^a-z0-9\-а-яё]', ''

    return $s
}
