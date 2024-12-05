param (
    [switch]$Debug
)

function Show-Notification {
    [cmdletbinding()]
    Param (
        [string]
        $ToastTitle,
        [string]
        [parameter(ValueFromPipeline)]
        $ToastText
    )

    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
    $Template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)

    $RawXml = [xml] $Template.GetXml()
    ($RawXml.toast.visual.binding.text | Where-object { $_.id -eq "1" }).AppendChild($RawXml.CreateTextNode($ToastTitle)) > $null
    ($RawXml.toast.visual.binding.text | Where-object { $_.id -eq "2" }).AppendChild($RawXml.CreateTextNode($ToastText)) > $null

    $SerializedXml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $SerializedXml.LoadXml($RawXml.OuterXml)

    $Toast = [Windows.UI.Notifications.ToastNotification]::new($SerializedXml)
    $Toast.Tag = "PowerShell"
    $Toast.Group = "PowerShell"
    $Toast.ExpirationTime = [DateTimeOffset]::Now.AddMinutes(1)

    $Notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("PowerShell")
    $Notifier.Show($Toast);
}

function Write-Log {
    Param ([string]$LogString)
    Add-Content $LogFile -value "$(Get-Date): $LogString"
    if ($Debug) {
        Write-Host "$(Get-Date): $LogString"
    }
}

function Invoke-Poweroff {
    param ([string]$reason = "���ڹػ�")
    # Write-Output $reason | Show-Notification
    Write-Log $reason
    if ($Debug) {
        Write-Host "Debugģʽ: ģ��ػ�������ԭ��: $reason" -ForegroundColor Yellow
    } else {
        shutdown.exe /s /t 40 /f /c $reason
    }
}

## �����������ػ�ǰ40�뵹��ʱ��ÿ��21:00-08:00ʱ��κ͹�����17:00��ػ���ÿ��ֻ�ܿ���50���ӣ�ÿ�ιػ���120�����ڲ��ܿ���
$playMinutes = 50
$restMinutes = 120
$AppPath = $PSScriptRoot
$PlayFile = Join-Path $AppPath "child_play.txt"
$RestFile = Join-Path $AppPath "child_rest.txt"
$DisableFile = Join-Path $AppPath "child_disable.txt"
$LogFile = Join-Path $AppPath "child.log"

# Cancel shutdown
if (Test-Path $DisableFile) { return }

$currentTime = Get-Date
$currentHour = $currentTime.ToString('HHmm')

## ҹ��ʱ���ж�(21:00-08:00)
if ($currentHour -lt 800 -or $currentHour -gt 2100) {
    Invoke-Poweroff -reason "����21�㵽����8���ڼ䲻��ʹ�õ���"
    return
}

## ������17:00���ж�
if ((Get-Date).DayOfWeek -in 1..5 -and $currentHour -gt 1700) {
    Invoke-Poweroff -reason "������17�����ʹ�õ���"
    return
}

## �����rest�ļ��������ļ���ʱ���Ƿ�Ϊ120����ǰ
if (Test-Path $RestFile) {
    $lastStopTime = Get-Date (Get-Content $RestFile)
    $timeDiff = ($currentTime - $lastStopTime).TotalMinutes
    if ($Debug) {
        Write-Host "��Ϣʱ����: �ϴ�ֹͣʱ�� $lastStopTime, ����Ϣ $timeDiff ����" -ForegroundColor Cyan
    }
    if ($timeDiff -lt $restMinutes) {
        Invoke-Poweroff -reason "����Ҫ��Ϣ $([math]::Round($restMinutes - $timeDiff)) ����"
        return
    }
}
else {
    # ������Ϣ�ļ�������Ϊ120����ǰ��ʱ��
    $initialRestTime = $currentTime.AddMinutes(-$restMinutes)
    Write-TimeFile -FilePath $RestFile -TimeValue $initialRestTime
}

## �����play�ļ��������ļ���ʱ���Ƿ�Ϊ50����ǰ
if (Test-Path $PlayFile) {
    $playStartTime = Get-Date (Get-Content $PlayFile)
    $playDuration = ($currentTime - $playStartTime).TotalMinutes
    if ($Debug) {
        Write-Host "ʹ��ʱ����: ��ʼʱ�� $playStartTime, ��ʹ�� $playDuration ����" -ForegroundColor Cyan
    }
    ## ���play�ļ���ʱ��Ϊ120����ǰ��������Ϊ��ǰʱ��
    if ($playDuration -gt $restMinutes) {
        Write-TimeFile -FilePath $PlayFile -TimeValue $currentTime
        return
    }
    if ($playDuration -gt $playMinutes) {
        Write-TimeFile -FilePath $RestFile -TimeValue $currentTime
        Invoke-Poweroff -reason "�ѳ�������ʹ��ʱ�� $playMinutes ����"
        return
    }
}
else {
    # ����play�ļ�������Ϊ��ǰʱ��
    Write-TimeFile -FilePath $PlayFile -TimeValue $currentTime
}
