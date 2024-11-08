#Requires -RunAsAdministrator
#Requires -Version 5.1

## �鿴��ǰ��ִ�в���
# Get-ExecutionPolicy -List
## ����ִ�в���ΪҪ��Զ�̽ű�ǩ������ΧΪ��ǰ�û�
# Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

## ���й���½
# irm https://gitee.com/xiagw/deploy.sh/raw/main/bin/ssh.ps1 | iex
## �������й���½
# irm https://github.com/xiagw/deploy.sh/raw/main/bin/ssh.ps1 | iex

## ����windows
## https://github.com/massgravel/Microsoft-Activation-Scripts
# irm https://massgrave.dev/get | iex

<#
.SYNOPSIS
    Windowsϵͳ���ú������װ�ű�
.DESCRIPTION
    �ṩWindowsϵͳ���á�SSH���á������װ�ȹ���
.NOTES
    ����: xiagw
    �汾: 1.0
#>
# �ű������������ʼ
param (
    [string]$ProxyServer = $DEFAULT_PROXY,  # ʹ��Ĭ�ϴ����ַ
    [switch]$UseProxy,
    [string]$Action = "install"  # Ĭ�϶���
)
#region ȫ�ֱ���
# ��������
$SCRIPT_VERSION = "2.0.0"
$DEFAULT_SHELL = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
$DEFAULT_PROXY = "http://192.168.44.11:1080"  # Ĭ�ϴ����ַ
#endregion

#region ������غ���
## ȫ�ִ������ú���
function Set-GlobalProxy {
    param (
        [string]$ProxyServer = $DEFAULT_PROXY,
        [switch]$Enable,
        [switch]$Disable
    )

    $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    $envVars = @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY")

    if ($Enable) {
        # ���ô���
        if (Test-Path $PROFILE) {
            Add-ProxyToProfile -ProxyServer $ProxyServer
        }
        Set-ItemProperty -Path $RegPath -Name ProxyEnable -Value 1
        Set-ItemProperty -Path $RegPath -Name ProxyServer -Value $ProxyServer

        # ���û�������
        foreach ($var in $envVars) {
            Set-Item -Path "env:$var" -Value $ProxyServer
        }

        # ����winget����
        Set-WingetConfig -ProxyServer $ProxyServer -Enable
        Write-Output "Global proxy enabled: $ProxyServer"
    }

    if ($Disable) {
        # �Ƴ�����
        if (Test-Path $PROFILE) {
            Remove-ProxyFromProfile
        }
        Set-ItemProperty -Path $RegPath -Name ProxyEnable -Value 0
        Remove-ItemProperty -Path $RegPath -Name ProxyServer -ErrorAction SilentlyContinue

        # �����������
        foreach ($var in $envVars) {
            Remove-Item -Path "env:$var" -ErrorAction SilentlyContinue
        }

        # ����winget����
        Set-WingetConfig -Disable
        Write-Output "Global proxy disabled"
    }
}

# ��ӵ�PowerShell�����ļ�
function Add-ProxyToProfile {
    param (
        [string]$ProxyServer = $DEFAULT_PROXY
    )

    # ��������ļ��Ƿ����
    if (-not (Test-Path $PROFILE)) {
        New-Item -Type File -Force -Path $PROFILE | Out-Null
    }

    # ��ȡ��������
    $currentContent = Get-Content $PROFILE -Raw
    if (-not $currentContent) {
        $currentContent = ""
    }

    # ׼��Ҫ��ӵĴ�������
    $proxySettings = @"
# ����������
# function Enable-Proxy { Set-GlobalProxy -ProxyServer '$ProxyServer' -Enable }
# function Disable-Proxy { Set-GlobalProxy -Disable }
# ����Ĭ�ϴ���
`$env:HTTP_PROXY = '$ProxyServer'
`$env:HTTPS_PROXY = '$ProxyServer'
`$env:ALL_PROXY = '$ProxyServer'
"@

    # ����Ƿ��Ѿ������κδ�������
    $proxyPatterns = @(
        [regex]::Escape($proxySettings),
        "HTTP_PROXY = ['`"]$([regex]::Escape($ProxyServer))['`"]",
        "HTTPS_PROXY = ['`"]$([regex]::Escape($ProxyServer))['`"]",
        "ALL_PROXY = ['`"]$([regex]::Escape($ProxyServer))['`"]"
    )

    foreach ($pattern in $proxyPatterns) {
        if ($currentContent -match $pattern) {
            Write-Output "Proxy settings already exist in PowerShell profile"
            return
        }
    }

    # ���û���ҵ��κδ������ã�������µ�����
    Add-Content -Path $PROFILE -Value "`n$proxySettings"
    Write-Output "Proxy settings added to PowerShell profile"
}

function Remove-ProxyFromProfile {
    # ��������ļ��Ƿ����
    if (-not (Test-Path $PROFILE)) {
        Write-Output "PowerShell profile does not exist"
        return
    }

    # ��ȡ��������
    $content = Get-Content $PROFILE -Raw

    if (-not $content) {
        Write-Output "PowerShell profile is empty"
        return
    }

    # �Ƴ������������
    $newContent = $content -replace "(?ms)# ����������.*?# ����Ĭ�ϴ���.*?\n.*?\n.*?\n.*?\n", ""

    # ��������б仯�������ļ�
    if ($newContent -ne $content) {
        $newContent.Trim() | Set-Content $PROFILE
        Write-Output "Proxy settings removed from PowerShell profile"
    }
    else {
        Write-Output "No proxy settings found in PowerShell profile"
    }
}
#endregion

#region SSH��غ���
## ��װopenssh
function Install-OpenSSH {
    param ([switch]$Force)

    Write-Output "Installing and configuring OpenSSH..."

    # ��װ OpenSSH ���
    Get-WindowsCapability -Online | Where-Object {
        $_.Name -like "OpenSSH*" -and ($_.State -eq "NotPresent" -or $Force)
    } | ForEach-Object {
        Add-WindowsCapability -Online -Name $_.Name
    }

    # ���ò���������
    $services = @{
        sshd = @{ StartupType = 'Automatic' }
        'ssh-agent' = @{ StartupType = 'Automatic' }
    }

    foreach ($svc in $services.Keys) {
        Set-Service -Name $svc -StartupType $services[$svc].StartupType
        Start-Service $svc -ErrorAction SilentlyContinue
    }

    # ���÷���ǽ
    if (-not (Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
            -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
    }

    # ���� PowerShell ΪĬ�� shell
    New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell `
        -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Force

    # ���� SSH ��Կ
    $sshPaths = @{
        UserKeys = "$HOME\.ssh\authorized_keys"
        AdminKeys = "C:\ProgramData\ssh\administrators_authorized_keys"
        Config = "C:\ProgramData\ssh\sshd_config"
    }

    # ���������� SSH Ŀ¼���ļ�
    foreach ($path in $sshPaths.Values) {
        if (-not (Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }
    }

    # ���� sshd_config
    $configContent = Get-Content $sshPaths.Config -Raw
    @('Match Group administrators', 'AuthorizedKeysFile __PROGRAMDATA__') | ForEach-Object {
        $configContent = $configContent -replace $_, "#$_"
    }
    $configContent | Set-Content $sshPaths.Config

    # ��ȡ������ SSH ��Կ
    try {
        $keys = @(
            if (Test-Path $sshPaths.UserKeys) { Get-Content $sshPaths.UserKeys }
            (Invoke-RestMethod 'https://api.github.com/users/xiagw/keys').key
        ) | Select-Object -Unique

        $keys | Set-Content $sshPaths.UserKeys
        Copy-Item $sshPaths.UserKeys $sshPaths.AdminKeys -Force

        # ���ù���Ա��Կ�ļ�Ȩ��
        icacls.exe $sshPaths.AdminKeys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"

        Write-Output "SSH keys configured (Total: $($keys.Count))"
    }
    catch {
        Write-Warning "Failed to fetch SSH keys: $_"
    }

    # ����������Ӧ�ø���
    Restart-Service sshd
    Write-Output "OpenSSH installation completed!"
}
#endregion

## ��װ oh my posh
function Install-OhMyPosh {
    param (
        [switch]$Force,
        [string]$Theme = "ys"
    )

    Write-Output "Setting up Oh My Posh..."

    # ��ʼ�������ļ�
    if (-not (Test-Path $PROFILE) -or $Force) {
        New-Item -Type File -Force -Path $PROFILE | Out-Null
        @(
            'Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete',
            'Set-PSReadLineOption -EditMode Emacs'
        ) | Set-Content $PROFILE
    }

    # ��װ Oh My Posh
    if ($Force -or -not (Get-Command oh-my-posh.exe -ErrorAction SilentlyContinue)) {
        try {
            Set-ExecutionPolicy Bypass -Scope Process -Force
            $installCmd = if ($ProxyServer -match "china|cn") {
                "scoop install https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/oh-my-posh.json"
            } else {
                "winget install JanDeDobbeleer.OhMyPosh --source winget"
            }
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://ohmyposh.dev/install.ps1'))
        }
        catch {
            Write-Error "Failed to install Oh My Posh: $_"
            return
        }
    }

    # ��������
    if (Get-Command oh-my-posh.exe -ErrorAction SilentlyContinue) {
        # ��ȡ��������
        $currentContent = Get-Content $PROFILE -Raw
        if (-not $currentContent) {
            $currentContent = ""
        }

        # ׼��Ҫ��ӵ� Oh My Posh ����
        $poshConfig = 'oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH/' + $Theme + '.omp.json" | Invoke-Expression'

        # ����Ƿ��Ѵ��� Oh My Posh ����
        $poshPattern = 'oh-my-posh init pwsh --config.*\.omp\.json.*Invoke-Expression'
        if ($currentContent -match $poshPattern) {
            # ������ھ����ã��滻Ϊ������
            $newContent = $currentContent -replace $poshPattern, $poshConfig
            $newContent | Set-Content $PROFILE
            Write-Output "Oh My Posh theme updated to: $Theme"
        } else {
            # ��������ڣ����������
            Add-Content -Path $PROFILE -Value $poshConfig
            Write-Output "Oh My Posh theme configured: $Theme"
        }

        Write-Output "Oh My Posh $(oh-my-posh version) configured with theme: $Theme"
        Write-Output "Please reload profile: . `$PROFILE"
    }
}

# ʹ��ʾ��������ע�͵�����
# ������װ
# Install-OhMyPosh

# ǿ�����°�װ��ʹ�ò�ͬ����
# Install-OhMyPosh -Force -Theme "agnoster"

#region ����������غ���
## ��װscoop, �ǹ���Ա
# irm get.scoop.sh | iex
# win10 ��װscoop����ȷ���� | impressionyang�ĸ��˷���վ
# https://impressionyang.gitee.io/2021/02/15/win10-install-scoop/

# Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
# Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
function Install-Scoop {
    param ([switch]$Force)

    if ((Get-Command scoop -ErrorAction SilentlyContinue) -and -not $Force) {
        Write-Output "Scoop already installed. Use -Force to reinstall."
        return
    }

    try {
        # ���û���
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        $env:HTTPS_PROXY = $ProxyServer

        # ѡ��װԴ����װ
        $installUrl = if ($ProxyServer -match "china|cn") {
            "https://gitee.com/glsnames/scoop-installer/raw/master/bin/install.ps1"
        } else {
            "https://get.scoop.sh"
        }

        Invoke-Expression (New-Object Net.WebClient).DownloadString($installUrl)

        # ��װ�������
        @("extras", "versions") | ForEach-Object { scoop bucket add $_ }
        scoop install git 7zip

        Write-Output "Scoop $(scoop --version) installed successfully!"
    }
    catch {
        Write-Error "Scoop installation failed: $_"
    }
    finally {
        Remove-Item Env:\HTTPS_PROXY -ErrorAction SilentlyContinue
    }
}
#endregion


# ʹ��ʾ��������ע�͵���:
# ��ͨ��װ
# Install-Scoop

# ǿ�����°�װ
# Install-Scoop -Force


## ���� winget
function Set-WingetConfig {
    param (
        [string]$ProxyServer,
        [switch]$Enable,
        [switch]$Disable
    )

    $settingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json"
    New-Item -ItemType Directory -Force -Path (Split-Path $settingsPath) | Out-Null

    # ���ػ򴴽�����
    $settings = if (Test-Path $settingsPath) {
        Get-Content $settingsPath -Raw | ConvertFrom-Json
    } else {
        @{ "$schema" = "https://aka.ms/winget-settings.schema.json" }
    }

    # ��������
    if ($Enable -and $ProxyServer) {
        $settings.network = @{ downloader = "wininet"; proxy = $ProxyServer }
        Write-Output "Enabled winget proxy: $ProxyServer"
    } elseif ($Disable -and $settings.network) {
        $settings.PSObject.Properties.Remove('network')
        Write-Output "Disabled winget proxy"
    }

    # ���沢��ʾ����
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath
    Get-Content $settingsPath

    # ����winget
    Write-Output "Testing winget..."
    winget source update
}
# ʹ��ʾ����
# ����winget����
# Set-WingetConfig -ProxyServer "http://192.168.44.11:1080" -Enable

# ����winget����
# Set-WingetConfig -Disable


#region �ն˺�Shell��غ���
## windows server 2022��װWindows Terminal
# method 1 winget install --id Microsoft.WindowsTerminal -e
# method 2 scoop install windows-terminal
# scoop update windows-terminal
function Install-WindowsTerminal {
    param ([switch]$Upgrade)

    # ȷ���Ѱ�װscoop
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Output "Installing Scoop first..."
        Install-Scoop
    }

    # ȷ��extras bucket�����
    if (-not (Test-Path "$(scoop prefix scoop)\buckets\extras")) {
        Write-Output "Adding extras bucket..."
        scoop bucket add extras
    }

    try {
        if ($Upgrade) {
            Write-Output "Upgrading Windows Terminal..."
            scoop update windows-terminal
        } else {
            # ����Ƿ��Ѱ�װ
            $isInstalled = Get-Command wt -ErrorAction SilentlyContinue
            if ($isInstalled) {
                Write-Output "Windows Terminal is already installed. Use -Upgrade to upgrade."
                return
            }

            Write-Output "Installing Windows Terminal via Scoop..."
            scoop install windows-terminal
        }

        # ���� Terminal
        $settingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
        if (Test-Path $settingsPath) {
            Copy-Item $settingsPath "$settingsPath.backup"
            $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
            $settings.defaultProfile = "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}"
            $settings.profiles.defaults = @{
                fontFace = "Cascadia Code"
                fontSize = 12
                colorScheme = "One Half Dark"
                useAcrylic = $true
                acrylicOpacity = 0.9
            }
            $settings | ConvertTo-Json -Depth 32 | Set-Content $settingsPath
        }

        Write-Output "Windows Terminal $(scoop info windows-terminal | Select-String 'Version:' | ForEach-Object { $_.ToString().Split(':')[1].Trim() }) installed successfully!"
    }
    catch {
        Write-Error "Installation failed: $_"
    }
}

function Install-PowerShell7 {
    param (
        [switch]$Force,
        [string]$Version = "latest"
    )

    # ��鰲װ״̬
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh -and -not $Force) {
        Write-Output "PowerShell $(&pwsh -Version) already installed. Use -Force to reinstall."
        return
    }

    try {
        if ($Version -eq "latest") {
            # ʹ��winget��װ���°汾
            winget install --id Microsoft.Powershell --source winget
        } else {
            # ʹ��MSI��װ�ض��汾
            $msiPath = Join-Path $env:TEMP "PowerShell7\PowerShell-$Version-win-x64.msi"
            New-Item -ItemType Directory -Force -Path (Split-Path $msiPath) | Out-Null

            # ���ز���װ
            Invoke-WebRequest -Uri "https://github.com/PowerShell/PowerShell/releases/download/v$Version/$($msiPath | Split-Path -Leaf)" -OutFile $msiPath
            Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /quiet ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1" -Wait
            Remove-Item -Recurse -Force (Split-Path $msiPath) -ErrorAction SilentlyContinue
        }

        # ��֤������
        if ($newPwsh = Get-Command pwsh -ErrorAction SilentlyContinue) {
            $pwshPath = Split-Path $newPwsh.Source -Parent
            if ($env:Path -notlike "*$pwshPath*") {
                [Environment]::SetEnvironmentVariable("Path", "$([Environment]::GetEnvironmentVariable('Path', 'User'));$pwshPath", "User")
            }
            $Force -and (New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value $newPwsh.Source -Force)
            Write-Output "PowerShell $(&pwsh -Version) installed successfully!"
        }
    }
    catch {
        Write-Error "Installation failed: $_"
    }
}

# ʹ��ʾ����
# ��װ���°汾
# Install-PowerShell7

# ǿ�����°�װ
# Install-PowerShell7 -Force

# ��װ�ض��汾
# Install-PowerShell7 -Version "7.3.4"

#region ϵͳ��������غ���
function Install-RSAT {
    param (
        [switch]$Force,
        [string[]]$Features = @('*'),
        [switch]$ListOnly
    )

    # ��ȡRSAT����
    $rsatFeatures = Get-WindowsCapability -Online | Where-Object Name -like "Rsat.Server*"
    if (-not $rsatFeatures) {
        Write-Error "No RSAT features found"
        return
    }

    # �г����ܻ�װ
    if ($ListOnly) {
        $rsatFeatures | Format-Table Name, State
        return
    }

    # ɸѡ����װ����
    $toInstall = $rsatFeatures | Where-Object {
        ($_.State -eq "NotPresent" -or $Force) -and
        ($Features -eq '*' -or $Features | Where-Object { $_.Name -like "Rsat.Server.$_" })
    }

    if ($toInstall) {
        $total = $toInstall.Count
        $toInstall | ForEach-Object -Begin {
            $i = 0
        } {
            $i++
            Write-Progress -Activity "Installing RSAT" -Status $_.Name -PercentComplete ($i/$total*100)
            try {
                Add-WindowsCapability -Online -Name $_.Name
            } catch {
                Write-Error "Failed to install $($_.Name): $_"
            }
        }
        Write-Progress -Activity "Installing RSAT" -Completed
    }

    # ��ʾ���
    $installed = @(Get-WindowsCapability -Online | Where-Object {
        $_.Name -like "Rsat.Server*" -and $_.State -eq "Installed"
    }).Count
    Write-Output "RSAT features installed: $installed"
}
#endregion
# ʹ��ʾ����
# �г����п��õ�RSAT����
# Install-RSAT -ListOnly

# ��װ����RSAT����
# Install-RSAT

# ��װ�ض����ܣ�����DNS��DHCP��
# Install-RSAT -Features 'Dns','Dhcp'

# ǿ�����°�װ���й���
# Install-RSAT -Force

# ǿ�����°�װ�ض�����
# Install-RSAT -Features 'Dns','Dhcp' -Force

#region �Զ���¼��غ���
function Set-WindowsAutoLogin {
    param (
        [Parameter(Mandatory=$true)][string]$Username,
        [Parameter(Mandatory=$true)][string]$Password,
        [switch]$Disable
    )

    $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    $RegSettings = @{
        AutoAdminLogon = if ($Disable) { "0" } else { "1" }
        DefaultUsername = $Username
        DefaultPassword = $Password
        AutoLogonCount = "0"
    }

    try {
        if ($Disable) {
            Write-Output "Disabling Windows Auto Login..."
            Set-ItemProperty -Path $RegPath -Name "AutoAdminLogon" -Value "0" -Type String
            "DefaultUsername", "DefaultPassword" | ForEach-Object {
                Remove-ItemProperty -Path $RegPath -Name $_ -ErrorAction SilentlyContinue
            }
        } else {
            Write-Output "Configuring Windows Auto Login for $Username..."
            $RegSettings.Keys | ForEach-Object {
                Set-ItemProperty -Path $RegPath -Name $_ -Value $RegSettings[$_] -Type $(if ($_ -eq "AutoLogonCount") {"DWord"} else {"String"})
            }
            Write-Warning "System will auto login as $Username after restart"
        }
        $true
    }
    catch {
        Write-Error "Auto Login configuration failed: $_"
        $false
    }
}

# ʹ��ʾ����
# �����Զ���¼
# Set-WindowsAutoLogin -Username "Administrator" -Password "YourPassword"

# �����Զ���¼
# Set-WindowsAutoLogin -Username "Administrator" -Password "YourPassword" -Disable

# �Ӽ����ļ���ȡƾ�ݲ������Զ���¼
function Set-WindowsAutoLoginFromFile {
    param (
        [Parameter(Mandatory=$true)][string]$CredentialFile,
        [switch]$Disable
    )

    try {
        # ��֤����ȡƾ��
        if (-not (Test-Path $CredentialFile)) { throw "Credential file not found" }
        $cred = Get-Content $CredentialFile | ConvertFrom-Json
        if (-not ($cred.username -and $cred.password)) { throw "Invalid credential format" }

        # �����Զ���¼
        Set-WindowsAutoLogin -Username $cred.username -Password $cred.password -Disable:$Disable
    }
    catch {
        Write-Error "Failed to configure auto login: $_"
        $false
    }
}

# ʹ��ʾ����
# ����ƾ���ļ�
# @{username="Administrator"; password="YourPassword"} | ConvertTo-Json | Out-File "C:\credentials.json"

# ���ļ������Զ���¼
# Set-WindowsAutoLoginFromFile -CredentialFile "C:\credentials.json"

# ���ļ������Զ���¼
# Set-WindowsAutoLoginFromFile -CredentialFile "C:\credentials.json" -Disable

function Set-SecureAutoLogin {
    param (
        [Parameter(Mandatory=$true)][string]$Username,
        [Parameter(ParameterSetName="SetLogin")][switch]$Secure,
        [Parameter(ParameterSetName="DisableLogin")][switch]$Disable
    )

    $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    $CredTarget = "WindowsAutoLogin"
    $ScriptPath = "$env:ProgramData\AutoLogin\AutoLogin.ps1"

    try {
        if ($Disable) {
            # �����Զ���¼
            Set-ItemProperty -Path $RegPath -Name "AutoAdminLogon" -Value "0" -Type String
            Remove-ItemProperty -Path $RegPath -Name "DefaultUsername" -ErrorAction SilentlyContinue
            cmdkey /delete:$CredTarget
            Unregister-ScheduledTask -TaskName "SecureAutoLogin" -Confirm:$false -ErrorAction SilentlyContinue
            return $true
        }

        if ($Secure) {
            # ��ȡƾ�ݲ��洢
            $SecurePass = Read-Host -Prompt "Enter password for $Username" -AsSecureString
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
            $PlainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
            cmdkey /generic:$CredTarget /user:$Username /pass:$PlainPass | Out-Null

            # ����ע���
            @{
                "AutoAdminLogon" = "1"
                "DefaultUsername" = $Username
                "DefaultDomainName" = $env:COMPUTERNAME
            }.GetEnumerator() | ForEach-Object {
                Set-ItemProperty -Path $RegPath -Name $_.Key -Value $_.Value -Type String
            }

            # �����������Զ���¼�ű�
            New-Item -ItemType Directory -Force -Path (Split-Path $ScriptPath) | Out-Null
            @"
`$cred = cmdkey /list | Where-Object { `$_ -like "*$CredTarget*" }
if (`$cred) {
    `$username = '$Username'
    `$password = (cmdkey /list | Where-Object { `$_ -like "*$CredTarget*" } | Select-String 'User:').ToString().Split(':')[1].Trim()
}
"@ | Set-Content $ScriptPath

            # ���ýű�Ȩ�޺ͼƻ�����
            $Acl = Get-Acl $ScriptPath
            $Ar = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "Allow")
            $Acl.SetAccessRule($Ar)
            Set-Acl $ScriptPath $Acl

            $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
            Register-ScheduledTask -TaskName "SecureAutoLogin" -Action $Action `
                -Trigger (New-ScheduledTaskTrigger -AtStartup) `
                -Principal (New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest) `
                -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries) -Force

            Write-Warning "System will auto login as $Username after restart"
            return $true
        }
    }
    catch {
        Write-Error "Secure Auto Login configuration failed: $_"
        return $false
    }
}
#endregion
# ʹ��ʾ����
# ���ð�ȫ���Զ���¼
# Set-SecureAutoLogin -Username "Administrator" -Secure

# �����Զ���¼
# Set-SecureAutoLogin -Username "Administrator" -Disable

#region ������
# ������ - �ڽű�����ʱ����
function Clear-GlobalSettings {
    $UseProxy -and (Set-GlobalProxy -Disable)
}
#endregion


function Show-ScriptHelp {
    @"
Windows System Configuration Script v$SCRIPT_VERSION

�����÷�:
    irm https://gitee.com/xiagw/deploy.sh/raw/main/bin/ssh.ps1 -OutFile ssh.ps1

����:
1. ������װ: .\ssh.ps1 [-Action install]
2. ʹ�ô���: .\ssh.ps1 -UseProxy [-ProxyServer "http://proxy:8080"]
3. ��ʾ����: .\ssh.ps1 -Action help[|-detailed]
4. �����ն�: .\ssh.ps1 -Action upgrade

��������:
SSH:        -Action ssh[-force]
Terminal:   -Action terminal[-upgrade]
PowerShell: -Action pwsh[-7.3.4]
Oh My Posh: -Action posh[-theme-agnoster]
Scoop:      -Action scoop[-force]
RSAT:       -Action rsat[-dns,dhcp|-list]
AutoLogin:  -Action autologin-[Username|disable]

����:
    -Action      : ִ�в���
    -UseProxy    : ���ô���
    -ProxyServer : �����ַ (Ĭ��: $DEFAULT_PROXY)
"@ | Write-Output
}

# ʹ��ʾ����
# Show-ScriptHelp              # ��ʾ��������
# Show-ScriptHelp -Detailed    # ��ʾ��ϸ����

#region ��ִ�д���
# ��ʼ������
$UseProxy -and (Set-GlobalProxy -ProxyServer $ProxyServer -Enable)

# ִ�в���
$actions = @{
    'help(-detailed)?$' = { Show-ScriptHelp -Detailed:($Action -eq "help-detailed") }
    '^install$' = { Install-OpenSSH }
    '^ssh(-force)?$' = { Install-OpenSSH -Force:($Action -eq "ssh-force") }
    '^upgrade$' = { Install-WindowsTerminal -Upgrade }
    '^terminal(-upgrade)?$' = { Install-WindowsTerminal -Upgrade:($Action -eq "terminal-upgrade") }
    '^pwsh(-[\d\.]+)?$' = {
        Install-PowerShell7 -Version $(if ($Action -eq "pwsh") {"latest"} else {$Action -replace "^pwsh-",""})
    }
    '^posh(-theme-.*)?$' = {
        Install-OhMyPosh -Theme $(if ($Action -eq "posh") {"ys"} else {$Action -replace "^posh-theme-",""})
    }
    '^scoop(-force)?$' = { Install-Scoop -Force:($Action -eq "scoop-force") }
    '^rsat(-list|-.*)?$' = {
        switch -Regex ($Action) {
            '^rsat-list$' { Install-RSAT -ListOnly }
            '^rsat-(.+)$' { Install-RSAT -Features ($Action -replace "^rsat-","").Split(',') }
            default { Install-RSAT }
        }
    }
    '^autologin-(.+)$' = {
        $username = $Action -replace "^autologin-",""
        Set-SecureAutoLogin -Username $(if ($username -eq "disable") {"Administrator"} else {$username}) `
            -$(if ($username -eq "disable") {"Disable"} else {"Secure"})
    }
}

# ִ��ƥ��Ĳ�������ʾ����
$executed = $false
foreach ($pattern in $actions.Keys) {
    if ($Action -match $pattern) {
        & $actions[$pattern]
        $executed = $true
        break
    }
}

if (-not $executed) {
    Write-Output "Unknown action: $Action"
    Show-ScriptHelp
}

# ע���������
$PSDefaultParameterValues['*:ProxyServer'] = $ProxyServer
Register-EngineEvent PowerShell.Exiting -Action { Clear-GlobalSettings } | Out-Null
#endregion

# git log�ʤɤΥޥ���Х������֤��ʾ�����뤿�� (�}���ֺ���)
# $env:LESSCHARSET = "utf-8"

## ��������
# Set-PSReadlineOption -BellStyle None

## �Ěs����
# scoop install fzf gawk
# Set-PSReadLineKeyHandler -Chord Ctrl+r -ScriptBlock {
#     Set-Alias awk $HOME\scoop\apps\gawk\current\bin\awk.exe
#     $command = Get-Content (Get-PSReadlineOption).HistorySavePath | awk '!a[$0]++' | fzf --tac
#     [Microsoft.PowerShell.PSConsoleReadLine]::Insert($command)
# }
