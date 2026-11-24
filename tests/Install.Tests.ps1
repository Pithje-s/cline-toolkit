#requires -Version 5.1
<#
    Тесты установщика cline-toolkit.

    Хелперы живут в модуле tests/lib/TestHelpers.psm1: Pester 5 выполняет блоки It
    в отдельной области видимости, поэтому функции и переменные из шапки файла там
    недоступны (CommandNotFoundException). Ассерты — через throw, набор работает
    на Pester 3.x и 5.x. Реальные каталоги Cline не используются: каждый тест
    работает в собственном временном каталоге.
#>

Import-Module (Join-Path $PSScriptRoot 'lib\TestHelpers.psm1') -Force

Describe 'install.ps1: MCP merge' {
    It 'сохраняет существующий сервер с ключом и добавляет недостающие из шаблона' {
        $e = New-TestEnv
        try {
            New-SeedMcpConfig -Path $e.McpFile 
            Invoke-Install -Env $e

            $after = [IO.File]::ReadAllText($e.McpFile) | ConvertFrom-Json

            Assert-True ([bool]$after.mcpServers.'my-custom') 'сервер my-custom потерян при установке'
            Assert-True (@($after.mcpServers.'my-custom'.args) -contains 'my-server') 'аргументы my-custom изменены'
            Assert-True (@($after.mcpServers.'my-custom'.autoApprove) -contains 'do_stuff') 'autoApprove my-custom изменён'
            Assert-True ($after.mcpServers.tavily.url -like ('*' + (Get-TestApiKey) + '*')) 'ключ Tavily потерян'
            Assert-True ([bool]$after.mcpServers.memory) 'сервер memory из шаблона не добавлен'

            $backup = @(Get-ChildItem -LiteralPath (Split-Path -Parent $e.McpFile) -Filter 'cline_mcp_settings.json.bak-*' -File -ErrorAction SilentlyContinue)
            Assert-True ($backup.Count -ge 1) 'бэкап MCP-конфига не создан'

            $bytes  = [IO.File]::ReadAllBytes($e.McpFile)
            $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            Assert-True (-not $hasBom) 'MCP JSON записан с BOM'
        } finally { Remove-TestEnv $e }
    }
    It 'не перезаписывает невалидный MCP-конфиг без явного разрешения' {
        $e = New-TestEnv
        try {
            [IO.File]::WriteAllText($e.McpFile, '{ broken json', (New-Object System.Text.UTF8Encoding($false)))

            $threw = $false
            try { Invoke-Install -Env $e } catch { $threw = $true }

            Assert-True $threw 'установка не остановилась на невалидном MCP-конфиге'
            Assert-True ((Get-Content -LiteralPath $e.McpFile -Raw) -eq '{ broken json') 'невалидный MCP-конфиг перезаписан'
            $backup = @(Get-ChildItem -LiteralPath (Split-Path -Parent $e.McpFile) -Filter '*.bak-*' -ErrorAction SilentlyContinue)
            Assert-True ($backup.Count -eq 0) 'создан бэкап, хотя файл не должен был перезаписываться'
        } finally { Remove-TestEnv $e }
    }
}

Describe 'install.ps1: манифест' {
    It 'пишет манифест, все пути из которого существуют' {
        $e = New-TestEnv
        try {
            Invoke-Install -Env $e

            Assert-True (Test-Path -LiteralPath $e.Manifest) 'манифест не создан'
            $m = Get-Content -LiteralPath $e.Manifest -Raw | ConvertFrom-Json
            Assert-True (@($m.files).Count -gt 0) 'манифест пуст'
            $missed = @($m.files | Where-Object { -not (Test-Path -LiteralPath $_.path) })
            Assert-True ($missed.Count -eq 0) ("в манифесте несуществующие пути: {0}" -f (($missed | ForEach-Object { $_.path }) -join '; '))
            Assert-True (@($m.files | Where-Object { -not $_.sha256 }).Count -eq 0) 'в манифесте есть записи без sha256'
        } finally { Remove-TestEnv $e }
    }
}

Describe 'install.ps1: prune' {
    It 'удаляет устаревший файл прошлой установки и оставляет изменённый вручную' {
        $e = New-TestEnv
        try {
            Invoke-Install -Env $e

            $staleSkill = Join-Path $e.Skills 'old-skill\SKILL.md'
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $staleSkill) | Out-Null
            Set-Content -LiteralPath $staleSkill -Value 'stale skill' -NoNewline

            $staleWf = Join-Path $e.Workflows 'old-workflow.md'
            Set-Content -LiteralPath $staleWf -Value 'stale workflow' -NoNewline

            $edited = Join-Path $e.Skills 'edited\SKILL.md'
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $edited) | Out-Null
            Set-Content -LiteralPath $edited -Value 'user edited' -NoNewline

            $m = Get-Content -LiteralPath $e.Manifest -Raw | ConvertFrom-Json
            $files = New-Object System.Collections.Generic.List[object]
            foreach ($f in @($m.files)) { $files.Add($f) }
            $files.Add([pscustomobject]@{ path = $staleSkill; sha256 = (Get-FileHash -LiteralPath $staleSkill -Algorithm SHA256).Hash; kind = 'skills' })
            $files.Add([pscustomobject]@{ path = $staleWf;    sha256 = (Get-FileHash -LiteralPath $staleWf -Algorithm SHA256).Hash;    kind = 'workflows' })
            $files.Add([pscustomobject]@{ path = $edited;     sha256 = ('0' * 64);                                                       kind = 'skills' })
            Write-JsonFile -Path $e.Manifest -Object ([pscustomobject]@{ toolkit = 'cline-toolkit'; version = '0.2.0'; installedAt = '2026-01-01T00:00:00Z'; files = $files })

            Invoke-Install -Env $e

            Assert-True (-not (Test-Path -LiteralPath $staleSkill)) 'устаревший навык не удалён'
            Assert-True (-not (Test-Path -LiteralPath $staleWf)) 'устаревший воркфлоу не удалён'
            Assert-True (Test-Path -LiteralPath $edited) 'изменённый вручную файл удалён, а должен остаться'
        } finally { Remove-TestEnv $e }
    }

    It '-DryRun ничего не пишет' {
        $e = New-TestEnv
        try {
            Invoke-Install -Env $e -DryRun

            Assert-True (-not (Test-Path -LiteralPath $e.Manifest)) 'dry-run создал манифест'
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $e.Rules '01-core.md'))) 'dry-run записал правила'
            Assert-True (-not (Test-Path -LiteralPath $e.McpFile)) 'dry-run записал MCP-конфиг'
        } finally { Remove-TestEnv $e }
    }
}

Describe 'uninstall.ps1' {
    It 'удаляет только файлы из манифеста и не трогает посторонние' {
        $e = New-TestEnv
        try {
            Invoke-Install -Env $e
            $foreign = Join-Path $e.Rules 'my-own-rule.md'
            Set-Content -LiteralPath $foreign -Value 'моё правило' -NoNewline

            $code = Invoke-Uninstall -Env $e

            Assert-True ($code -eq 0) ("uninstall вернул код {0}" -f $code)
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $e.Rules '01-core.md'))) 'правило toolkit не удалено'
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $e.Skills 'verify-changes\SKILL.md'))) 'навык toolkit не удалён'
            Assert-True (Test-Path -LiteralPath $foreign) 'посторонний файл удалён'
            Assert-True (-not (Test-Path -LiteralPath $e.Manifest)) 'манифест не удалён'
            Assert-True (Test-Path -LiteralPath $e.McpFile) 'MCP-конфиг удалён, а не должен'
        } finally { Remove-TestEnv $e }
    }

    It '-RestoreMcpBackup возвращает MCP-конфиг из бэкапа' {
        $e = New-TestEnv
        try {
            New-SeedMcpConfig -Path $e.McpFile 
            Invoke-Install -Env $e
            Write-JsonFile -Path $e.McpFile -Object ([pscustomobject]@{ mcpServers = [pscustomobject]@{} })

            $code = Invoke-Uninstall -Env $e -RestoreMcpBackup

            Assert-True ($code -eq 0) ("uninstall вернул код {0}" -f $code)
            $restored = [IO.File]::ReadAllText($e.McpFile) | ConvertFrom-Json
            Assert-True ([bool]$restored.mcpServers.'my-custom') 'кастомный сервер не восстановлен из бэкапа'
            Assert-True ($restored.mcpServers.tavily.url -like ('*' + (Get-TestApiKey) + '*')) 'ключ Tavily не восстановлен'
        } finally { Remove-TestEnv $e }
    }
}
