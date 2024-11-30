@echo off
:: [�����ļ�ͷ��ע�Ͷβ�ɾ��]
:: GBK���룬CRLF����    curl.exe -Lo child.cmd https://gitee.com/xiagw/deploy.sh/raw/main/lib/utils/child.cmd
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
set "DELAY_SECONDS=40"
set "URL_HOST=http://192.168.5.1"
set "URL_PORT=8899"

echo.%1| findstr /i "^debug$ ^d$" >nul && set "DEBUG_MODE=1"
echo.%1| findstr /i "^reset$ ^r$" >nul && goto :RESET
echo.%1| findstr /i "^install$ ^i$" >nul && goto :INSTALL_TASK
echo.%1| findstr /i "^server$ ^s$" >nul && goto :START_SERVER

:: ִ������ʱ����
powershell -NoLogo -NonInteractive -NoProfile -ExecutionPolicy Bypass -Command ^
"$error.clear(); ^
try { ^
    $now = Get-Date; ^
    # ���û�������
    [Environment]::SetEnvironmentVariable('curr_hour', $now.Hour, 'Process'); ^
    $weekday = [int]$now.DayOfWeek; ^
    if ($weekday -eq 0) { $weekday = 7 }; ^
    [Environment]::SetEnvironmentVariable('weekday', $weekday, 'Process'); ^
    if(-not (Test-Path '%PLAY_FILE%')) { ^
        Set-Content -Path '%PLAY_FILE%' -Value $now.ToString('yyyy/MM/dd HH:mm:ss.ff') -NoNewline; ^
    } ^
    if(-not (Test-Path '%REST_FILE%')) { ^
        $startup = Get-Date (Get-Content '%PLAY_FILE%'); ^
        $shutdown = $startup.AddMinutes(-120); ^
        Set-Content -Path '%REST_FILE%' -Value $shutdown.ToString('yyyy/MM/dd HH:mm:ss.ff') -NoNewline; ^
    } ^
    $shutdown = Get-Date (Get-Content '%REST_FILE%'); ^
    [Environment]::SetEnvironmentVariable('rest_elapsed', [Math]::Round(($now - $shutdown).TotalMinutes), 'Process'); ^
    $startup = Get-Date (Get-Content '%PLAY_FILE%'); ^
    $play_elapsed = [Math]::Round(($now - $startup).TotalMinutes); ^
    if($startup -le $shutdown) { ^
        Set-Content -Path '%PLAY_FILE%' -Value $now.ToString('yyyy/MM/dd HH:mm:ss.ff') -NoNewline; ^
        $play_elapsed = 0; ^
    } ^
    [Environment]::SetEnvironmentVariable('play_elapsed', $play_elapsed, 'Process'); ^
    if ($env:DEBUG_MODE -eq '1') { ^
        Write-Host 'curr_hour=' $env:curr_hour; ^
        Write-Host 'weekday=' $env:weekday; ^
        Write-Host 'rest_elapsed=' $env:rest_elapsed; ^
        Write-Host 'play_elapsed=' $env:play_elapsed; ^
    } ^
} catch { ^
    Write-Host ('����: ' + $_.Exception.Message) ^
}"

call :TRIGGER

:: ���ػ�����
if %curr_hour% GEQ %WORK_HOUR_21% (
    call :DO_SHUTDOWN "������%WORK_HOUR_21%������̹ػ�"
    exit /b
)
if %curr_hour% LSS %WORK_HOUR_8% (
    call :DO_SHUTDOWN "������%WORK_HOUR_8%��ǰ�����̹ػ�"
    exit /b
)
if %weekday% LEQ 5 (
    if %curr_hour% GEQ %WORK_HOUR_17% (
        call :DO_SHUTDOWN "�����ǹ�����%WORK_HOUR_17%������̹ػ�"
        exit /b
    )
)

if %rest_elapsed% LSS %REST_MINUTES% (
    call :DO_SHUTDOWN "�����ϴιػ�δ��%REST_MINUTES%���ӣ����̹ػ�"
    exit /b
)

if %play_elapsed% GEQ %PLAY_MINUTES% (
    if "%DEBUG_MODE%"=="1" (
        call :LOG "DEBUGģʽ: ����ʱ�䳬��%PLAY_MINUTES%���ӣ����̹ػ�"
    ) else (
        echo %DATE% %TIME% > "%REST_FILE%"
    )
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
