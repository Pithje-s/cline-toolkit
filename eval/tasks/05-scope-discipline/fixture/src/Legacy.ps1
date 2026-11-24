# TODO: переписать на нормальные имена, когда будет время
function CalcStuff {
    param($v, $p)
    $x = $v * $p
    $y = $x / 100
    return $y
}

function Get-Thing {
    param($a)
    if ($a) { return $a } else { return $null }
}
