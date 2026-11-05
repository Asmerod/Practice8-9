# Назначение сценария — публикация оригинального PNG, экспортированного из GitDiagram, в командном GitHub-репозитории.
# Требование к окружению — Git для Windows, доступ к GitHub и локально клонированный репозиторий.

param(
    # Каталог локального клона репозитория Asmerod/Practice8-9.
    [Parameter(Mandatory = $true)]
    [string]$RepositoryDirectory,

    # Полный путь к оригинальному PNG, скачанному на сайте GitDiagram.
    [Parameter(Mandatory = $true)]
    [string]$SourceImagePath
)

# Режим строгой проверки имён переменных и аргументов PowerShell.
Set-StrictMode -Version Latest

# Режим прекращения выполнения сценария при ошибках PowerShell.
$ErrorActionPreference = 'Stop'

# Получение существующего абсолютного пути к клону репозитория.
$ResolvedRepositoryDirectory = (Resolve-Path -LiteralPath $RepositoryDirectory).Path

# Получение существующего абсолютного пути к выгруженному PNG.
$ResolvedImagePath = (Resolve-Path -LiteralPath $SourceImagePath).Path

# Проверка установленного Git перед началом публикации.
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git не найден. Установите Git for Windows и откройте новый PowerShell.'
}

# Проверка корректности ссылки на изображение.
if ([System.IO.Path]::GetExtension($ResolvedImagePath) -ine '.png') {
    throw 'GitDiagram должен быть экспортирован в файл формата PNG.'
}

# Получение первых восьми байтов графического файла.
$ImageBytes = [System.IO.File]::ReadAllBytes($ResolvedImagePath)

# Получение сигнатуры PNG для защиты от случайного выбора другого файла.
$PngSignature = [byte[]](137, 80, 78, 71, 13, 10, 26, 10)

# Проверка полноты заголовка PNG.
if ($ImageBytes.Length -lt $PngSignature.Length) {
    throw 'Файл изображения пуст или повреждён.'
}

# Проверка соответствия всех байтов стандартной сигнатуре PNG.
for ($ByteIndex = 0; $ByteIndex -lt $PngSignature.Length; $ByteIndex++) {
    if ($ImageBytes[$ByteIndex] -ne $PngSignature[$ByteIndex]) {
        throw 'Выбранный файл не имеет корректной сигнатуры PNG.'
    }
}

# Получение адреса origin для проверки назначения публикации.
$RemoteUrl = (& git -C $ResolvedRepositoryDirectory remote get-url origin)
if ($LASTEXITCODE -ne 0) { throw 'Указанная папка не является подходящим Git-клоном.' }

# Проверка соответствия origin утверждённому командному репозиторию.
if ($RemoteUrl -notmatch '(?i)github\.com[:/]Asmerod/Practice8-9(?:\.git)?/?$') {
    throw "Неожиданный origin: $RemoteUrl. Публикация отменена."
}

# Получение названия локальной активной ветки.
$BranchName = (& git -C $ResolvedRepositoryDirectory branch --show-current)
if ($LASTEXITCODE -ne 0 -or $BranchName -ne 'master') {
    throw "Ожидалась активная ветка master, фактически: $BranchName"
}

# Проверка отсутствия незакоммиченных изменений перед обновлением клона.
$PendingChanges = @(& git -C $ResolvedRepositoryDirectory status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Не удалось получить состояние Git.' }
if ($PendingChanges.Count -gt 0) {
    throw 'В клоне есть незакоммиченные изменения. Проверьте их до публикации диаграммы.'
}

# Получение последних изменений удалённой ветки без переписывания истории.
& git -C $ResolvedRepositoryDirectory pull --ff-only origin master
if ($LASTEXITCODE -ne 0) { throw 'Не удалось безопасно обновить ветку master.' }

# Создание отдельного каталога с графическими ресурсами в корне репозитория.
$AssetsDirectory = Join-Path $ResolvedRepositoryDirectory 'assets'
New-Item -ItemType Directory -Path $AssetsDirectory -Force | Out-Null

# Определение конечного имени архитектурной диаграммы.
$DiagramDestination = Join-Path $AssetsDirectory 'Диаграмма архитектуры GitDiagram.png'

# Копирование оригинального графического экспорта без преобразования его содержимого.
if ($ResolvedImagePath -ne $DiagramDestination) {
    Copy-Item -LiteralPath $ResolvedImagePath -Destination $DiagramDestination -Force
}

# Добавление графического ресурса в индекс Git.
& git -C $ResolvedRepositoryDirectory add -- 'assets/Диаграмма архитектуры GitDiagram.png'
if ($LASTEXITCODE -ne 0) { throw 'Не удалось добавить диаграмму в индекс Git.' }

# Вывод изменений для проверки перед созданием коммита.
Write-Host "`nЗапланированные изменения:" -ForegroundColor Cyan
& git -C $ResolvedRepositoryDirectory -c core.quotePath=false status --short
if ($LASTEXITCODE -ne 0) { throw 'Ошибка чтения изменений Git.' }

# Проверка наличия изменений после добавления диаграммы.
& git -C $ResolvedRepositoryDirectory diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host 'Диаграмма уже опубликована без изменений.' -ForegroundColor Yellow
    exit 0
}
if ($LASTEXITCODE -ne 1) { throw 'Ошибка проверки индексированных изменений.' }

# Запрос явного подтверждения публикации в удалённом репозитории.
$Approval = Read-Host 'Проверили имя и содержимое диаграммы? Введите ДА для commit и push'
if ($Approval -cne 'ДА') {
    Write-Host 'Публикация отменена. Изображение осталось только в локальном клоне.' -ForegroundColor Yellow
    exit 0
}

# Создание отдельного коммита с диаграммой GitDiagram.
& git -C $ResolvedRepositoryDirectory commit -m 'Add GitDiagram repository architecture PNG'
if ($LASTEXITCODE -ne 0) { throw 'Не удалось создать коммит диаграммы.' }

# Публикация диаграммы в исходной ветке master.
& git -C $ResolvedRepositoryDirectory push origin master
if ($LASTEXITCODE -ne 0) { throw 'Не удалось отправить диаграмму в GitHub.' }

# Вывод адреса успешно опубликованного репозитория.
Write-Host "`nДиаграмма GitDiagram опубликована: https://github.com/Asmerod/Practice8-9" -ForegroundColor Green
