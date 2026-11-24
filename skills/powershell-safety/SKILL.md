---
name: powershell-safety
description: Mandatory rules for running PowerShell, pwsh and Windows terminal commands without hanging the agent. Use when generating or executing PowerShell commands, writing .ps1 scripts, launching or waiting for processes, reading large output, or when a task needs Administrator/UAC rights. Prevents buffered output, interactive prompts, deadlocked Start-Process -Wait, native-stderr terminating errors and encoding breakage.
---

# PowerShell Safety

Правила обязательны при генерации ЛЮБЫХ команд для терминала и любых `.ps1`-скриптов.

## Чёрный список (мгновенный FAIL)

Команды, которые буферизируют вывод, ждут ввода или висят бесконечно:

- интерактивные: `Out-GridView`, `Show-Command`, `Show-ControlPanelItem`, `Show-EventLog`, `Read-Host`, любое `-Paging` (в т.ч. `Out-Host -Paging`);
- форматирование: `Format-Table` (особенно `-AutoSize`/`-Wrap`), `Format-List`, `Format-Wide`, `Format-Hex` — вместо них `Select-Object` или `ForEach-Object { "$($_.Prop) - $($_.Other)" }`;
- `Start-Process ... -Wait` с `-RedirectStandardOutput`/`-RedirectStandardError` — дескрипторы не закрываются, процесс висит вечно;
- `Invoke-Expression` (`iex`) — запрещён правилами безопасности, только прямой вызов `& $exe @args`;
- `while ($true)` без условия выхода или таймаута;
- `Start-Sleep` как ожидание завершения другого процесса — только `Wait-Process -Timeout`.

## Белый список (использовать)

1. Прелюдия сложного скрипта:

   ```powershell
   $ErrorActionPreference = 'Stop'
   $ProgressPreference = 'SilentlyContinue'
   ```

2. Вывод: `Select-Object` для свойств, `ForEach-Object` для строк, `Write-Host` для статуса (умеренно).
3. Файлы: `Test-Path` перед доступом; `-ErrorAction SilentlyContinue` только для некритичных поисков; `-Depth 2`/`-Depth 3` вместо бездумного `-Recurse` на `C:\`, `C:\Users`, `C:\Windows`.
4. Тяжёлые команды вызываются ОДИН раз: `$files = Get-ChildItem ...; $files.Count; $files | ForEach-Object { ... }`.
5. Ожидание: `Wait-Process -Name <имя> -Timeout <сек>`.

## Запуск скриптов и ожидание

- Дождаться завершения: прямой вызов `& "C:\path\script.ps1"` или `powershell.exe -File "C:\path\script.ps1"` — он корректно возвращает вывод и код.
- Долгие операции (сборка, установка): `Start-Job`/отдельное окно и проверка статуса позже, а не блокировка терминала через `-Wait`.
- Скрипт нужен с правами администратора: запуск через `Start-Process powershell -Verb RunAs -ArgumentList '-File "C:\path\script.ps1"'`, БЕЗ `-Wait` и БЕЗ перенаправления вывода. Пользователю сказать, что окно отдельное, и попросить лог.

## Права администратора (UAC)

Если задача требует HKLM, системных файлов или настроек драйверов:

1. Написать готовый `.ps1` (на Рабочий стол или в корень проекта).
2. Внутри — самоподъём прав, чтобы пользователю не пришлось ничего настраивать:

   ```powershell
   $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
   if (-not $isAdmin) { Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath; exit }
   ```

3. Ответ пользователю короткий: «создал `fix_system.ps1`, запусти от имени Администратора, жду лог». Списки «зайдите в настройки и нажмите кнопку» запрещены.
4. Автоматический запуск с `RunAs` без ведома пользователя запрещён: самоподъём допустим только внутри скрипта, который запускает сам пользователь.

## Много вывода и «залипания»

- Команды с большим выводом (логи, деревья файлов): перенаправить в файл и прочитать его инструментом чтения, а не вываливать в терминал.
- В конце команды — маркер завершения: `; Write-Host "EXIT:$LASTEXITCODE"`.
- Если терминал перестал отвечать: не повторять команду «на удачу», а сузить вывод (`Select-Object -First N`, `-Tail 30`) и проверить, не висит ли дочерний процесс.

## Ловушки, на которых уже обжигались

- **stderr нативного процесса + `$ErrorActionPreference='Stop'` = terminating error.** `& git ... 2>&1` или `2>$null` при `Stop` бросает `NativeCommandError` (например, `warning: LF will be replaced by CRLF`), и логика вокруг ломается. Обёртка:

  ```powershell
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { $out = & git ... 2>&1; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $prev }
  ```

- **BOM в `.ps1`.** Windows PowerShell 5.1 читает файл без BOM как ANSI: кириллица превращается в мусор, а иногда в «умные кавычки» — файл перестаёт парситься. Скрипты с кириллицей сохранять в UTF-8 **с BOM**.
- **`@($list)` где `$list` — `List[object]`** может бросить `ArgumentException` («Типы аргумента не совпадают»). Использовать `.ToArray()` или `[object[]]$list`.
- **Разворачивание массивов.** Функция, возвращающая массив из одного элемента, отдаёт скаляр: `.Count` у `PSCustomObject` даст `$null`, а `[0]` — первый символ строки. Возвращать `,$array` и оборачивать на месте `@(...)`.
- **`[string]`-параметр превращает `$null` в `''`.** Если нужен именно `$null` (проверка «не передали»), параметр должен быть без типа или с `[AllowNull()]` и без `[string]`.
