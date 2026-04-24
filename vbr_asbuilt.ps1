<#
.SYNOPSIS
Automates deployment, validation and execution of AsBuiltReport for Veeam Backup & Replication.

.DESCRIPTION
This script validates the environment, installs required modules (online or offline),
handles PowerShell compatibility (5.1 and 7+), connects to Veeam Backup & Replication,
generates configuration files and executes the AsBuiltReport.

Includes:
- Environment validation
- Online/offline module handling
- PowerShell relaunch logic
- Veeam connectivity and version detection
- Execution summary and structured logging
- NuGet provider handling for online and offline execution

.PARAMETER relaunched
Internal control parameter used when the script relaunches itself in PowerShell 7.

.PARAMETER VBRServer
Target Veeam Backup & Replication server. Default is localhost.

.PARAMETER Mode
Execution mode:
- Full: normal validation and execution flow
- DownloadOnly: download required modules only

If not specified, the script prompts at startup.

.PARAMETER ModulesPath
Path used to store or read offline modules.
Default: script_path\modules

.PARAMETER OutputPath
Directory used to store generated reports.
Default: script_path\report

.PARAMETER SkipVersionPrompt
If specified, the script will not prompt when Veeam v13+ is detected.

.EXAMPLE
.\vbr_asbuilt.ps1

Runs the script interactively.

.EXAMPLE
.\vbr_asbuilt.ps1 -Mode DownloadOnly

Downloads required modules to the offline modules folder.

.EXAMPLE
.\vbr_asbuilt.ps1 -VBRServer vbr01.contoso.local -OutputPath C:\Temp\report

Runs the full workflow against a remote VBR server.

.EXAMPLE
Get-Help .\vbr_asbuilt.ps1 -Detailed

Shows detailed help.

.NOTES
Author  : Juliano Cunha
GitHub  : https://github.com/julianscunha


.REQUIREMENTS
- Windows PowerShell 5.1 or PowerShell 7+
- Veeam Backup & Replication installed
- Administrative privileges

.LICENSE
MIT License
#>

param(
    [int]$relaunched = 0,
    [string]$VBRServer = "localhost",
    [ValidateSet("Full","DownloadOnly")]
    [string]$Mode,
    [string]$ModulesPath,
    [string]$OutputPath,
    [switch]$SkipVersionPrompt
)

$ScriptVersion = "v0.1.0"

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ConfirmPreference = 'None'

try {
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [Console]::InputEncoding  = $utf8NoBom
        [Console]::OutputEncoding = $utf8NoBom
        $OutputEncoding = $utf8NoBom
    }
    else {
        $defaultEncoding = [System.Text.Encoding]::GetEncoding(850)
        [Console]::InputEncoding  = $defaultEncoding
        [Console]::OutputEncoding = $defaultEncoding
        $OutputEncoding = $defaultEncoding
    }
}
catch {
}

Clear-Host

$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$logFile = Join-Path $ScriptRoot "AsBuiltReport_Veeam.log"
$offlineModulesRoot = if ([string]::IsNullOrWhiteSpace($ModulesPath)) { Join-Path $ScriptRoot "modules" } else { $ModulesPath }
$defaultReportOutput = if ([string]::IsNullOrWhiteSpace($OutputPath)) { Join-Path $ScriptRoot "report" } else { $OutputPath }
$NuGetMinimumVersion = [version]"2.8.5.201"

$ExecutionSummary = [ordered]@{
    PowerShell              = "PENDING"
    Connectivity            = "PENDING"
    NuGetGallery            = "PENDING"
    Modules                 = "PENDING"
    VeeamPowerShell         = "PENDING"
    VeeamConnection         = "PENDING"
    VeeamVersion            = "PENDING"
    ReportConfig            = "PENDING"
    ReportExecution         = "PENDING"
    FinalStatus             = "PENDING"
    FinalMessage            = ""
}

if ($relaunched -eq 0) {
    if (Test-Path $logFile) {
        Remove-Item $logFile -Force -ErrorAction SilentlyContinue
    }
}

$ConsoleVisibleLevels = @("INFO", "WARNING", "ERROR")

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO","SUCCESS","WARNING","ERROR","DEBUG")][string]$Level = "INFO",
        [int]$Indent = 0
    )

    $prefix = " " * ($Indent * 2)

    switch ($Level) {
        "INFO"    { $tag = "[INFO]    " }
        "SUCCESS" { $tag = "[OK]      " }
        "WARNING" { $tag = "[WARN]    " }
        "ERROR"   { $tag = "[ERROR]   " }
        "DEBUG"   { $tag = "[DEBUG]   " }
    }

    $line = "{0} {1}{2}{3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $tag, $prefix, $Message

    if ($ConsoleVisibleLevels -contains $Level) {
        Write-Host $line
    }

    $line | Out-File -FilePath $logFile -Append -Encoding utf8
}

function Write-Section {
    param([Parameter(Mandatory)][string]$Title)
    Write-Log ("===== {0} =====" -f $Title) "INFO" 0
}

function Confirm-Action {
    param([Parameter(Mandatory)][string]$Message)
    $response = Read-Host "$Message (Y/N)"
    return $response -match '^[Yy]$'
}

function Pause-End {
    Read-Host "Pressione ENTER para finalizar"
}

function Update-Summary {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value
    )
    $ExecutionSummary[$Key] = $Value
}

function Write-FinalSummary {
    Write-Section "RESUMO FINAL"

    $items = @(
        "PowerShell","Connectivity","NuGetGallery","Modules","VeeamPowerShell",
        "VeeamConnection","VeeamVersion","ReportConfig","ReportExecution","FinalStatus"
    )

    foreach ($item in $items) {
        $value = $ExecutionSummary[$item]
        $level = switch ($value) {
            "OK"        { "INFO" }
            "WARNING"   { "WARNING" }
            "FAILED"    { "ERROR" }
            "SKIPPED"   { "WARNING" }
            default     { "INFO" }
        }

        Write-Log ("{0}: {1}" -f $item, $value) $level 1
    }

    if (-not [string]::IsNullOrWhiteSpace($ExecutionSummary.FinalMessage)) {
        Write-Log ("Mensagem final: {0}" -f $ExecutionSummary.FinalMessage) "INFO" 1
    }
}

function Stop-WithFailure {
    param(
        [Parameter(Mandatory)][string]$SummaryKey,
        [Parameter(Mandatory)][string]$Message
    )

    Update-Summary -Key $SummaryKey -Value "FAILED"
    Update-Summary -Key "FinalStatus" -Value "FAILED"
    Update-Summary -Key "FinalMessage" -Value $Message

    Write-Log $Message "ERROR" 1
    Write-FinalSummary
    Pause-End
    exit
}

function Get-ExecutionMode {
    param([string]$CurrentMode)

    if (-not [string]::IsNullOrWhiteSpace($CurrentMode)) {
        return $CurrentMode
    }

    Write-Section "MODO DE EXECUÇÃO"
    Write-Log "Selecione o modo desejado:" "INFO" 1
    Write-Log "1 - Execução normal (validação + relatório)" "INFO" 2
    Write-Log "2 - Somente baixar pacotes" "INFO" 2

    do {
        $choice = Read-Host "Opção [1/2]"
        switch ($choice) {
            "1" { return "Full" }
            "2" { return "DownloadOnly" }
            default { Write-Log "Opção inválida. Informe 1 ou 2." "WARNING" 1 }
        }
    } while ($true)
}

function Test-InternetConnectivity {
    $targets = @("https://www.powershellgallery.com","https://www.microsoft.com")

    foreach ($target in $targets) {
        try {
            Invoke-WebRequest -Uri $target -UseBasicParsing -TimeoutSec 5 | Out-Null
            return $true
        }
        catch {
        }
    }

    return $false
}

function Get-LatestAvailableModule {
    param([Parameter(Mandatory)][string]$Name)

    return Get-Module -ListAvailable -Name $Name |
        Sort-Object Version -Descending |
        Select-Object -First 1
}

function Ensure-ModuleImported {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string[]]$RequiredCommands = @()
    )

    $loaded = Get-Module -Name $Name
    if (-not $loaded) { return $false }

    foreach ($cmd in $RequiredCommands) {
        if (-not (Get-Command -Name $cmd -ErrorAction SilentlyContinue)) {
            return $false
        }
    }

    return $true
}

function Get-PreferredUserModulePath {
    $modulePaths = $env:PSModulePath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    Write-Log "PSModulePath detectado para seleção do destino de módulos:" "DEBUG" 2
    foreach ($path in $modulePaths) {
        Write-Log $path "DEBUG" 3
    }

    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $preferred = $modulePaths | Where-Object {
            $_ -match '[\\/](Documents|Documentos)[\\/]PowerShell[\\/]Modules$'
        } | Select-Object -First 1

        if ($preferred) { return $preferred }
    }

    $preferred = $modulePaths | Where-Object {
        $_ -match '[\\/](Documents|Documentos)[\\/]WindowsPowerShell[\\/]Modules$'
    } | Select-Object -First 1

    if ($preferred) { return $preferred }

    return $null
}

function Validate-PowerShellGetAndGallery {
    Write-Log "Validando PowerShellGet / PSGallery" "INFO" 1

    try {
        $powerShellGet = Get-Module -ListAvailable -Name PowerShellGet |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if ($powerShellGet) {
            Write-Log ("PowerShellGet encontrado: v{0}" -f $powerShellGet.Version) "SUCCESS" 2
        }
        else {
            throw "PowerShellGet não localizado em ListAvailable."
        }

        $gallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if (-not $gallery) {
            throw "PSGallery não encontrada."
        }

        if ($gallery.InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
            $gallery = Get-PSRepository -Name PSGallery -ErrorAction Stop
        }

        Write-Log ("PSGallery validada. Policy: {0}" -f $gallery.InstallationPolicy) "SUCCESS" 2
        return $true
    }
    catch {
        Write-Log ("Falha na validação de PowerShellGet/PSGallery: {0}" -f $_.Exception.Message) "ERROR" 2
        return $false
    }
}

function Get-NuGetProviderRoots {
    $roots = @()

    if ($env:LOCALAPPDATA) {
        $roots += (Join-Path $env:LOCALAPPDATA "PackageManagement\ProviderAssemblies\NuGet")
    }

    if ($env:ProgramFiles) {
        $roots += (Join-Path $env:ProgramFiles "PackageManagement\ProviderAssemblies\NuGet")
    }

    return $roots | Select-Object -Unique
}

function Get-LatestAvailableNuGetProvider {
    try {
        $providers = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue
        if (-not $providers) { return $null }

        return $providers |
            Sort-Object {[version]$_.Version} -Descending |
            Select-Object -First 1
    }
    catch {
        return $null
    }
}

function Get-LatestInstalledNuGetProviderFolder {
    $candidateFolders = @()

    foreach ($root in (Get-NuGetProviderRoots)) {
        if (Test-Path $root) {
            $dirs = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue
            foreach ($dir in $dirs) {
                try {
                    $version = [version]$dir.Name
                    $candidateFolders += [pscustomobject]@{
                        Version = $version
                        Path    = $dir.FullName
                    }
                }
                catch {
                }
            }
        }
    }

    return $candidateFolders |
        Sort-Object Version -Descending |
        Select-Object -First 1
}

function Get-OfflineNuGetProviderFolder {
    param(
        [Parameter(Mandatory)][string]$ModulesRoot,
        [Parameter(Mandatory)][version]$RequiredVersion
    )

    $nugetRoot = Join-Path $ModulesRoot "NuGet"
    if (-not (Test-Path $nugetRoot)) {
        return $null
    }

    $candidateFolders = @()
    $dirs = Get-ChildItem -Path $nugetRoot -Directory -ErrorAction SilentlyContinue

    foreach ($dir in $dirs) {
        try {
            $version = [version]$dir.Name
            if ($version -ge $RequiredVersion) {
                $candidateFolders += [pscustomobject]@{
                    Version = $version
                    Path    = $dir.FullName
                }
            }
        }
        catch {
        }
    }

    return $candidateFolders |
        Sort-Object Version -Descending |
        Select-Object -First 1
}

function Import-NuGetProviderToSession {
    param(
        [Parameter(Mandatory)][version]$RequiredVersion
    )

    try {
        $provider = Get-LatestAvailableNuGetProvider
        if (-not $provider) { return $false }

        if ([version]$provider.Version -lt $RequiredVersion) { return $false }

        Import-PackageProvider -Name NuGet -RequiredVersion $provider.Version -Force -ErrorAction Stop | Out-Null
        Write-Log ("NuGet provider importado na sessão: v{0}" -f $provider.Version) "SUCCESS" 2
        return $true
    }
    catch {
        Write-Log ("Falha ao importar NuGet provider na sessão: {0}" -f $_.Exception.Message) "WARNING" 2
        return $false
    }
}

function Copy-NuGetProviderFolder {
    param(
        [Parameter(Mandatory)][string]$SourceFolder,
        [Parameter(Mandatory)][string]$DestinationRoot
    )

    $providerVersion = Split-Path $SourceFolder -Leaf
    $destinationVersionPath = Join-Path $DestinationRoot $providerVersion

    if (-not (Test-Path $DestinationRoot)) {
        New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
    }

    if (Test-Path $destinationVersionPath) {
        Remove-Item $destinationVersionPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    Copy-Item -Path $SourceFolder -Destination $destinationVersionPath -Recurse -Force -ErrorAction Stop
    return $destinationVersionPath
}

function Promote-NuGetProviderToSystem {
    param(
        [Parameter(Mandatory)][string]$SourceFolder,
        [Parameter(Mandatory)][version]$RequiredVersion
    )

    $providerVersion = [version](Split-Path $SourceFolder -Leaf)
    $targetRoots = @()

    if ($env:LOCALAPPDATA) {
        $targetRoots += (Join-Path $env:LOCALAPPDATA "PackageManagement\ProviderAssemblies\NuGet")
    }

    if ($env:ProgramFiles) {
        $targetRoots += (Join-Path $env:ProgramFiles "PackageManagement\ProviderAssemblies\NuGet")
    }

    $copySuccess = $false

    foreach ($root in ($targetRoots | Select-Object -Unique)) {
        try {
            $dest = Copy-NuGetProviderFolder -SourceFolder $SourceFolder -DestinationRoot $root
            Write-Log ("NuGet provider v{0} copiado para {1}" -f $providerVersion, $dest) "SUCCESS" 2
            $copySuccess = $true
        }
        catch {
            Write-Log ("Falha ao copiar NuGet provider para {0}: {1}" -f $root, $_.Exception.Message) "WARNING" 2
        }
    }

    if (-not $copySuccess) {
        Write-Log "Nenhuma cópia do NuGet provider para os caminhos padrão do sistema foi concluída com sucesso." "ERROR" 2
        return $false
    }

    [void](Import-NuGetProviderToSession -RequiredVersion $RequiredVersion)

    $provider = Get-LatestAvailableNuGetProvider
    if ($provider -and ([version]$provider.Version -ge $RequiredVersion)) {
        Write-Log ("NuGet provider reconhecido pelo sistema após promoção: v{0}" -f $provider.Version) "SUCCESS" 2
        return $true
    }

    Write-Log "NuGet provider foi copiado, mas não ficou reconhecido pelo sistema." "ERROR" 2
    return $false
}

function Export-NuGetProviderToModulesFromFolder {
    param(
        [Parameter(Mandatory)][string]$SourceFolder,
        [Parameter(Mandatory)][string]$ModulesRoot,
        [Parameter(Mandatory)][version]$RequiredVersion
    )

    $sourceVersion = [version](Split-Path $SourceFolder -Leaf)
    if ($sourceVersion -lt $RequiredVersion) {
        Write-Log ("NuGet provider encontrado abaixo da versão mínima. Encontrado: {0} | Requerido: {1}" -f $sourceVersion, $RequiredVersion) "ERROR" 2
        return $false
    }

    $targetRoot = Join-Path $ModulesRoot "NuGet"

    try {
        $dest = Copy-NuGetProviderFolder -SourceFolder $SourceFolder -DestinationRoot $targetRoot
        Write-Log ("NuGet provider exportado para o pacote offline: {0}" -f $dest) "INFO" 2
        return $true
    }
    catch {
        Write-Log ("Falha ao exportar NuGet provider para o pacote offline: {0}" -f $_.Exception.Message) "ERROR" 2
        return $false
    }
}

function Invoke-IsolatedNuGetDownloadSession {
    param(
        [Parameter(Mandatory)][version]$RequiredVersion,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][array]$ModuleDefinitions
    )

    Write-Log "NuGet local abaixo do mínimo. Iniciando sessão isolada temporária para obtenção do provider e download dos módulos." "WARNING" 1

    $originalLocalAppData = $env:LOCALAPPDATA
    $tempRoot = Join-Path $env:TEMP ("VBR_AsBuilt_NuGet_" + [guid]::NewGuid().Guid)
    $tempLocalAppData = Join-Path $tempRoot "LocalAppData"

    try {
        New-Item -ItemType Directory -Path $tempLocalAppData -Force | Out-Null
        $env:LOCALAPPDATA = $tempLocalAppData

        $gallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if ($gallery -and $gallery.InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
        }

        Install-PackageProvider -Name NuGet -MinimumVersion $RequiredVersion -Force -ForceBootstrap -Scope CurrentUser -Confirm:$false -ErrorAction Stop | Out-Null

        $tempNuGetRoot = Join-Path $tempLocalAppData "PackageManagement\ProviderAssemblies\NuGet"
        $tempProviderFolder = $null

        if (Test-Path $tempNuGetRoot) {
            $tempProviderFolder = Get-ChildItem -Path $tempNuGetRoot -Directory -ErrorAction SilentlyContinue |
                ForEach-Object {
                    try {
                        [pscustomobject]@{
                            Version = [version]$_.Name
                            Path    = $_.FullName
                        }
                    }
                    catch {
                    }
                } |
                Where-Object { $_ -and $_.Version -ge $RequiredVersion } |
                Sort-Object Version -Descending |
                Select-Object -First 1
        }

        if (-not $tempProviderFolder) {
            throw "O NuGet provider não foi encontrado na sessão isolada temporária."
        }

        if (-not (Export-NuGetProviderToModulesFromFolder -SourceFolder $tempProviderFolder.Path -ModulesRoot $DestinationPath -RequiredVersion $RequiredVersion)) {
            throw "Falha ao exportar o NuGet provider da sessão isolada."
        }

        foreach ($moduleDef in $ModuleDefinitions) {
            $name = $moduleDef.Name
            $requiredVersionText = $moduleDef.RequiredVersion
            $optional = if ($moduleDef.ContainsKey("Optional")) { [bool]$moduleDef.Optional } else { $false }

            try {
                Write-Log ("Baixando módulo {0} v{1} para {2} em sessão isolada" -f $name, $requiredVersionText, $DestinationPath) "INFO" 1
                Save-Module -Name $name -RequiredVersion $requiredVersionText -Path $DestinationPath -Force -Confirm:$false -ErrorAction Stop
                Write-Log ("Download concluído para {0} v{1}" -f $name, $requiredVersionText) "SUCCESS" 2
            }
            catch {
                if ($optional) {
                    Write-Log ("Falha no download do módulo opcional {0}: {1}" -f $name, $_.Exception.Message) "WARNING" 2
                }
                else {
                    throw
                }
            }
        }

        return $true
    }
    catch {
        Write-Log ("Falha na sessão isolada de obtenção do NuGet provider: {0}" -f $_.Exception.Message) "ERROR" 2
        return $false
    }
    finally {
        $env:LOCALAPPDATA = $originalLocalAppData

        try {
            if (Test-Path $tempRoot) {
                Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Log ("Não foi possível remover a área temporária isolada do NuGet: {0}" -f $_.Exception.Message) "DEBUG" 2
        }
    }
}

function Ensure-NuGetProviderPresent {
    param(
        [Parameter(Mandatory)][version]$RequiredVersion,
        [Parameter(Mandatory)][bool]$InternetAvailable,
        [Parameter(Mandatory)][bool]$OnlineInstallEnabled,
        [Parameter(Mandatory)][string]$OfflineRoot
    )

    Write-Log "Validando presença do NuGet provider" "INFO" 1

    $provider = Get-LatestAvailableNuGetProvider
    if ($provider -and ([version]$provider.Version -ge $RequiredVersion)) {
        Write-Log ("NuGet provider já disponível: v{0}" -f $provider.Version) "SUCCESS" 2
        [void](Import-NuGetProviderToSession -RequiredVersion $RequiredVersion)
        return $true
    }

    if ($provider) {
        Write-Log ("NuGet provider abaixo da versão mínima. Encontrado: {0} | Requerido: {1}" -f $provider.Version, $RequiredVersion) "WARNING" 2
    }
    else {
        Write-Log "NuGet provider não encontrado localmente" "WARNING" 2
    }

    if ($InternetAvailable -and $OnlineInstallEnabled) {
        try {
            Write-Log "Tentando instalação online do NuGet provider..." "INFO" 2
            Install-PackageProvider -Name NuGet -MinimumVersion $RequiredVersion -Force -ForceBootstrap -Scope CurrentUser -Confirm:$false -ErrorAction Stop | Out-Null
            [void](Import-NuGetProviderToSession -RequiredVersion $RequiredVersion)
        }
        catch {
            Write-Log ("Falha na instalação online do NuGet provider: {0}" -f $_.Exception.Message) "WARNING" 2
        }
    }

    $provider = Get-LatestAvailableNuGetProvider
    if ($provider -and ([version]$provider.Version -ge $RequiredVersion)) {
        Write-Log ("NuGet provider disponível após tentativa online: v{0}" -f $provider.Version) "SUCCESS" 2
        return $true
    }

    $offlineProviderFolder = Get-OfflineNuGetProviderFolder -ModulesRoot $OfflineRoot -RequiredVersion $RequiredVersion
    if (-not $offlineProviderFolder) {
        Write-Log ("NuGet provider offline não encontrado em {0}" -f (Join-Path $OfflineRoot "NuGet")) "ERROR" 2
        return $false
    }

    Write-Log ("Tentando promover NuGet provider offline a partir de {0}" -f $offlineProviderFolder.Path) "INFO" 2
    return (Promote-NuGetProviderToSystem -SourceFolder $offlineProviderFolder.Path -RequiredVersion $RequiredVersion)
}

function Download-RequiredModules {
    param(
        [Parameter(Mandatory)][array]$ModuleDefinitions,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][bool]$InternetAvailable,
        [Parameter(Mandatory)][version]$RequiredNuGetVersion
    )

    if (-not $InternetAvailable) {
        Stop-WithFailure -SummaryKey "Modules" -Message "Modo DownloadOnly requer acesso à internet."
    }

    if (-not (Test-Path $DestinationPath)) {
        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    }

    Write-Section "DOWNLOAD DE PACOTES"

    $localProviderFolder = Get-LatestInstalledNuGetProviderFolder
    $localProvider = Get-LatestAvailableNuGetProvider

    if ($localProvider -and ([version]$localProvider.Version -ge $RequiredNuGetVersion) -and $localProviderFolder) {
        Write-Log ("NuGet provider local atende ao mínimo: v{0}" -f $localProvider.Version) "SUCCESS" 1
        [void](Import-NuGetProviderToSession -RequiredVersion $RequiredNuGetVersion)

        if (-not (Export-NuGetProviderToModulesFromFolder -SourceFolder $localProviderFolder.Path -ModulesRoot $DestinationPath -RequiredVersion $RequiredNuGetVersion)) {
            Stop-WithFailure -SummaryKey "NuGetGallery" -Message "Falha ao exportar o NuGet provider local para o pacote offline."
        }

        foreach ($moduleDef in $ModuleDefinitions) {
            $name = $moduleDef.Name
            $requiredVersionText = $moduleDef.RequiredVersion
            $optional = if ($moduleDef.ContainsKey("Optional")) { [bool]$moduleDef.Optional } else { $false }

            try {
                Write-Log ("Baixando módulo {0} v{1} para {2}" -f $name, $requiredVersionText, $DestinationPath) "INFO" 1
                Save-Module -Name $name -RequiredVersion $requiredVersionText -Path $DestinationPath -Force -Confirm:$false -ErrorAction Stop
                Write-Log ("Download concluído para {0} v{1}" -f $name, $requiredVersionText) "SUCCESS" 2
            }
            catch {
                if ($optional) {
                    Write-Log ("Falha no download do módulo opcional {0}: {1}" -f $name, $_.Exception.Message) "WARNING" 2
                }
                else {
                    Stop-WithFailure -SummaryKey "Modules" -Message ("Falha no download do módulo {0}: {1}" -f $name, $_.Exception.Message)
                }
            }
        }
    }
    else {
        $isolatedOk = Invoke-IsolatedNuGetDownloadSession -RequiredVersion $RequiredNuGetVersion -DestinationPath $DestinationPath -ModuleDefinitions $ModuleDefinitions
        if (-not $isolatedOk) {
            Stop-WithFailure -SummaryKey "NuGetGallery" -Message "Falha ao preparar o NuGet provider e os módulos em sessão isolada."
        }
    }

    Update-Summary -Key "NuGetGallery" -Value "OK"
    Update-Summary -Key "Modules" -Value "OK"
    Update-Summary -Key "VeeamPowerShell" -Value "SKIPPED"
    Update-Summary -Key "VeeamConnection" -Value "SKIPPED"
    Update-Summary -Key "VeeamVersion" -Value "SKIPPED"
    Update-Summary -Key "ReportConfig" -Value "SKIPPED"
    Update-Summary -Key "ReportExecution" -Value "SKIPPED"
    Update-Summary -Key "FinalStatus" -Value "OK"
    Update-Summary -Key "FinalMessage" -Value ("Download de pacotes concluído em: {0}" -f $DestinationPath)
    Write-FinalSummary
    Pause-End
    exit
}

function Install-ModuleOfflineFromFolder {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][version]$RequiredVersion,
        [Parameter(Mandatory)][string]$OfflineRoot
    )

    $sourcePath = Join-Path $OfflineRoot $Name
    if (-not (Test-Path $sourcePath)) {
        Write-Log ("Pasta offline não encontrada para o módulo {0}: {1}" -f $Name, $sourcePath) "ERROR" 2
        return $null
    }

    $sourceVersionPath = Join-Path $sourcePath $RequiredVersion.ToString()
    if (-not (Test-Path $sourceVersionPath)) {
        Write-Log ("Versão offline esperada não encontrada para {0}: {1}" -f $Name, $sourceVersionPath) "ERROR" 2
        return $null
    }

    $preferredModuleRoot = Get-PreferredUserModulePath

    if (-not $preferredModuleRoot) {
        Write-Log "Nenhum caminho de módulos de usuário foi identificado no PSModulePath." "ERROR" 2
        return $null
    }

    Write-Log ("Caminho de módulos selecionado para instalação: {0}" -f $preferredModuleRoot) "INFO" 2

    try {
        if (-not (Test-Path $preferredModuleRoot)) {
            New-Item -ItemType Directory -Path $preferredModuleRoot -Force | Out-Null
        }

        $targetModulePath = Join-Path $preferredModuleRoot $Name
        if (-not (Test-Path $targetModulePath)) {
            New-Item -ItemType Directory -Path $targetModulePath -Force | Out-Null
        }

        $targetVersionPath = Join-Path $targetModulePath $RequiredVersion.ToString()
        if (Test-Path $targetVersionPath) {
            Remove-Item $targetVersionPath -Recurse -Force -ErrorAction SilentlyContinue
        }

        Copy-Item -Path $sourceVersionPath -Destination $targetVersionPath -Recurse -Force -ErrorAction Stop
        Write-Log ("Módulo {0} v{1} copiado para {2}" -f $Name, $RequiredVersion, $targetVersionPath) "SUCCESS" 2

        if (-not (Test-Path $targetVersionPath)) {
            Write-Log ("O módulo {0} não foi encontrado no destino esperado: {1}" -f $Name, $targetVersionPath) "ERROR" 2
            return $null
        }

        Write-Log ("Módulo {0} validado no caminho: {1}" -f $Name, $targetVersionPath) "SUCCESS" 2
        return $targetVersionPath
    }
    catch {
        Write-Log ("Falha ao copiar {0} para {1}: {2}" -f $Name, $preferredModuleRoot, $_.Exception.Message) "ERROR" 2
        return $null
    }
}

function Show-OfflineModuleInstructions {
    param(
        [Parameter(Mandatory)][string]$ModuleName,
        [Parameter(Mandatory)][string]$OfflineRoot,
        [Parameter(Mandatory)][array]$AllModules
    )

    Write-Log ("Não foi possível instalar o módulo {0} automaticamente." -f $ModuleName) "ERROR" 1
    Write-Log "Baixe os módulos em uma máquina auxiliar com internet e salve na pasta abaixo:" "WARNING" 1
    Write-Log $OfflineRoot "WARNING" 2
    Write-Log "Comandos sugeridos para a máquina auxiliar:" "INFO" 1

    foreach ($module in $AllModules) {
        Write-Log ("Save-Module -Name {0} -RequiredVersion {1} -Path `"{2}`"" -f $module.Name, $module.RequiredVersion, $OfflineRoot) "INFO" 2
    }

    Write-Log ("NuGet provider esperado em: {0}" -f (Join-Path $OfflineRoot "NuGet\<versão>")) "INFO" 2
    Write-Log "Depois de copiar a pasta modules ao lado do script, reexecute este mesmo arquivo." "INFO" 1
}

function Ensure-AllModulesPresent {
    param(
        [Parameter(Mandatory)][array]$ModuleDefinitions,
        [Parameter(Mandatory)][bool]$InternetAvailable,
        [Parameter(Mandatory)][bool]$OnlineInstallEnabled,
        [Parameter(Mandatory)][string]$OfflineRoot
    )

    foreach ($moduleDef in $ModuleDefinitions) {
        $name = $moduleDef.Name
        $requiredVersion = [version]$moduleDef.RequiredVersion

        Write-Log ("Validando presença do módulo {0}" -f $name) "INFO" 1

        $available = Get-LatestAvailableModule -Name $name
        if ($available -and ([version]$available.Version -ge $requiredVersion)) {
            Write-Log ("Módulo já disponível: {0} v{1}" -f $name, $available.Version) "SUCCESS" 2
            continue
        }

        if ($available) {
            Write-Log ("Versão local insuficiente para {0}. Encontrado: {1} | Requerido: {2}" -f $name, $available.Version, $requiredVersion) "WARNING" 2
        }
        else {
            Write-Log ("Módulo {0} não encontrado localmente" -f $name) "WARNING" 2
        }

        if ($InternetAvailable -and $OnlineInstallEnabled) {
            Write-Log ("Tentando instalação online de {0}..." -f $name) "INFO" 2
            try {
                Install-Module -Name $name -RequiredVersion $requiredVersion -Force -Scope CurrentUser -AllowClobber -Confirm:$false -ErrorAction Stop
                Write-Log ("Instalação online concluída para {0} v{1}" -f $name, $requiredVersion) "SUCCESS" 2
            }
            catch {
                Write-Log ("Falha na instalação online de {0}: {1}" -f $name, $_.Exception.Message) "ERROR" 2
            }
        }

        $available = Get-LatestAvailableModule -Name $name
        if (-not ($available -and ([version]$available.Version -ge $requiredVersion))) {
            Write-Log ("Tentando instalação offline de {0}..." -f $name) "INFO" 2
            $offlineTargetVersionPath = Install-ModuleOfflineFromFolder -Name $name -RequiredVersion $requiredVersion -OfflineRoot $OfflineRoot
            if (-not $offlineTargetVersionPath) {
                Show-OfflineModuleInstructions -ModuleName $name -OfflineRoot $OfflineRoot -AllModules $ModuleDefinitions
                return $false
            }
        }

        $validated = Get-LatestAvailableModule -Name $name
        if (-not $validated) {
            Write-Log ("Módulo {0} não foi localizado após instalação." -f $name) "ERROR" 2
            return $false
        }

        if ([version]$validated.Version -lt $requiredVersion) {
            Write-Log ("Validação de versão falhou para {0}. Requerido: >= {1}. Encontrado: {2}" -f $name, $requiredVersion, $validated.Version) "ERROR" 2
            return $false
        }

        Write-Log ("Presença validada para {0}: v{1}" -f $name, $validated.Version) "SUCCESS" 2
        Write-Log ("Origem validada: {0}" -f $validated.Path) "DEBUG" 2
    }

    return $true
}

function Import-ModuleInControlledOrder {
    param(
        [Parameter(Mandatory)][array]$ModuleDefinitions
    )

    foreach ($moduleDef in $ModuleDefinitions) {
        $name = $moduleDef.Name
        $requiredCommands = $moduleDef.RequiredCommands
        $minimumPSEdition = if ($moduleDef.ContainsKey("MinimumPSEdition")) { $moduleDef.MinimumPSEdition } else { "Any" }

        Write-Log ("Importando módulo {0}" -f $name) "INFO" 1

        if ($minimumPSEdition -eq "DesktopOnly" -and $PSEdition -ne "Desktop") {
            Write-Log ("Importação do módulo {0} será ignorada na sessão atual porque ele requer Windows PowerShell (Desktop)." -f $name) "WARNING" 2
            continue
        }

        try {
            Import-Module -Name $name -Force -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop
            Write-Log ("Importação concluída para {0}" -f $name) "SUCCESS" 2
        }
        catch {
            Write-Log ("Falha ao importar {0}: {1}" -f $name, $_.Exception.Message) "ERROR" 2
            return $false
        }

        if (-not (Ensure-ModuleImported -Name $name -RequiredCommands $requiredCommands)) {
            Write-Log ("Módulo {0} não passou na validação final de sessão/cmdlets" -f $name) "ERROR" 2
            return $false
        }

        foreach ($cmd in $requiredCommands) {
            Write-Log ("Cmdlet validado: {0}" -f $cmd) "SUCCESS" 2
        }

        Write-Log ("Módulo {0} validado com sucesso" -f $name) "SUCCESS" 2
    }

    return $true
}

function Ensure-ReportConfigFile {
    param(
        [Parameter(Mandatory)][string]$FolderPath
    )

    $reportConfigPath = Join-Path $FolderPath "AsBuiltReport.Veeam.VBR.json"

    if (Test-Path $reportConfigPath) {
        Write-Log ("Arquivo de configuração do report localizado: {0}" -f $reportConfigPath) "SUCCESS" 1
        return $reportConfigPath
    }

    Write-Log ("Arquivo de configuração do report não encontrado. Gerando em: {0}" -f $reportConfigPath) "INFO" 1

    try {
        if (-not (Test-Path $FolderPath)) {
            New-Item -ItemType Directory -Path $FolderPath -Force | Out-Null
        }

        New-AsBuiltReportConfig -Report Veeam.VBR -FolderPath $FolderPath -ErrorAction Stop | Out-Null

        if (-not (Test-Path $reportConfigPath)) {
            throw "O arquivo de configuração não foi criado."
        }

        Write-Log ("Arquivo de configuração do report criado com sucesso: {0}" -f $reportConfigPath) "SUCCESS" 1
        return $reportConfigPath
    }
    catch {
        Write-Log ("Falha ao gerar arquivo de configuração do report: {0}" -f $_.Exception.Message) "ERROR" 1
        return $null
    }
}

Write-Section "INÍCIO DA EXECUÇÃO"

$ModulePresenceBaseline = @(
    @{ Name = "PScribo";                 RequiredVersion = "0.11.1";    RequiredCommands = @() },
    @{ Name = "PScriboCharts";           RequiredVersion = "0.9.0";     RequiredCommands = @() },
    @{ Name = "PSGraph";                 RequiredVersion = "2.1.38.27"; RequiredCommands = @() },
    @{ Name = "Diagrammer.Core";         RequiredVersion = "0.2.39";    RequiredCommands = @() },
    @{ Name = "Veeam.Diagrammer";        RequiredVersion = "0.6.34";    RequiredCommands = @(); MinimumPSEdition = "DesktopOnly" },
    @{ Name = "AsBuiltReport.Core";      RequiredVersion = "1.6.2";     RequiredCommands = @("New-AsBuiltReport", "New-AsBuiltReportConfig") },
    @{ Name = "AsBuiltReport.Veeam.VBR"; RequiredVersion = "0.8.26";    RequiredCommands = @() }
)

$ModuleImportOrder = @(
    @{ Name = "PScribo";                 RequiredVersion = "0.11.1";    RequiredCommands = @() },
    @{ Name = "PScriboCharts";           RequiredVersion = "0.9.0";     RequiredCommands = @() },
    @{ Name = "PSGraph";                 RequiredVersion = "2.1.38.27"; RequiredCommands = @() },
    @{ Name = "Diagrammer.Core";         RequiredVersion = "0.2.39";    RequiredCommands = @() },
    @{ Name = "Veeam.Diagrammer";        RequiredVersion = "0.6.34";    RequiredCommands = @(); MinimumPSEdition = "DesktopOnly" },
    @{ Name = "AsBuiltReport.Core";      RequiredVersion = "1.6.2";     RequiredCommands = @("New-AsBuiltReport", "New-AsBuiltReportConfig") },
    @{ Name = "AsBuiltReport.Veeam.VBR"; RequiredVersion = "0.8.26";    RequiredCommands = @() }
)

Write-Log "Validação do PowerShell" "INFO" 0
$psVersion = $PSVersionTable.PSVersion.Major
Write-Log ("Versão detectada: {0}" -f $psVersion) "INFO" 1
Update-Summary -Key "PowerShell" -Value "OK"

$Mode = Get-ExecutionMode -CurrentMode $Mode
Write-Log ("Modo selecionado: {0}" -f $Mode) "INFO" 1

Write-Log "Validação de conectividade" "INFO" 0
$internetAvailable = Test-InternetConnectivity
$onlineInstallEnabled = $false

if ($internetAvailable) {
    Write-Log "Internet disponível para operações online" "INFO" 1

        # ---------------- VERSION CHECK (SILENCIOSO) ----------------
        try {
            $repo = "julianscunha/Veeam.VBR.ASBuilt"
            $release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -TimeoutSec 3 -ErrorAction Stop    
            $latestVersion = $release.tag_name    
            if ($latestVersion -and $latestVersion -ne $ScriptVersion) {
                Write-Host ""
                Write-Host ("Nova versão disponível: {0} (atual: {1})" -f $latestVersion, $ScriptVersion) -ForegroundColor Yellow
            }
        }
        catch {
            # totalmente silencioso (sem internet, timeout, erro API, etc)
        }
    
    Update-Summary -Key "Connectivity" -Value "OK"
    $onlineInstallEnabled = Validate-PowerShellGetAndGallery
    if ($onlineInstallEnabled) {
        Update-Summary -Key "NuGetGallery" -Value "OK"
    }
    else {
        Write-Log "Operações online de PowerShellGet/PSGallery serão desabilitadas." "WARNING" 1
        Update-Summary -Key "NuGetGallery" -Value "WARNING"
    }

    if ($Mode -eq "DownloadOnly") {
        Download-RequiredModules -ModuleDefinitions $ModulePresenceBaseline -DestinationPath $offlineModulesRoot -InternetAvailable $internetAvailable -RequiredNuGetVersion $NuGetMinimumVersion
    }
}
else {
    Write-Log "Ambiente sem internet detectado" "WARNING" 1
    Write-Log ("Será utilizada a pasta offline, se disponível: {0}" -f $offlineModulesRoot) "INFO" 1
    Update-Summary -Key "Connectivity" -Value "WARNING"
    Update-Summary -Key "NuGetGallery" -Value "SKIPPED"

    if ($Mode -eq "DownloadOnly") {
        Stop-WithFailure -SummaryKey "Connectivity" -Message "Modo DownloadOnly requer acesso à internet."
    }
}

Write-Log "Validação do NuGet provider" "INFO" 0
$nugetOk = Ensure-NuGetProviderPresent -RequiredVersion $NuGetMinimumVersion -InternetAvailable $internetAvailable -OnlineInstallEnabled $onlineInstallEnabled -OfflineRoot $offlineModulesRoot
if (-not $nugetOk) {
    Stop-WithFailure -SummaryKey "NuGetGallery" -Message "Falha na validação/promoção do NuGet provider."
}

Write-Log "Validação de presença dos módulos AsBuilt" "INFO" 0
$presenceOk = Ensure-AllModulesPresent -ModuleDefinitions $ModulePresenceBaseline -InternetAvailable $internetAvailable -OnlineInstallEnabled $onlineInstallEnabled -OfflineRoot $offlineModulesRoot
if (-not $presenceOk) {
    Stop-WithFailure -SummaryKey "Modules" -Message "Falha na validação ou instalação dos módulos necessários."
}

Write-Log "Importação controlada de módulos AsBuilt" "INFO" 0
$importOk = Import-ModuleInControlledOrder -ModuleDefinitions $ModuleImportOrder
if (-not $importOk) {
    Stop-WithFailure -SummaryKey "Modules" -Message "Falha na importação controlada dos módulos necessários."
}
Update-Summary -Key "Modules" -Value "OK"

Write-Log "Carregamento do Veeam" "INFO" 0
$veeamDll = "C:\Program Files\Veeam\Backup and Replication\Console\Veeam.Backup.PowerShell.dll"

if (-not (Test-Path $veeamDll)) {
    Stop-WithFailure -SummaryKey "VeeamPowerShell" -Message ("DLL do Veeam não encontrada: {0}" -f $veeamDll)
}

try {
    Write-Log ("PowerShell Edition: {0}" -f $PSEdition) "INFO" 1
    Write-Log ("PowerShell Version: {0}" -f $PSVersionTable.PSVersion) "INFO" 1
    Write-Log ("DLL do Veeam: {0}" -f $veeamDll) "INFO" 1

    Import-Module $veeamDll -ErrorAction Stop -DisableNameChecking -WarningAction SilentlyContinue
    Write-Log "DLL carregada com sucesso" "SUCCESS" 1
}
catch {
    Write-Log ("Falha ao carregar DLL do Veeam: {0}" -f $_.Exception.Message) "WARNING" 1

    if ($_.Exception.InnerException) {
        Write-Log ("InnerException: {0}" -f $_.Exception.InnerException.Message) "ERROR" 1
    }

    Write-Log ("StackTrace: {0}" -f $_.Exception.StackTrace) "DEBUG" 1

    if ($psVersion -lt 7) {
        if (Confirm-Action "Executar em PowerShell 7?") {
            $pwsh = "C:\Program Files\PowerShell\7\pwsh.exe"

            if (Test-Path $pwsh) {
                Update-Summary -Key "VeeamPowerShell" -Value "WARNING"
                Update-Summary -Key "FinalStatus" -Value "WARNING"
                Update-Summary -Key "FinalMessage" -Value "Relaunch em PowerShell 7 necessário para carregar os cmdlets do Veeam."
                $argList = "-NoExit -File `"$PSCommandPath`" -relaunched 1 -VBRServer `"$VBRServer`" -Mode Full -ModulesPath `"$offlineModulesRoot`" -OutputPath `"$defaultReportOutput`""
                if ($SkipVersionPrompt) { $argList += " -SkipVersionPrompt" }
                Start-Process $pwsh -ArgumentList $argList
                exit
            }
            else {
                Stop-WithFailure -SummaryKey "VeeamPowerShell" -Message "PowerShell 7 não encontrado."
            }
        }
        else {
            Stop-WithFailure -SummaryKey "VeeamPowerShell" -Message "Execução cancelada pelo usuário após falha de carregamento da DLL do Veeam."
        }
    }
    else {
        Stop-WithFailure -SummaryKey "VeeamPowerShell" -Message ("Falha ao carregar DLL do Veeam: {0}" -f $_.Exception.Message)
    }
}

if (-not (Get-Command Get-VBRServer -ErrorAction SilentlyContinue)) {
    Stop-WithFailure -SummaryKey "VeeamPowerShell" -Message "Cmdlets do Veeam indisponíveis."
}

Write-Log "PowerShell Veeam funcional" "SUCCESS" 1
Update-Summary -Key "VeeamPowerShell" -Value "OK"

Write-Log "Conexão com Veeam" "INFO" 0
try {
    Connect-VBRServer -Server $VBRServer | Out-Null
    Write-Log ("Conectado ao servidor Veeam: {0}" -f $VBRServer) "SUCCESS" 1
    Update-Summary -Key "VeeamConnection" -Value "OK"
}
catch {
    Stop-WithFailure -SummaryKey "VeeamConnection" -Message ("Falha na conexão: {0}" -f $_.Exception.Message)
}

Write-Log "Validação da versão do Veeam" "INFO" 0
try {
    $info = Get-VBRBackupServerInfo
    Write-Log "Dados retornados:" "DEBUG" 1
    Write-Log ($info | Format-Table | Out-String) "DEBUG" 2

    $version = $info.Build
    if (-not $version) {
        throw "Campo Build não encontrado"
    }

    Write-Log ("Versão detectada: {0}" -f $version) "INFO" 1
    $ver = [version]$version

    if ($ver.Major -lt 12) {
        Stop-WithFailure -SummaryKey "VeeamVersion" -Message "Versão não suportada."
    }

    if ($ver.Major -ge 13) {
        Write-Log "Versão 13+ detectada. O README oficial do report marca Veeam v13 como não suportado e indica compatibilidade do report apenas com Windows PowerShell 5.1." "WARNING" 1
        Update-Summary -Key "VeeamVersion" -Value "WARNING"
        if (-not $SkipVersionPrompt) {
            if (-not (Confirm-Action "Deseja continuar mesmo assim?")) {
                Stop-WithFailure -SummaryKey "VeeamVersion" -Message "Execução cancelada pelo usuário após detecção de Veeam v13+."
            }
        }
    }
    else {
        Update-Summary -Key "VeeamVersion" -Value "OK"
    }
}
catch {
    Stop-WithFailure -SummaryKey "VeeamVersion" -Message ("Erro ao obter versão: {0}" -f $_.Exception.Message)
}

Write-Log "Entrada de parâmetros" "INFO" 0
$target = Read-Host "Servidor [$VBRServer]"
if ([string]::IsNullOrWhiteSpace($target)) {
    $target = $VBRServer
}

$username = Read-Host "Usuário"
$password = Read-Host "Senha" -AsSecureString

$output = Read-Host ("Diretório de saída [{0}]" -f $defaultReportOutput)
if ([string]::IsNullOrWhiteSpace($output)) {
    $output = $defaultReportOutput
}

if (-not (Test-Path $output)) {
    if (Confirm-Action ("Criar diretório {0}?" -f $output)) {
        New-Item -ItemType Directory -Path $output -Force | Out-Null
    }
    else {
        Stop-WithFailure -SummaryKey "ReportConfig" -Message ("Criação do diretório de saída cancelada pelo usuário: {0}" -f $output)
    }
}

$reportConfigPath = Ensure-ReportConfigFile -FolderPath $output
if (-not $reportConfigPath) {
    Stop-WithFailure -SummaryKey "ReportConfig" -Message "Não foi possível preparar o arquivo de configuração do report."
}
Update-Summary -Key "ReportConfig" -Value "OK"

if (-not $internetAvailable) {
    Write-Log "Aplicando bloqueios de bootstrap automático do PowerShellGet para ambiente offline" "INFO" 1

    try {
        [void](Import-NuGetProviderToSession -RequiredVersion $NuGetMinimumVersion)

        $psGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if ($psGallery) {
            try {
                Unregister-PSRepository -Name PSGallery -ErrorAction Stop
                Write-Log "PSGallery removida temporariamente da sessão offline" "WARNING" 2
            }
            catch {
                Write-Log ("Não foi possível remover PSGallery temporariamente: {0}" -f $_.Exception.Message) "DEBUG" 2
            }
        }

        $env:POWERSHELL_TELEMETRY_OPTOUT = '1'
        $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'

        Write-Log "Bloqueios offline aplicados antes da execução do AsBuiltReport" "SUCCESS" 2
    }
    catch {
        Write-Log ("Falha ao aplicar bloqueios offline: {0}" -f $_.Exception.Message) "WARNING" 2
    }
}

Write-Log "Execução do AsBuiltReport" "INFO" 0
try {
    New-AsBuiltReport `
        -Report Veeam.VBR `
        -Target $target `
        -Username $username `
        -Password $password `
        -OutputPath $output `
        -ReportConfigPath $reportConfigPath `
        -Format Word,HTML

    Write-Log "Relatório gerado com sucesso" "SUCCESS" 1
    Update-Summary -Key "ReportExecution" -Value "OK"
    Update-Summary -Key "FinalStatus" -Value "OK"
    Update-Summary -Key "FinalMessage" -Value "Execução concluída com sucesso."
}
catch {
    $message = $_.Exception.Message

    if ($message -match "Veeam Backup & Replication v13 in any variant \(Windows or Appliance\) is not supported") {
        Write-Log "O ambiente foi validado com sucesso, porém o módulo oficial AsBuiltReport.Veeam.VBR bloqueia a execução em Veeam v13." "ERROR" 1
        Write-Log "A falha não está relacionada a conectividade, módulos ou PowerShell. Trata-se de uma limitação funcional do report oficial." "ERROR" 1
        Update-Summary -Key "ReportExecution" -Value "FAILED"
        Update-Summary -Key "FinalStatus" -Value "FAILED"
        Update-Summary -Key "FinalMessage" -Value "Bloqueio funcional do módulo oficial AsBuiltReport.Veeam.VBR para Veeam v13."
    }
    else {
        Write-Log ("Erro na execução: {0}" -f $message) "ERROR" 1
        Update-Summary -Key "ReportExecution" -Value "FAILED"
        Update-Summary -Key "FinalStatus" -Value "FAILED"
        Update-Summary -Key "FinalMessage" -Value $message
    }
}

Write-Section "FIM DA EXECUÇÃO"
Write-FinalSummary
Pause-End
