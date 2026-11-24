$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'src\Slug.ps1')

$result = ConvertTo-Slug -Text 'Hello World'
if ($result -ne 'hello-world') { throw "ожидалось 'hello-world', получено '$result'" }

$cyrillic = ConvertTo-Slug -Text 'Привет Мир'
if ($cyrillic -ne 'привет-мир') { throw "кириллица: ожидалось 'привет-мир', получено '$cyrillic'" }

$spaces = ConvertTo-Slug -Text 'a   b'
if ($spaces -ne 'a-b') { throw "пробелы: ожидалось 'a-b', получено '$spaces'" }

$special = ConvertTo-Slug -Text 'a!b?'
if ($special -ne 'ab') { throw "спецсимволы: ожидалось 'ab', получено '$special'" }

Write-Output 'TESTS PASS'
