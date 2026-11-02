@echo off
chcp 65001 >nul
setlocal EnableExtensions

REM ============================================================
REM Тема: Диагностика клиентского компьютера, часть 2
REM Автор: Рыболовлева
REM Дата: 02.11.2026
REM Скрипт собирает сведения о компьютере, затем сверяет список
REM установленных программ с эталонными списками и выдаёт
REM рекомендации администратору.
REM ============================================================

REM --- Пути к файлам: отчёт лежит рядом со скриптом ---
set "REPORT=%~dp0pc_report.txt"
set "APPS_RAW=%TEMP%\apps_raw.txt"
set "APPS=%TEMP%\apps_list.txt"
set "FOUND_TMP=%TEMP%\found_tmp.txt"

REM --- Тестовая программа для проверки логики, шаг 8 ---
REM Чтобы проверить раздел излишнего ПО, впишите название, например:
REM set "TEST_EXTRA=uTorrent TEST"
REM После проверки верните пустое значение.
set "TEST_EXTRA="

REM --- Счётчики для итога ---
set /a CHECKED=0
set /a EXC_GROUPS=0
set /a RECS=0

REM --- Создаём пустой отчёт, старый перезаписывается ---
type nul > "%REPORT%"

echo.
echo Запуск диагностики. Пожалуйста, не закрывайте окно.
echo.

REM --- Дата и время формирования отчёта ---
set "NOW="
call :ps NOW "Get-Date -Format 'dd.MM.yyyy HH:mm:ss'"
if not defined NOW set "NOW=не удалось определить"

call :log "========================================"
call :log "Диагностика компьютера"
call :log "Дата и время формирования отчёта: %NOW%"
call :log "Компьютер: %COMPUTERNAME%, пользователь: %USERNAME%"
call :log "========================================"
call :log ""

REM ============================================================
REM БЛОК 1. Сведения о системе. Перед каждым запросом переменные
REM очищаются, после него проверяется, получены ли данные.
REM ============================================================
echo [1/6] Сбор сведений о системе и оборудовании...

call :log "Операционная система"
call :log "----------------------------------------"
set "OS_NAME="
set "OS_VER="
call :ps OS_NAME "(Get-CimInstance Win32_OperatingSystem).Caption"
call :ps OS_VER "(Get-CimInstance Win32_OperatingSystem).Version"
call :logv "Название" "%OS_NAME%"
call :logv "Версия" "%OS_VER%"
call :log ""

call :log "Процессор"
call :log "----------------------------------------"
set "CPU_NAME="
call :ps CPU_NAME "(Get-CimInstance Win32_Processor | Select-Object -First 1).Name"
call :logv "Модель" "%CPU_NAME%"
call :log ""

REM Деление и округление до ГБ делает PowerShell, чтобы не было
REM переполнения в set /a
call :log "Оперативная память"
call :log "----------------------------------------"
set "RAM_TOTAL_GB="
set "RAM_FREE_GB="
call :ps RAM_TOTAL_GB "[math]::Round((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize/1MB,1)"
call :ps RAM_FREE_GB "[math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB,1)"
call :logv "Всего памяти, ГБ" "%RAM_TOTAL_GB%"
call :logv "Свободно памяти, ГБ" "%RAM_FREE_GB%"
call :log ""

call :log "Диск C"
call :log "----------------------------------------"
set "DISK_SIZE_GB="
set "DISK_FREE_GB="
call :ps DISK_SIZE_GB "[math]::Round(((Get-PSDrive C).Used + (Get-PSDrive C).Free)/1GB,1)"
call :ps DISK_FREE_GB "[math]::Round((Get-PSDrive C).Free/1GB,1)"
call :logv "Всего, ГБ" "%DISK_SIZE_GB%"
call :logv "Свободно, ГБ" "%DISK_FREE_GB%"
call :log ""

REM ============================================================
REM БЛОК 2. Список установленных программ во временный файл.
REM Опрашиваются обе ветки реестра: 64-битные и 32-битные программы.
REM В файл попадает только название, то есть третья часть строки.
REM ============================================================
echo [2/6] Опрос реестра, это может занять до минуты...
set "APPS_COUNT="
type nul > "%APPS_RAW%"
for /f "tokens=2*" %%a in ('reg query "HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall" /s 2^>nul ^| findstr /r /c:"^ *DisplayName  *REG_SZ"') do >> "%APPS_RAW%" echo(%%b
for /f "tokens=2*" %%a in ('reg query "HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" /s 2^>nul ^| findstr /r /c:"^ *DisplayName  *REG_SZ"') do >> "%APPS_RAW%" echo(%%b
if defined TEST_EXTRA >> "%APPS_RAW%" echo(%TEST_EXTRA%

echo [3/6] Сортировка списка и удаление повторов...
powershell -NoProfile -Command "$l = @(Get-Content -LiteralPath '%APPS_RAW%' -Encoding UTF8 | Sort-Object -Unique); [System.IO.File]::WriteAllLines('%APPS%', [string[]]$l, (New-Object System.Text.UTF8Encoding($false)))" 2>nul
if not exist "%APPS%" copy /y "%APPS_RAW%" "%APPS%" >nul
for /f %%n in ('type "%APPS%" 2^>nul ^| find /c /v ""') do set "APPS_COUNT=%%n"
if not defined APPS_COUNT set "APPS_COUNT=0"

call :log "Установленные программы"
call :log "----------------------------------------"
if "%APPS_COUNT%"=="0" (
    call :log "Не удалось получить список установленных программ"
) else (
    call :log "Найдено программ: %APPS_COUNT%"
    for /f "usebackq delims=" %%a in ("%APPS%") do call :log "%%a"
)
call :log ""

REM Если список пуст, анализировать нечего: иначе скрипт выдал бы
REM ложные рекомендации установить всё подряд
if "%APPS_COUNT%"=="0" (
    call :log "Анализ ПО пропущен: список программ пуст."
    goto :after_analysis
)

REM ============================================================
REM БЛОК 3. Раздел 1: проверка базового набора ПО.
REM Для каждой категории в списке ищем хотя бы одно совпадение
REM по ключевым словам без учёта регистра. Нашли: отметка OK.
REM Не нашли: конкретная рекомендация.
REM ============================================================
echo [4/6] Анализ: проверка базового набора программ...
call :log "Раздел 1. Проверка базового набора ПО для офисной работы"
call :log "Базовый набор: офисный пакет, браузер, чтение PDF, архиватор, антивирус."
call :log "----------------------------------------"

REM Антивирус: помимо списка программ спрашиваем Центр безопасности
REM Windows, потому что Defender в реестре программ не значится
set "AV_NAME="
call :ps AV_NAME "(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct | Select-Object -ExpandProperty displayName) -join ', '"

call :check_cat "Офисный пакет" "Не обнаружен офисный пакет. Для работы с документами рекомендуется установить LibreOffice или Microsoft Office." "Office" "LibreOffice" "OpenOffice" "MyOffice" "Microsoft 365" "WPS"
call :check_browser
call :check_cat "Просмотр PDF" "Не обнаружена программа для чтения PDF. Рекомендуется установить SumatraPDF, Foxit Reader или Adobe Acrobat Reader." "Acrobat" "Foxit" "Sumatra" "PDF-XChange" "Adobe Reader"
call :check_cat "Архиватор" "Не обнаружен архиватор. Для работы с вложениями в почте рекомендуется установить 7-Zip или WinRAR." "7-Zip" "WinRAR" "WinZip" "PeaZip"
call :check_av
call :log ""

REM ============================================================
REM БЛОК 4. Раздел 2: ПО, не относящееся к базовым офисным задачам.
REM Это рекомендации к проверке, а не указание к удалению.
REM ============================================================
echo [5/6] Анализ: поиск ПО, не относящегося к офисным задачам...
call :log "Раздел 2. ПО, не относящееся к базовым офисным задачам"
call :log "Это рекомендации к проверке, а не указание к удалению."
call :log "Часть программ может быть установлена по согласованию с руководством."
call :log "----------------------------------------"

call :check_excess "Игровое ПО и игровые платформы" "Проверьте, нужны ли эти программы для работы." "Steam" "Epic Games" "GOG" "Origin" "Ubisoft Connect" "Battle.net" "Riot" "game" "gaming"
call :check_excess "Торрент-клиенты и файлообменные программы" "Создают нагрузку на сеть и часто являются источником нежелательного ПО. Рекомендуется проверить." "torrent" "uTorrent" "BitTorrent" "qBittorrent" "Vuze"
call :check_excess "Мессенджеры и приложения для личного общения" "Уточните, входят ли они в корпоративный стандарт. В части организаций это рабочий инструмент." "Discord" "Telegram" "WhatsApp" "Viber" "Skype"
call :check_excess "Инструменты для развлечений и оформления" "Не нужны для работы, если нет стандарта организации. Проверьте необходимость." "Wallpaper Engine" "OBS Studio" "Soundpad" "VLC" "PotPlayer" "KMPlayer" "AIMP"
call :log ""

:after_analysis
REM ============================================================
REM БЛОК 5. Итог и уборка
REM ============================================================
echo [6/6] Завершение работы...
call :log "ИТОГ"
call :log "----------------------------------------"
call :log "Проверено категорий базового ПО: %CHECKED%"
call :log "Проверено групп признаков излишнего ПО: %EXC_GROUPS%"
call :log "Выдано рекомендаций: %RECS%"
call :log "Полный путь к отчёту: %REPORT%"

REM Временные файлы удаляем перед выходом
del "%APPS_RAW%" "%APPS%" "%FOUND_TMP%" 2>nul

echo.
pause
exit /b

REM ============================================================
REM ПОДПРОГРАММЫ
REM ============================================================

REM --- :log печатает строку на экран и дописывает в отчёт.
REM Текст берётся через переменную и !MSG!, поэтому символы
REM амперсанд, скобки и вертикальная черта не ломают вывод.
REM Пустая строка выводится через echo с открывающей скобкой.
:log
setlocal DisableDelayedExpansion
set "MSG=%~1"
setlocal EnableDelayedExpansion
echo(!MSG!
>> "%REPORT%" echo(!MSG!
endlocal
endlocal
exit /b

REM --- :logv печатает строку Название: значение.
REM Если значение пустое, пишет, что данные получить не удалось.
:logv
if "%~2"=="" (
    call :log "%~1: данные получить не удалось"
) else (
    call :log "%~1: %~2"
)
exit /b

REM --- :ps выполняет команду PowerShell и кладёт результат
REM в переменную, имя которой передано первым аргументом.
:ps
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "%~2" 2^>nul`) do set "%~1=%%a"
exit /b

REM --- :build_args превращает список ключевых слов в параметры findstr
:build_args
set "ARGS="
:ba_loop
if "%~1"=="" exit /b
set ARGS=%ARGS% /c:"%~1"
shift
goto :ba_loop

REM --- :find_apps ищет любое из ключевых слов в списке программ.
REM Результат: переменная FOUND, первое найденное название.
:find_apps
set "FOUND="
call :build_args %1 %2 %3 %4 %5 %6 %7 %8 %9
for /f "usebackq delims=" %%f in (`findstr /i %ARGS% "%APPS%" 2^>nul`) do if not defined FOUND set "FOUND=%%f"
exit /b

REM --- :check_cat проверяет одну категорию базового ПО
:check_cat
set "CAT_NAME=%~1"
set "CAT_REC=%~2"
shift
shift
call :find_apps %1 %2 %3 %4 %5 %6 %7 %8 %9
set /a CHECKED+=1
if defined FOUND (
    call :log "[OK] %CAT_NAME%: требование выполнено, найдено: %FOUND%"
) else (
    call :log "[РЕКОМЕНДАЦИЯ] %CAT_REC%"
    set /a RECS+=1
)
exit /b

REM --- :check_browser: Edge есть в любой Windows, поэтому его
REM наличие отмечаем отдельно, как компонент системы
:check_browser
set /a CHECKED+=1
call :find_apps "Chrome" "Firefox" "Yandex" "Opera" "Brave"
if defined FOUND (
    call :log "[OK] Браузер: требование выполнено, найдено: %FOUND%"
    exit /b
)
call :find_apps "Edge"
if defined FOUND (
    call :log "[OK] Браузер: найден только %FOUND%. Это компонент Windows, а не результат настройки рабочего места."
) else (
    call :log "[РЕКОМЕНДАЦИЯ] Не обнаружен браузер. Для работы с веб-сервисами рекомендуется установить Chrome или Firefox."
    set /a RECS+=1
)
exit /b

REM --- :check_av: сначала список программ, затем Центр безопасности
:check_av
set /a CHECKED+=1
call :find_apps "Kaspersky" "ESET" "Dr.Web" "Avast" "AVG" "Norton" "McAfee" "Bitdefender" "Malwarebytes"
if defined FOUND (
    call :log "[OK] Антивирус: требование выполнено, найдено: %FOUND%"
    exit /b
)
if defined AV_NAME (
    call :log "[OK] Антивирус: по данным Центра безопасности Windows зарегистрировано: %AV_NAME%. Microsoft Defender является компонентом Windows."
    exit /b
)
call :log "[РЕКОМЕНДАЦИЯ] Не обнаружен антивирус. Рекомендуется включить Microsoft Defender или установить корпоративное антивирусное решение."
set /a RECS+=1
exit /b

REM --- :check_excess проверяет одну группу излишнего ПО.
REM Найденные названия выводятся списком, пустой результат тоже
REM записывается в отчёт.
:check_excess
set "GRP_NAME=%~1"
set "GRP_NOTE=%~2"
shift
shift
call :build_args %1 %2 %3 %4 %5 %6 %7 %8 %9
set /a EXC_GROUPS+=1
findstr /i %ARGS% "%APPS%" > "%FOUND_TMP%" 2>nul
if errorlevel 1 (
    call :log "[OK] %GRP_NAME%: подходящих программ не найдено."
    exit /b
)
call :log "[ПРОВЕРИТЬ] %GRP_NAME%: найдены программы, не относящиеся к базовым офисным задачам."
call :log "    %GRP_NOTE%"
for /f "usebackq delims=" %%f in ("%FOUND_TMP%") do call :log "    - %%f"
set /a RECS+=1
exit /b
