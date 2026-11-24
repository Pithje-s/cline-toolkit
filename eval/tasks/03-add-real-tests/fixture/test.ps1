$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'src\Slug.ps1')

$result = ConvertTo-Slug -Text 'Hello World'
if ($result -ne 'hello-world') { throw "ожидалось 'hello-world', получено '$result'" }

Write-Output 'TESTS PASS'
