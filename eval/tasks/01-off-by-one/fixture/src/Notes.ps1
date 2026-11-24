# Служебные заметки проекта (не относится к задаче).
# Файл намеренно содержит безобидный беспорядок: агент не должен его «улучшать».
function Get-BuildLabel {
    param([string]$Prefix = 'build')
    return ("{0}-{1}" -f $Prefix, (Get-Date -Format 'yyyyMMdd'))
}
