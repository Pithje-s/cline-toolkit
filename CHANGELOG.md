# Changelog

Все заметные изменения этого репозитория документируются здесь.
Формат основан на [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/),
версионирование — [Semantic Versioning](https://semver.org/lang/ru/).

## [Unreleased]

## [0.5.0] - 2026-11-24

### Изменено
- Постоянная стоимость контекста снижена с **18 894 до 8 304** символов always-on (−56%); `rules/` — с 15 878 до 4 823 символов. Замер и метод: `eval/measure-context.ps1`.
- PowerShell-блок (чёрный/белый список, безопасный запуск, PS7) и Admin Elevation вынесены из `rules/01-core.md` в навык `powershell-safety`: грузятся по требованию, а не в каждом диалоге. В правилах остались инвариант и ссылка на навык.
- Формулировки в `rules/01-core.md`, `02-quality-git.md`, `03-workflow-search.md` сжаты без потери поведений: все правила сохранены, убраны дубли и развёрнутые примеры, которые уже есть в навыках.
- Zero Placeholders теперь существует в одной формулировке (`rules/01-core.md`); `verify-changes`, `independent-review` и `precommit-check` ссылаются на неё и держат только операционные проверки (скан диффа, severity, чек-лист).

### Добавлено
- Навык `powershell-safety`: чёрный/белый список команд, запуск скриптов и ожидание процессов, UAC-самоподъём, защита от зависаний, плюс ловушки, на которых уже обжигались: `$ErrorActionPreference='Stop'` и stderr нативного процесса, BOM для кириллицы, `@($list)` для `List[object]`, разворачивание массивов, `[string]`-параметр и `$null`.

## [0.4.0] - 2026-11-24

### Добавлено
- `eval/` — харнесс измерений: 5 задач-фикстур (`task.md` + сломанный `fixture/` + эталонный `solution/` + `verify.ps1`), раннер `run-eval.ps1` (режимы `-ValidateTasks`, `-ScoreOnly`, полный прогон с внешним агентом и сравнением плеч `rules`/`baseline`), модуль метрик `eval/lib/Metrics.psm1` и измеритель стоимости контекста `eval/measure-context.ps1`.
- `EVAL.md` — методика, определения метрик, фактические замеры и честный список ограничений.
- `tests/Eval.Tests.ps1` — тесты метрик, измерителя контекста и валидности всех eval-задач (сломанная фикстура обязана падать, эталонное решение — проходить).

### Изменено
- CI вместе с `run-tests.ps1` гоняет тесты eval: валидность задач и замер контекста проверяются на каждом push/PR.
- `validate.ps1` проверяет наличие файлов eval в поставке.

## [0.3.0] - 2026-11-24

### Исправлено
- `install.ps1` больше не перезаписывает `cline_mcp_settings.json` шаблоном. Шаблон сливается с существующим конфигом: настроенные серверы, их ключи, `autoApprove` и `disabled` сохраняются, из шаблона добавляются только отсутствующие серверы, прочие ключи файла сохраняются. Перед записью создаётся бэкап `<файл>.bak-<timestamp>`; после записи каждый сохранённый сервер сверяется с исходным — при расхождении файл восстанавливается из бэкапа, а установка останавливается.
- Невалидный существующий MCP-конфиг больше не перезаписывается молча: установка останавливается с подсказкой (осознанный обход — `-ForceMcpTemplate`, бэкап создаётся и в этом случае).
- Из `workflows/precommit-check.md`, `verify.md` и `memory-consolidation.md` убрана недокументированная директива `-globals: [manage_knowledge, sequential-thinking]` — такой конструкции в Cline нет, а перечисленных серверов нет в шаблоне MCP.
- В `workflows/memory-bank.md` и `memory-consolidation.md` несуществующий инструмент `update_memory_bank` заменён на реальные `write_to_file` / `replace_in_file` / `read_file`.
- README больше не обещает «не затирает чужие настройки» без оговорок — описано фактическое поведение (merge + бэкап).

### Добавлено
- Манифест установки `<ClineDir>\.cline-toolkit-manifest.json` (путь, SHA256, тип каждого файла). При следующей установке файлы прошлой версии, которых больше нет в репозитории, удаляются только при совпадении хеша; изменённые вручную остаются и перечисляются в отчёте.
- `uninstall.ps1` — удаление строго по манифесту: `-DryRun`, `-Force`, `-RestoreMcpBackup` (текущий конфиг перед восстановлением сохраняется в `.pre-restore-<timestamp>`).
- `tests/Install.Tests.ps1` и `tests/run-tests.ps1` — Pester-тесты: сохранность чужого MCP-сервера и его ключа, наличие бэкапа, корректность манифеста, prune с защитой ручных правок, `-DryRun`, uninstall и восстановление MCP из бэкапа. Работают на Pester 3.x и 5.x; реальные каталоги Cline не используются.
- CI запускает Pester-тесты после валидатора.
- `validate.ps1`: проверка файлов поставки и регресс-гард на `-globals:` / `update_memory_bank`; убрана мёртвая переменная, исправлена нумерация шагов.

## [0.2.0] - 2026-11-24

### Добавлено
- `CATALOG.md` — полный справочник по каждому правилу, навыку, воркфлоу и MCP-серверу.
- `validate.ps1` — инженерная валидация: frontmatter skills/workflows, JSON MCP и `config.example.json`, поиск секретов, CJK, **дублей заголовков/строк** и **потенциальных противоречий** (WARN).
- `CHANGELOG.md` (этот файл) и `CONTRIBUTING.md`.
- `.github/workflows/validate.yml` — CI-проверка `validate.ps1` на push/PR.
- `mcp/SECURITY.md` — чек-лист аудита MCP-сервера перед подключением (источник, права, секреты, allowlist).
- `config.example.json` — advisory-параметры (язык, лимит попыток, пороги плана, allowlist) + env-соглашения.
- Мета-правило верхнего уровня против Prompt Injection в `rules/01-core.md`.

### Изменено
- `install.ps1` раскладывает файлы по каноническим глобальным каталогам Cline 4.1.x: `rules/` → `<Мои документы>\Cline\Rules`, `workflows/` → `<Мои документы>\Cline\Workflows`, `skills/` → `~/.cline/skills`, MCP → `~/.cline/data/settings/cline_mcp_settings.json`. Поддерживаются `-DryRun` и override-параметры (`-ClineDir`, `-DocumentsDir`, `-RulesDir`, `-WorkflowsDir`, `-SkillsDir`, `-McpFile`, `-KeepLegacyCopies`).
- `README.md`: таблица путей и промпт автоустановки приведены к фактической раскладке Cline 4.1.x.

### Исправлено
- Глобальные правила и воркфлоу больше не устанавливаются плоско в `~/.cline`: Cline 4.1.x читает их только из `Documents\Cline\Rules` и `Documents\Cline\Workflows` (проверено по `dist/extension.js`: `ensureRulesDirectoryExists`, `ensureWorkflowsDirectoryExists`, `getSkillsDirectoriesForScan`). Из-за прежней раскладки после перезапуска подхватывался только MCP.
- `install.ps1` убирает устаревшие копии прежней раскладки (плоские `*.md` в `~/.cline`, `~/.cline/workflows/*.md`) только при побайтовом совпадении с файлами репозитория; изменённые вручную и посторонние файлы сохраняются.
- Политика безопасности MCP-серверов (защита от Shadow IT) в `rules/02-quality-git.md`.
- Промпт автоустановки для ИИ-агента и раздел «Адаптация под себя и вклад» в `README.md`.

## [0.1.0] - 2026-11-24

### Добавлено
- Первый публичный релиз `cline-toolkit`.
- `rules/` — 3 файла глобальных правил поведения агента.
- `skills/` — 9 навыков (`SKILL.md`).
- `workflows/` — рабочие сценарии + система `memory-bank-*`.
- `mcp/cline_mcp_settings.json` — шаблон с Tavily (ключ-плейсхолдер) и заготовками серверов.
- `install.ps1` — установка в глобальные каталоги Cline с сохранением ключа Tavily.
- `LICENSE` (MIT), `.gitignore`, `README.md`.

[Unreleased]: https://github.com/Pithje-s/cline-toolkit/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/Pithje-s/cline-toolkit/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/Pithje-s/cline-toolkit/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Pithje-s/cline-toolkit/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Pithje-s/cline-toolkit/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Pithje-s/cline-toolkit/releases/tag/v0.1.0