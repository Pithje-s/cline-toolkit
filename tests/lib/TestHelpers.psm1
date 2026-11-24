<#
    Общие хелперы тестов cline-toolkit.

    Почему модуль, а не функции в шапке тест-файла: Pester 5 выполняет блоки It
    в отдельной области видимости, и объявления на верхнем уровне файла там
    недоступны (CommandNotFoundException). Функции модуля видны в любом блоке
    и одинаково работают на Pester 3 и 5.
#>

$script:repoRoot        = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:installScript   = Join-Path $script:repoRoot 'install.ps1'
$script:uninstallScript = Join-Path $script:repoRoot 'uninstall.ps1'
$script:evalRoot        = Join-Path $script:repoRoot 'eval'

function Get-ToolkitRoot {
    return $script:repoRoot
}

function Get-EvalRoot {
    return $script:evalRoot
}

function Get-TestApiKey {
    # Собирается из частей, чтобы validate.ps1 не принял строку за утёкший ключ
    return ('tvly-' + 'TESTKEY0000')
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function New-TestEnv {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('cline-toolkit-test-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    $env = @{
        Root      = $root
        ClineDir  = Join-Path $root '.cline'
        Documents = Join-Path $root 'Documents'
        Rules     = Join-Path $root 'Documents\Cline\Rules'
        Workflows = Join-Path $root 'Documents\Cline\Workflows'
        Skills    = Join-Path $root '.cline\skills'
        McpFile   = Join-Path $root '.cline\data\settings\cline_mcp_settings.json'
        Manifest  = Join-Path $root '.cline\.cline-toolkit-manifest.json'
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $env.McpFile) | Out-Null
    return $env
}

function Remove-TestEnv {
    param($Env)
    if ($Env -and (Test-Path -LiteralPath $Env.Root)) {
        Remove-Item -LiteralPath $Env.Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Write-JsonFile {
    param([string]$Path, $Object)
    $json = $Object | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Invoke-EvalScript {
    param([string]$ScriptPath, [string[]]$Arguments = @())

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $list = @($Arguments)
        $raw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @list 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
    }

    return [pscustomobject]@{
        code = $code
        text = (($raw | ForEach-Object { [string]$_ }) -join "`n")
    }
}

function Invoke-Install {
    param($Env, [switch]$DryRun, [switch]$NoPrune)

    & $script:installScript -ClineDir $Env.ClineDir -DocumentsDir $Env.Documents `
        -McpFile $Env.McpFile -ManifestFile $Env.Manifest -DryRun:$DryRun -NoPrune:$NoPrune 6>$null
}

function Invoke-Uninstall {
    param($Env, [switch]$RestoreMcpBackup, [switch]$DryRun)

    $exe = (Get-Process -Id $PID).Path
    $cliArgs = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:uninstallScript,
        '-ClineDir', $Env.ClineDir, '-DocumentsDir', $Env.Documents,
        '-McpFile', $Env.McpFile, '-ManifestFile', $Env.Manifest
    )
    if ($RestoreMcpBackup) { $cliArgs += '-RestoreMcpBackup' }
    if ($DryRun) { $cliArgs += '-DryRun' }

    & $exe @cliArgs 6>$null | Out-Null
    return $LASTEXITCODE
}

function New-SeedMcpConfig {
    param([string]$Path, [string]$ApiKey = (Get-TestApiKey))

    $seed = [ordered]@{
        mcpServers = [ordered]@{
            'my-custom' = [ordered]@{
                command     = 'npx'
                args        = @('-y', 'my-server')
                disabled    = $false
                autoApprove = @('do_stuff')
            }
            tavily = [ordered]@{
                type        = 'streamableHttp'
                url         = ('https://mcp.tavily.com/mcp/?tavilyApiKey=' + $ApiKey)
                disabled    = $false
                autoApprove = @()
            }
        }
    }
    Write-JsonFile -Path $Path -Object $seed
}

Export-ModuleMember -Function Get-ToolkitRoot, Get-EvalRoot, Get-TestApiKey, Assert-True,
    New-TestEnv, Remove-TestEnv, Write-JsonFile, Invoke-EvalScript,
    Invoke-Install, Invoke-Uninstall, New-SeedMcpConfig
