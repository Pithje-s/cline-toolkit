function Add-Percent {
    param(
        [double]$Value,
        [double]$Percent
    )

    return $Value * $Percent / 100
}
