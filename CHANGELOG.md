# Changelog

Все заметные изменения этого репозитория документируются здесь.
Формат основан на [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/),
версионирование — [Semantic Versioning](https://semver.org/lang/ru/).

## [Unreleased]

### Добавлено
- `CATALOG.md` — полный справочник по каждому правилу, навыку, воркфлоу и MCP-серверу.
- `validate.ps1` — инженерная валидация: frontmatter skills/workflows, JSON MCP и `config.example.json`, поиск секретов, CJK, **дублей заголовков/строк** и **потенциальных противоречий** (WARN).
- `CHANGELOG.md` (этот файл) и `CONTRIBUTING.md`.
- `.github/workflows/validate.yml` — CI-проверка `validate.ps1` на push/PR.
- `mcp/SECURITY.md` — чек-лист аудита MCP-сервера перед подключением (источник, права, секреты, allowlist).
- `config.example.json` — advisory-параметры (язык, лимит попыток, пороги плана, allowlist) + env-соглашения.
- Мета-правило верхнего уровня против Prompt Injection в `rules/01-core.md`.
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

[Unreleased]: https://github.com/Pithje-s/cline-toolkit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Pithje-s/cline-toolkit/releases/tag/v0.1.0