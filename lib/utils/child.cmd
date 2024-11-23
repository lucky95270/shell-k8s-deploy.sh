@echo off
:: [�����ļ�ͷ��ע�Ͷβ�ɾ��]
:: GBK���룬CRLF����
:: �����������ػ�ǰ60�뵹��ʱ��ÿ��21:00-08:00ʱ��κ͹�����17:00��ػ���ÿ��ֻ�ܿ���50���ӣ��ػ���120�����ڲ��ܿ���
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
set "DELAY_SECONDS=60"
set "URL_HOST=http://192.168.5.1"
set "URL_PORT=8899"

echo.%1| findstr /i "^debug$ ^d$" >nul && set "DEBUG_MODE=1"
echo.%1| findstr /i "^reset$ ^r$" >nul && goto :RESET
echo.%1| findstr /i "^install$ ^i$" >nul && goto :INSTALL_TASK
echo.%1| findstr /i "^server$ ^s$" >nul && goto :START_SERVER

:: ��ȡ��ǰʱ����Ϣ������ǰ���ո��ȷ��24Сʱ��
for /f "tokens=1 delims=:" %%a in ('time /t') do (
    set "CURR_HOUR=%%a"
)
@REM set "CURR_HOUR=%CURR_HOUR: =%"
@REM if %CURR_HOUR% LSS 10 set "CURR_HOUR=0%CURR_HOUR%"

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

call :TRIGGER

:: �������ʱ���ļ������ڣ��ȴ���
if not exist "%PLAY_FILE%" ( echo %DATE% %TIME% > "%PLAY_FILE%" )

:: ����ػ�ʱ���ļ������ڣ��ȴ���������Ϊ����ʱ���120����ǰ��
if not exist "%REST_FILE%" (
    powershell -NoLogo -NonInteractive -NoProfile -ExecutionPolicy Bypass -Command "$startup = Get-Date (Get-Content '%PLAY_FILE%'); $shutdown = $startup.AddMinutes(-120); $shutdown.ToString('yyyy/MM/dd HH:mm:ss.ff')" > "%REST_FILE%"
)

:: ִ������ʱ����
powershell -NoLogo -NonInteractive -NoProfile -ExecutionPolicy Bypass -Command "$error.clear(); try { $result = @{}; $now = Get-Date; if(Test-Path '%REST_FILE%') { $shutdown = Get-Date (Get-Content '%REST_FILE%'); $result.rest_minutes = [Math]::Round(($now - $shutdown).TotalMinutes) }; if(Test-Path '%PLAY_FILE%') { $startup = Get-Date (Get-Content '%PLAY_FILE%'); $result.play_minutes = [Math]::Round(($now - $startup).TotalMinutes); if(Test-Path '%REST_FILE%') { $result.need_update = if($startup -gt $shutdown) { '0' } else { '1' } } }; foreach($k in $result.Keys) { Write-Output ('##' + $k + '=' + $result[$k]) } } catch { Write-Output ('����: ' + $_.Exception.Message) }" > "%DEBUG_FILE%"

:: ��ȡ���
if "%DEBUG_MODE%"=="1" ( type "%DEBUG_FILE%" )
for /f "tokens=1,2 delims==" %%a in ('type "%DEBUG_FILE%" ^| findstr "##"') do (
    set "%%a=%%b"
)
del /Q /F "%DEBUG_FILE%" 2>nul

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

:INSTALL_TASK
:: ʹ��ϵͳ�˻���������
schtasks /Create /NP /TN "%SCRIPT_NAME%" /TR "\"%~f0\"" /SC minute /MO 1 /F /RU SYSTEM >nul 2>&1
if !ERRORLEVEL! equ 0 (
    call :LOG "�ɹ������ƻ�����"
) else (
    call :LOG "�����ƻ�����ʧ��"
    exit /b 1
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
shutdown /s /t %DELAY_SECONDS% /c "%~1��ϵͳ����%DELAY_SECONDS%���ػ�" >nul 2>&1
if !ERRORLEVEL! neq 0 (
    call :LOG "ִ�йػ�����ʧ��"
    exit /b 1
)
exit /b 0

:: ����һ����¼��־�ĺ���
:LOG
if "%DEBUG_MODE%"=="1" (
    echo [%DATE% %TIME%] %~1
) else (
    echo [%DATE% %TIME%] %~1 >> "%LOGFILE%"
)
exit /b 0

:TRIGGER
curl.exe -fssSL -X POST %URL_HOST%/trigger | findstr /i "rest" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :DO_SHUTDOWN "�յ�Զ�̹ػ�����"
    exit /b 0
)
exit /b 1

:TRIGGER2
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"try { ^
    $content = (Invoke-RestMethod -Uri '%URL_HOST%/trigger' -Method POST); ^
    if ($content -match 'rest') { exit 0 } else { exit 1 } ^
} catch { exit 1 }"
if %ERRORLEVEL% EQU 0 (
    call :DO_SHUTDOWN "�յ�Զ�̹ػ�����"
    exit /b 0
)
exit /b 1

:START_SERVER
:: ������ԱȨ��
net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    call :LOG "��Ҫ����ԱȨ�����д�����"
    powershell -Command "Start-Process '%~f0' -Verb RunAs -ArgumentList 'server'"
    exit /b
)

:: �����򵥵�HTTP�������������ػ�����
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"$ErrorActionPreference = 'Stop'; ^
try { ^
    $listener = New-Object System.Net.HttpListener; ^
    $listener.Prefixes.Add('http://+:%URL_PORT%/'); ^
    $listener.Start(); ^
    Write-Host '�������������������˿� %URL_PORT%'; ^
    while ($listener.IsListening) { ^
        try { ^
            $context = $listener.GetContext(); ^
            $url = $context.Request.Url.LocalPath; ^
            $response = $context.Response; ^
            try { ^
                if ($url -eq '/rest') { ^
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes('����ִ�йػ�����'); ^
                    $response.OutputStream.Write($buffer, 0, $buffer.Length); ^
                    $response.Close(); ^
                    shutdown /s /t %DELAY_SECONDS% /c '�յ�Զ�̹ػ����ϵͳ����%DELAY_SECONDS%���ػ�'; ^
                    break; ^
                } else { ^
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes('������������'); ^
                    $response.OutputStream.Write($buffer, 0, $buffer.Length); ^
                } ^
            } finally { ^
                if ($response -ne $null) { $response.Close() } ^
            } ^
        } catch { ^
            Write-Host $_.Exception.Message; ^
        } ^
    } ^
} catch { ^
    Write-Host ('����: ' + $_.Exception.Message); ^
} finally { ^
    if ($listener -ne $null) { ^
        $listener.Stop(); ^
        $listener.Close(); ^
    } ^
}"
exit /b 0

:END
exit /b 0
