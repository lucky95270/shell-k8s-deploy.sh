@echo off
:: [�����ļ�ͷ��ע�Ͷβ�ɾ��]
:: GBK���룬CRLF����    curl.exe -Lo child.cmd https://gitee.com/xiagw/deploy.sh/raw/main/lib/utils/child.cmd
:: �����������ػ�ǰ40�뵹��ʱ��ÿ��21:00-08:00ʱ��κ͹�����17:00��ػ���ÿ��ֻ�ܿ���50���ӣ�ÿ�ιػ���120�����ڲ��ܿ���
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
set "DELAY_SECONDS=40"
set "URL_HOST=http://192.168.5.1"
set "URL_PORT=8899"

echo.%1| findstr /i "^debug$ ^d$" >nul && set "DEBUG_MODE=1"
echo.%1| findstr /i "^reset$ ^r$" >nul && goto :RESET
echo.%1| findstr /i "^upgrade$ ^u$" >nul && goto :UPGRADE
echo.%1| findstr /i "^install$ ^i$" >nul && goto :INSTALL_TASK
echo.%1| findstr /i "^server$ ^s$" >nul && goto :START_SERVER

:: ִ������ʱ����
:: powershell -NoLogo -NonInteractive -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "%~f0"
powershell -NoLogo -NonInteractive -NoProfile -ExecutionPolicy Bypass -Command ^
"$error.clear(); ^
try { ^
    $result = @{}; ^
    $now = Get-Date; ^
    $result.curr_hour = $now.Hour; ^
    $result.weekday = [int]$now.DayOfWeek; ^
    if ($result.weekday -eq 0) { $result.weekday = 7 }; ^
    if(-not (Test-Path '%PLAY_FILE%')) { ^
        Set-Content -Path '%PLAY_FILE%' -Value $now.ToString('yyyy/MM/dd HH:mm:ss.ff') -NoNewline; ^
    } ^
    if(-not (Test-Path '%REST_FILE%')) { ^
        $shutdown = $now.AddMinutes(-%REST_MINUTES%); ^
        Set-Content -Path '%REST_FILE%' -Value $shutdown.ToString('yyyy/MM/dd HH:mm:ss.ff') -NoNewline; ^
    } ^
    $shutdown = Get-Date (Get-Content '%REST_FILE%'); ^
    $result.rest_elapsed = [Math]::Round(($now - $shutdown).TotalMinutes); ^
    $startup = Get-Date (Get-Content '%PLAY_FILE%'); ^
    $result.play_elapsed = [Math]::Round(($now - $startup).TotalMinutes); ^
    if($result.play_elapsed -gt %REST_MINUTES%) { ^
        Set-Content -Path '%PLAY_FILE%' -Value $now.ToString('yyyy/MM/dd HH:mm:ss.ff') -NoNewline; ^
        $result.play_elapsed = 0; ^
    } ^
    foreach($k in $result.Keys) { Write-Output ('##' + $k + '=' + $result[$k]) } ^
} catch { ^
    Write-Output ('����: ' + $_.Exception.Message) ^
} ^
" > "%DEBUG_FILE%"

:: ��ȡ���
if "%DEBUG_MODE%"=="1" ( type "%DEBUG_FILE%" )
for /f "tokens=1,2 delims==" %%a in ('type "%DEBUG_FILE%" ^| findstr "##"') do (set "%%a=%%b")
del /Q /F "%DEBUG_FILE%" 2>nul

:: ���Զ�̹ػ�����
:: call :TRIGGER

:: ���ʱ����
if !##curr_hour! GEQ 21 (
    call :DO_SHUTDOWN "����21�������ʹ�õ���"
    exit /b
)
if !##curr_hour! LSS 8 (
    call :DO_SHUTDOWN "����8��ǰ������ʹ�õ���"
    exit /b
)
if !##weekday! LEQ 4 (
    if !##curr_hour! GEQ 17 (
        call :DO_SHUTDOWN "������17�������ʹ�õ���"
        exit /b
    )
)

:: ���ػ�����
if !##rest_elapsed! LSS %REST_MINUTES% (
    call :DO_SHUTDOWN "�����ϴιػ�δ��%REST_MINUTES%���ӣ����̹ػ�"
    exit /b
)
:: ��鿪��ʱ��
if !##play_elapsed! GEQ %PLAY_MINUTES% (
    echo %DATE:~0,10% %TIME% > "%REST_FILE%"
    call :DO_SHUTDOWN "����ʱ�䳬��%PLAY_MINUTES%���ӣ����̹ػ�"
    exit /b
)
:: ����
goto :END

:: �����Ǻ���
:RESET
shutdown /a
del /Q /F "%PLAY_FILE%" "%REST_FILE%"
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
    echo.
    call :LOG "DEBUGģʽ: ��ʾ�ػ�ʱ���ļ�����"
    type "%REST_FILE%"
    exit /b 0
)
:: ִ�йػ�
call :LOG "ִ�йػ�����: %~1"
shutdown /s /t %DELAY_SECONDS% /c "%~1��ϵͳ����%DELAY_SECONDS%���ػ�" >nul 2>&1
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
for /f "delims=" %%a in ('curl.exe -fssSL -X POST %URL_HOST%/trigger') do set "RESPONSE=%%a"
echo.!RESPONSE! | findstr /i "play" >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    exit /b 1
)
echo.!RESPONSE! | findstr /i "rest" >nul 2>&1
if !ERRORLEVEL! EQU 0 (
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

:UPGRADE
:: �������°汾�Ľű�
curl.exe -Lo "%~f0.new" "https://gitee.com/xiagw/deploy.sh/raw/main/lib/utils/child.cmd"
if %ERRORLEVEL% NEQ 0 (
    call :LOG "�����°汾ʧ��"
    del /F /Q "%~f0.new" 2>nul
    exit /b 1
)
:: �滻���ļ�
move /Y "%~f0.new" "%~f0" >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    call :LOG "�����ļ�ʧ��"
    del /F /Q "%~f0.new" 2>nul
    exit /b 1
)
call :LOG "���³ɹ����"
exit /b 0

:END
exit /b 0
