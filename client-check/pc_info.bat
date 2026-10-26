@echo off
chcp 65001 >nul

REM ============================================================
REM Тема: Диагностика клиентского компьютера
REM Автор: Рыболовлева
REM Дата: 26.10.2026
REM ============================================================

REM --- Путь к отчёту: файл лежит рядом с pc_info.bat ---
set "REPORT=%~dp0pc_report.txt"
REM Создаём пустой отчёт (если он уже был - он перезапишется)
type nul > "%REPORT%"

REM --- Заголовок ---
call :out "========================================"
call :out "Диагностика компьютера"
call :out "========================================"
call :out ""

REM --- Операционная система ---
call :out "Операционная система"
call :out "----------------------------------------"
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "(Get-CimInstance Win32_OperatingSystem).Caption"`) do set "OS_NAME=%%a"
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "(Get-CimInstance Win32_OperatingSystem).Version"`) do set "OS_VER=%%a"
call :out "Название: %OS_NAME%"
call :out "Версия: %OS_VER%"
call :out ""

REM --- Процессор ---
call :out "Процессор"
call :out "----------------------------------------"
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "(Get-CimInstance Win32_Processor | Select-Object -First 1).Name"`) do set "CPU_NAME=%%a"
call :out "%CPU_NAME%"
call :out ""

REM --- Оперативная память (значения в КБ, переводим в ГБ) ---
call :out "Оперативная память"
call :out "----------------------------------------"
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "(Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize"`) do set "RAM_TOTAL_KB=%%a"
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory"`) do set "RAM_FREE_KB=%%a"
set /a RAM_TOTAL_GB=%RAM_TOTAL_KB%/1048576
set /a RAM_FREE_GB=%RAM_FREE_KB%/1048576
call :out "Всего памяти: %RAM_TOTAL_GB% ГБ"
call :out "Свободно памяти: %RAM_FREE_GB% ГБ"
call :out ""

REM --- Диск C (значения в байтах, переводим в ГБ) ---
REM Байт очень много, set /a не умеет считать числа больше 2 миллиардов.
REM Поэтому сначала отрезаем последние 6 цифр (получаем примерно мегабайты),
REM а потом делим на 1074 (это 1073741824 / 1000000).
call :out "Диск C"
call :out "----------------------------------------"
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "((Get-PSDrive C).Used + (Get-PSDrive C).Free)"`) do set "DISK_SIZE=%%a"
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "(Get-PSDrive C).Free"`) do set "DISK_FREE=%%a"
set /a DISK_SIZE_GB=%DISK_SIZE:~0,-6%/1074
set /a DISK_FREE_GB=%DISK_FREE:~0,-6%/1074
call :out "Всего: %DISK_SIZE_GB% ГБ"
call :out "Свободно: %DISK_FREE_GB% ГБ"
call :out ""

REM --- Установленные программы ---
call :out "Установленные программы"
call :out "----------------------------------------"
echo Идёт поиск программ, подождите немного...

REM 64-битные программы
for /f "tokens=2*" %%a in ('reg query "HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall" /s ^| findstr /r /c:"^ *DisplayName  *REG_SZ"') do (
    echo %%b
    echo %%b >> "%REPORT%"
)

REM 32-битные программы
for /f "tokens=2*" %%a in ('reg query "HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" /s ^| findstr /r /c:"^ *DisplayName  *REG_SZ"') do (
    echo %%b
    echo %%b >> "%REPORT%"
)
echo.

REM --- Конец ---
echo ========================================
echo Отчёт сохранён
echo ========================================
pause
exit /b

REM --- Подпрограмма: печатает строку в окно И дописывает её в файл ---
:out
echo(%~1
echo(%~1 >> "%REPORT%"
exit /b
