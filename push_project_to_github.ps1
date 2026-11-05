# Назначение сценария — безопасно опубликовать подготовленные материалы в существующем GitHub-репозитории.
# Требование к окружению — Git для Windows и вход в GitHub через Git Credential Manager.

param(
    # Каталог исходного проекта, распакованного из архива «ПР 8-9 (готово к публикации).zip».
    [Parameter(Mandatory = $true)]
    [string]$SourceDirectory,

    # Каталог, в который будет клонирован GitHub-репозиторий.
    [string]$CheckoutDirectory = (Join-Path (Get-Location).Path 'PR 8-9')
)

# Режим строгой проверки переменных и аргументов PowerShell.
Set-StrictMode -Version Latest

# Режим немедленного прекращения работы при ошибках командлетов PowerShell.
$ErrorActionPreference = 'Stop'

# Адрес уже существующего репозитория команды.
$RepositoryUrl = 'https://github.com/Asmerod/Practice8-9.git'

# Абсолютный путь к подготовленным исходным материалам проекта.
$SourceProjectDirectory = (Resolve-Path -LiteralPath $SourceDirectory).Path

# Проверка структуры исходного проекта перед публикацией.
foreach ($RelativePath in @('README.md', 'data/eurusd_d1_bid_final.csv', 'notebooks/Практика_8-9_Задание_1_Группа_2.ipynb')) {
    if (-not (Test-Path -LiteralPath (Join-Path $SourceProjectDirectory $RelativePath) -PathType Leaf)) {
        throw "Отсутствует обязательный исходный файл: $RelativePath"
    }
}

# Проверка наличия установленного Git в командной строке.
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git не найден. Установите Git for Windows и откройте новый PowerShell.'
}

# Проверка отсутствия заранее занятой папки клонирования.
if (Test-Path -LiteralPath $CheckoutDirectory) {
    throw "Папка клонирования уже существует: $CheckoutDirectory. Укажите другой -CheckoutDirectory."
}

# Клонирование текущей истории GitHub вместо создания нового независимого репозитория.
& git clone --branch master --single-branch -- $RepositoryUrl $CheckoutDirectory
if ($LASTEXITCODE -ne 0) { throw 'Ошибка клонирования GitHub-репозитория.' }

# Определение списка файлов, отслеживаемых существующей историей Git.
$TrackedFiles = @(& git -C $CheckoutDirectory ls-files)
if ($LASTEXITCODE -ne 0) { throw 'Не удалось прочитать список файлов репозитория.' }

# Удаление прежнего README в нижнем регистре, если он отслеживается Git.
# Причина — GitHub различает README.md и readme.md, а Windows обычно нет.
if ($TrackedFiles -ccontains 'readme.md') {
    & git -C $CheckoutDirectory rm -- 'readme.md'
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось удалить прежний readme.md.' }
}

# Копирование всех каталогов и файлов утверждённой структуры проекта в клонированный репозиторий.
Get-ChildItem -LiteralPath $SourceProjectDirectory -Force |
    Where-Object { $_.Name -ne '.git' } |
    ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $CheckoutDirectory -Recurse -Force
    }

# Добавление новых, обновлённых и удалённых файлов в индекс Git.
& git -C $CheckoutDirectory add --all
if ($LASTEXITCODE -ne 0) { throw 'Не удалось проиндексировать изменения Git.' }

# Вывод полного перечня планируемых изменений для проверки пользователя.
Write-Host "`nИзменения, подготовленные к публикации:" -ForegroundColor Cyan
& git -C $CheckoutDirectory -c core.quotePath=false status --short
if ($LASTEXITCODE -ne 0) { throw 'Не удалось проверить изменения.' }

# Проверка наличия индексированных изменений перед созданием коммита.
& git -C $CheckoutDirectory diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host 'Изменений для публикации нет.' -ForegroundColor Yellow
    exit 0
}
if ($LASTEXITCODE -ne 1) { throw 'Ошибка проверки изменений Git.' }

# Подтверждение пользователя перед созданием коммита и отправкой в GitHub.
$Approval = Read-Host 'Проверили список файлов? Введите ДА для commit и push'
if ($Approval -cne 'ДА') {
    Write-Host 'Публикация отменена. Подготовленный клон сохранён.' -ForegroundColor Yellow
    exit 0
}

# Создание коммита с обновлённым кодом, README и всеми материалами проекта.
& git -C $CheckoutDirectory commit -m 'Publish EURUSD forecasting research, documentation and reproducible notebook'
if ($LASTEXITCODE -ne 0) { throw 'Не удалось создать коммит.' }

# Отправка коммита в существующую ветку master репозитория команды.
& git -C $CheckoutDirectory push origin master
if ($LASTEXITCODE -ne 0) { throw 'Не удалось опубликовать коммит. Проверьте права GitHub и состояние ветки master.' }

# Вывод подтверждения успешно завершённой публикации.
Write-Host "`nПубликация завершена: $RepositoryUrl" -ForegroundColor Green
