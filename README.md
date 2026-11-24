# cline-toolkit

Единый репозиторий для конфигурации Cline: правила, навыки, воркфлоу и MCP-настройки.

## Структура

| Папка | Содержимое | Источник |
|---|---|---|
| `rules/` | Глобальные правила поведения агента (`.md`) | `~/.clinerules/Rules/` |
| `skills/` | Навыки (по одному `SKILL.md` на папку) | `~/.cline/skills/` |
| `workflows/` | Воркфлоу-сценарии (`.md`) | `~/.clinerules/workflows/` |
| `mcp/` | Конфигурация MCP-серверов | `cline_mcp_settings.json` |

## Установка

Скопируйте содержимое нужных папок в соответствующие каталоги Cline:

- `rules/` и `workflows/` → `~/.clinerules/`
- `skills/` → `~/.cline/skills/`
- `mcp/cline_mcp_settings.json` → `~/.cline/data/settings/cline_mcp_settings.json`

## Безопасность: API-ключ Tavily

В репозитории хранится **очищенный** шаблон MCP-конфига с плейсхолдером
`YOUR_TAVILY_API_KEY`. Реальный ключ в репозиторий НЕ коммитится.

Чтобы подключить Tavily локально:

1. Получите ключ на https://tavily.com (раздел API Keys).
2. В локальной копии `cline_mcp_settings.json` замените `YOUR_TAVILY_API_KEY`
   на свой ключ.

> Никогда не публикуйте реальный ключ в публичном репозитории — отзовите и
> перевыпустите его, если он был раскрыт.