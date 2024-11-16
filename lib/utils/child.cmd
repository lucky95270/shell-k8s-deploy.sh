@echo off

REM GBK���룬CRLF���У���������ע��
setlocal EnableDelayedExpansion

:: ���û����ļ�����·��
set "SCRIPT_NAME=%~n0"
set "SCRIPT_PATH=%~dp0"
set "BASE_PATH=%SCRIPT_PATH%%SCRIPT_NAME%"
set "LOGFILE=%BASE_PATH%.log"
set "DEBUG_FILE=%BASE_PATH%_debug.txt"
set "PLAY_FILE=%BASE_PATH%_play.txt"
set "REST_FILE=%BASE_PATH%_rest.txt"
set "PLAY_MINUTES=50"
set "REST_MINUTES=120"
set "WORK_HOUR_8=8"
set "WORK_HOUR_17=17"
set "WORK_HOUR_21=21"

echo.%1| findstr /i "^debug$ ^d$" >nul && set "DEBUG_MODE=1"
echo.%1| findstr /i "^reset$ ^r$" >nul && goto :RESET
echo.%1| findstr /i "^install$ ^i$" >nul && goto :INSTALL_TASK

:: ��ȡ��ǰʱ����Ϣ������ǰ���ո��ȷ��24Сʱ��
for /f "tokens=1 delims=:" %%a in ('time /t') do (
    set "CURR_HOUR=%%a"
)
set "CURR_HOUR=%CURR_HOUR: =%"
if %CURR_HOUR% LSS 10 set "CURR_HOUR=0%CURR_HOUR%"

:: ��ȡ��ǰ���ڼ� (1-7, ����1����һ)
if "%DATE:~11%"=="��һ" set "WEEKDAY=1"
if "%DATE:~11%"=="�ܶ�" set "WEEKDAY=2"
if "%DATE:~11%"=="����" set "WEEKDAY=3"
if "%DATE:~11%"=="����" set "WEEKDAY=4"
if "%DATE:~11%"=="����" set "WEEKDAY=5"
if "%DATE:~11%"=="����" set "WEEKDAY=6"
if "%DATE:~11%"=="����" set "WEEKDAY=7"

if "%DEBUG_MODE%"=="1" (
    call :LOG "DEBUGģʽ: ��ǰʱ��=%CURR_HOUR%"
    call :LOG "DEBUGģʽ: ��ǰ���ڼ�=%WEEKDAY%"
    call :LOG "DEBUGģʽ: �����ʱ������"
) else (
    call :CHECK_TIME_LIMITS
)

:: �������ʱ���ļ������ڣ��ȴ���
if not exist "%PLAY_FILE%" ( echo %DATE% %TIME% > "%PLAY_FILE%" )

:: ����ػ�ʱ���ļ������ڣ��ȴ���������Ϊ����ʱ���120����ǰ��
if not exist "%REST_FILE%" (
    powershell -command "$startup = Get-Date (Get-Content '%PLAY_FILE%'); $shutdown = $startup.AddMinutes(-120); $shutdown.ToString('yyyy/MM/dd HH:mm:ss.ff')" > "%REST_FILE%"
)

:: ִ������ʱ����
powershell -command "$error.clear(); try { $result = @{}; $now = Get-Date; if(Test-Path '%REST_FILE%') { $shutdown = Get-Date (Get-Content '%REST_FILE%'); $result.rest_minutes = [Math]::Round(($now - $shutdown).TotalMinutes) }; if(Test-Path '%PLAY_FILE%') { $startup = Get-Date (Get-Content '%PLAY_FILE%'); $result.play_minutes = [Math]::Round(($now - $startup).TotalMinutes); if(Test-Path '%REST_FILE%') { $result.need_update = if($startup -gt $shutdown) { '0' } else { '1' } } }; foreach($k in $result.Keys) { Write-Output ('##' + $k + '=' + $result[$k]) } } catch { Write-Output ('����: ' + $_.Exception.Message) }" > "%DEBUG_FILE%"

:: ��ȡ���
for /f "tokens=1,2 delims==" %%a in ('type "%DEBUG_FILE%" ^| findstr "##"') do (
    set "%%a=%%b"
    call :LOG "���ñ��� %%a=%%b"
)
del "%DEBUG_FILE%" 2>nul

:: ��������ʱ��
if !##need_update! EQU 1 (
    echo %DATE% %TIME% > "%PLAY_FILE%" || (
        call :LOG "�޷���������ʱ���ļ�"
        exit /b 1
    )
)

:: ���ػ�����
if !##rest_minutes! LSS %REST_MINUTES% (
    call :DO_SHUTDOWN "�����ϴιػ�δ��%REST_MINUTES%����"
    exit /b
)

:: ��鿪��ʱ��
if !##play_minutes! GEQ %PLAY_MINUTES% (
    echo %DATE% %TIME% > "%REST_FILE%"
    call :DO_SHUTDOWN "����ʱ�䳬��%PLAY_MINUTES%����"
    exit /b
)
:: ����
goto :END

:: �����Ǻ���
:CHECK_TIME_LIMITS
:: ����Ƿ��������ʱ�䷶Χ��
:: ���21:00-08:00ʱ���
if %CURR_HOUR% GEQ %WORK_HOUR_21% (
    call :DO_SHUTDOWN "������%WORK_HOUR_21%���"
    exit /b
)
if %CURR_HOUR% LSS %WORK_HOUR_8% (
    call :DO_SHUTDOWN "������%WORK_HOUR_8%��ǰ"
    exit /b
)
:: ��鹤����17:00������
if %WEEKDAY% LEQ 5 (
    if %CURR_HOUR% GEQ %WORK_HOUR_17% (
        call :DO_SHUTDOWN "�����ǹ�����%WORK_HOUR_17%���"
        exit /b
    )
)
exit /b

:RESET
shutdown /a
del /Q /F "%PLAY_FILE%"
del /Q /F "%REST_FILE%"
goto :END

:: ����в���"install"���򴴽��ƻ�����
:INSTALL_TASK
schtasks /query /tn "%SCRIPT_NAME%" >nul 2>&1
if !ERRORLEVEL! neq 0 (
    :: ʹ�õ�ǰ�û��˻��������񣬲�ʹ��ϵͳ�˻�
    schtasks /create /tn "%SCRIPT_NAME%" /tr "\"%~f0\"" /sc minute /mo 1 /f /ru "%USERNAME%" >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        call :LOG "�ɹ������ƻ�����"
    ) else (
        call :LOG "�����ƻ�����ʧ��"
        exit /b 1
    )
) else (
    call :LOG "�ƻ������Ѵ���"
)
exit /b 0

:DO_SHUTDOWN
if "%DEBUG_MODE%"=="1" (
    call :LOG "DEBUGģʽ: �����ػ�����: %~1"
    call :LOG "DEBUGģʽ: ��ʾ����ʱ���ļ�����"
    type "%PLAY_FILE%"
    call :LOG "DEBUGģʽ: ��ʾ�ػ�ʱ���ļ�����"
    type "%REST_FILE%"
    exit /b 0
)
:: ִ�йػ�
shutdown /s /t 30 /c "%~1��ϵͳ����30���ػ�" >nul 2>&1
if !ERRORLEVEL! neq 0 (
    call :LOG "ִ�йػ�����ʧ��"
    exit /b 1
)
exit /b 0

:: ����һ����¼��־�ĺ���
:LOG
echo [%DATE% %TIME%] %~1
echo [%DATE% %TIME%] %~1 >> "%LOGFILE%"
exit /b 0

:END
exit /b 0