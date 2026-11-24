#requires -Version 5.1
<#
    Тесты eval-харнесса: метрики, измеритель контекста и валидность задач.
    Ассерты через throw — совместимо с Pester 3.x и 5.x.
#>

$script:repoRoot = Split-Path -Parent $PSScriptRoot
$script:evalRoot = Join-Path $script:repoRoot 'eval'
Import-Module (Join-Path $script:evalRoot 'lib\Metrics.psm1') -Force

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

Describe 'Metrics: заглушки' {
    It 'находит TODO и пустые тела в добавленных строках' {
        $lines = Get-AddedLines -DiffText @('+++ b/file.ps1', '+TODO: implement', '+    pass', '+$x = 1')
        Assert-True ($lines.Count -eq 3) ("ожидалось 3 добавленные строки, получено {0}" -f $lines.Count)

        $found = Get-PlaceholderFindings -Lines $lines
        Assert-True ($found.Count -eq 2) ("ожидалось 2 находки (TODO, pass), получено {0}" -f $found.Count)
    }

    It 'не считает заглушкой обычный код' {
        $found = Get-PlaceholderFindings -Lines @('$total = 0', 'return $Value * 2')
        Assert-True ($found.Count -eq 0) 'обычный код помечен как заглушка'
    }
}

Describe 'Metrics: шумные комментарии' {
    It 'ловит комментарий, пересказывающий код' {
        $found = Get-NoisyCommentFindings -Lines @('# Импортируем модуль', '// return value')
        Assert-True ($found.Count -eq 2) ("ожидалось 2 шумных комментария, получено {0}" -f $found.Count)
    }

    It 'не трогает комментарий про причину' {
        $found = Get-NoisyCommentFindings -Lines @('# Обход бага: API возвращает null вместо пустого массива')
        Assert-True ($found.Count -eq 0) 'комментарий why помечен как шум'
    }
}

Describe 'Metrics: доказательства в финальном сообщении' {
    It 'считает «готово» без доказательств недоказанным' {
        Assert-True (Test-UnverifiedDone -Message 'Готово, всё исправлено.') 'не поймано «готово без доказательств»'
    }

    It 'не считает недоказанным сообщение с прогоном тестов' {
        $msg = 'Готово. npm test: 12 passed, exit code 0'
        Assert-True (-not (Test-UnverifiedDone -Message $msg)) 'сообщение с результатом тестов помечено недоказанным'
    }

    It 'не считает недоказанным честную оговорку' {
        Assert-True (-not (Test-UnverifiedDone -Message 'Готово, но UI не проверено')) 'честная оговорка не учтена'
    }
}

Describe 'Metrics: файлы вне scope' {
    It 'парсит git --stat и находит файлы вне разрешённых' {
        $stat = " src/Math.ps1 | 4 ++--`n src/Legacy.ps1 | 2 +-`n 2 files changed, 3 insertions(+), 2 deletions(-)"

        $files = Get-ChangedFiles -DiffStat $stat
        Assert-True ($files.Count -eq 2) ("ожидалось 2 изменённых файла, получено {0}: {1}" -f $files.Count, ($files -join ', '))

        $unrelated = Get-UnrelatedChanges -DiffStat $stat -AllowedPaths @('src/Math.ps1')
        Assert-True ($unrelated.Count -eq 1) ("ожидался 1 файл вне scope, получено {0}" -f $unrelated.Count)
        Assert-True ($unrelated[0] -eq 'src/Legacy.ps1') ("неожиданный файл вне scope: {0}" -f $unrelated[0])
    }
}

Describe 'Metrics: Measure-Workspace' {
    It 'считает добавленные строки, заглушки и изменения вне scope' {
        $ws = Join-Path ([IO.Path]::GetTempPath()) ('eval-metrics-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $ws | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $ws 'a.ps1') -Value 'function A { 1 }' -NoNewline
            Set-Content -LiteralPath (Join-Path $ws 'b.ps1') -Value 'function B { 2 }' -NoNewline
            & git -C $ws init --quiet 2>$null
            & git -C $ws add -A 2>$null
            & git -C $ws -c user.email=eval@localhost -c user.name=eval commit --quiet -m init 2>$null
            if ($LASTEXITCODE -ne 0) { throw 'не удалось создать тестовый git-репозиторий' }

            Set-Content -LiteralPath (Join-Path $ws 'a.ps1') -Value 'function A { 2 }' -NoNewline
            Add-Content -LiteralPath (Join-Path $ws 'a.ps1') -Value "`n# TODO: доделать"
            Set-Content -LiteralPath (Join-Path $ws 'b.ps1') -Value 'function B { 3 }' -NoNewline

            $m = Measure-Workspace -Workspace $ws -AllowedPaths @('a.ps1')
            Assert-True ($m.placeholderCount -eq 1) ("ожидалась 1 заглушка, получено {0}" -f $m.placeholderCount)
            Assert-True ($m.unrelatedCount -eq 1) ("ожидался 1 файл вне scope, получено {0}" -f $m.unrelatedCount)
            Assert-True ($m.unrelatedFiles[0] -eq 'b.ps1') ("неожиданный файл вне scope: {0}" -f $m.unrelatedFiles[0])
            Assert-True ($m.addedLines -gt 0) 'не посчитаны добавленные строки'
        } finally {
            Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
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

Describe 'eval: валидность задач' {
    It 'все задачи проходят проверку broken=fail / solution=pass' {
        $outDir = Join-Path ([IO.Path]::GetTempPath()) ('eval-out-' + [guid]::NewGuid().ToString('N'))
        try {
            $run = Invoke-EvalScript -ScriptPath (Join-Path $script:evalRoot 'run-eval.ps1') -Arguments @('-ValidateTasks', '-OutDir', $outDir)
            Assert-True ($run.code -eq 0) ("run-eval -ValidateTasks вернул {0}:`n{1}" -f $run.code, $run.text)
            Assert-True ($run.text -match 'Все задачи валидны') ("нет подтверждения валидности в выводе:`n{0}" -f $run.text)
        } finally {
            Remove-Item -LiteralPath $outDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'eval: measure-context' {
    It 'измеряет слои и always-on стоимость' {
        $run = Invoke-EvalScript -ScriptPath (Join-Path $script:evalRoot 'measure-context.ps1') -Arguments @('-Json')
        Assert-True ($run.code -eq 0) ("measure-context вернул {0}:`n{1}" -f $run.code, $run.text)

        $data = $run.text | ConvertFrom-Json
        Assert-True ($data.alwaysOnChars -gt 0) 'always-on стоимость равна нулю'
        Assert-True (@($data.layers | Where-Object { $_.layer -eq 'rules' }).Count -eq 1) 'слой rules не измерен'
        Assert-True (@($data.layers | Where-Object { $_.layer -eq 'skills metadata' }).Count -eq 1) 'слой skills metadata не измерен'
        Assert-True (@($data.layers | Where-Object { $_.layer -eq 'workflows' }).Count -eq 1) 'слой workflows не измерен'
        Assert-True ($data.onDemandChars -gt 0) 'on-demand стоимость не измерена'
    }

    It 'always-on равен сумме только always-on слоёв' {
        $run = Invoke-EvalScript -ScriptPath (Join-Path $script:evalRoot 'measure-context.ps1') -Arguments @('-Json')
        $data = $run.text | ConvertFrom-Json

        $expected = 0
        foreach ($layer in @($data.layers)) {
            if ($layer.load -eq 'always-on') { $expected += $layer.chars }
        }
        Assert-True ($data.alwaysOnChars -eq $expected) ("alwaysOnChars={0}, сумма always-on слоёв={1}" -f $data.alwaysOnChars, $expected)
    }
}
