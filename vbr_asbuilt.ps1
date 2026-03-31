# ==============================
# AsBuiltReport Veeam - FINAL v19
# Online/Offline module handling + NuGet validation
# Console reduzida | Log completo | Resumo final
# ==============================

param(
    [int]$relaunched = 0,
    [string]$VBRServer = "localhost"
)

$ErrorActionPreference = 'Stop'

# ------------------------------
# ENCODING / CONSOLE
# ------------------------------
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

# ------------------------------
# PATHS
# ------------------------------
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$logFile = Join-Path $ScriptRoot "AsBuiltReport_Veeam.log"
$offlineModulesRoot = Join-Path $ScriptRoot "modules"
$defaultReportOutput = Join-Path $ScriptRoot "report"

# ------------------------------
# EXECUTION STATUS
# ------------------------------
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

# ------------------------------
# LOG CONTROL
# ------------------------------
if ($relaunched -eq 0) {
    if (Test-Path $logFile) {
        Remove-Item $logFile -Force -ErrorAction SilentlyContinue
    }
}

# ------------------------------
# LOG SETTINGS
# ------------------------------
$ConsoleVisibleLevels = @("INFO", "WARNING", "ERROR")

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO","SUCCESS","WARNING","ERROR","DEBUG")]
        [string]$Level = "INFO",

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
        "PowerShell",
        "Connectivity",
        "NuGetGallery",
        "Modules",
        "VeeamPowerShell",
        "VeeamConnection",
        "VeeamVersion",
        "ReportConfig",
        "ReportExecution",
        "FinalStatus"
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

function Test-InternetConnectivity {
    $targets = @(
        "https://www.powershellgallery.com",
        "https://www.microsoft.com"
    )

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

function Test-ModuleVersion {
    param(
        [Parameter(Mandatory)][string]$ModuleName,
        [Parameter(Mandatory)][version]$RequiredVersion
    )

    $available = Get-LatestAvailableModule -Name $ModuleName
    if (-not $available) {
        return $false
    }

    return ([version]$available.Version -ge $RequiredVersion)
}

function Ensure-ModuleImported {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string[]]$RequiredCommands = @()
    )

    $loaded = Get-Module -Name $Name
    if (-not $loaded) {
        return $false
    }

    foreach ($cmd in $RequiredCommands) {
        if (-not (Get-Command -Name $cmd -ErrorAction SilentlyContinue)) {
            return $false
        }
    }

    return $true
}

function Validate-NuGetAndGallery {
    Write-Log "Validando NuGet / PowerShellGet / PSGallery" "INFO" 1

    try {
        $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if ($nuget) {
            Write-Log ("NuGet provider encontrado: v{0}" -f $nuget.Version) "SUCCESS" 2
        }
        else {
            Write-Log "NuGet provider ausente. Tentando instalar..." "WARNING" 2
            Install-PackageProvider -Name NuGet -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
            $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
            if (-not $nuget) {
                throw "NuGet provider não ficou disponível após a tentativa de instalação."
            }
            Write-Log ("NuGet provider instalado: v{0}" -f $nuget.Version) "SUCCESS" 2
        }

        $powerShellGet = Get-Module -ListAvailable -Name PowerShellGet |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if ($powerShellGet) {
            Write-Log ("PowerShellGet encontrado: v{0}" -f $powerShellGet.Version) "SUCCESS" 2
        }
        else {
            Write-Log "PowerShellGet não localizado em ListAvailable" "WARNING" 2
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
        Update-Summary -Key "NuGetGallery" -Value "OK"
        return $true
    }
    catch {
        Write-Log ("Falha na validação de NuGet/PSGallery: {0}" -f $_.Exception.Message) "ERROR" 2
        Update-Summary -Key "NuGetGallery" -Value "FAILED"
        return $false
    }
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
        return $false
    }

    $sourceVersionPath = Join-Path $sourcePath $RequiredVersion.ToString()
    if (-not (Test-Path $sourceVersionPath)) {
        Write-Log ("Versão offline esperada não encontrada para {0}: {1}" -f $Name, $sourceVersionPath) "ERROR" 2
        return $false
    }

    $targetRoots = @()
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $targetRoots += (Join-Path $HOME "Documents\PowerShell\Modules")
    }
    $targetRoots += (Join-Path $HOME "Documents\WindowsPowerShell\Modules")

    $copied = $false

    foreach ($root in $targetRoots | Select-Object -Unique) {
        try {
            if (-not (Test-Path $root)) {
                New-Item -ItemType Directory -Path $root -Force | Out-Null
            }

            $targetModulePath = Join-Path $root $Name
            if (-not (Test-Path $targetModulePath)) {
                New-Item -ItemType Directory -Path $targetModulePath -Force | Out-Null
            }

            $targetVersionPath = Join-Path $targetModulePath $RequiredVersion.ToString()
            if (Test-Path $targetVersionPath) {
                Remove-Item $targetVersionPath -Recurse -Force -ErrorAction SilentlyContinue
            }

            Copy-Item -Path $sourceVersionPath -Destination $targetVersionPath -Recurse -Force -ErrorAction Stop
            Write-Log ("Módulo {0} v{1} copiado para {2}" -f $Name, $RequiredVersion, $targetVersionPath) "SUCCESS" 2
            $copied = $true
        }
        catch {
            Write-Log ("Falha ao copiar {0} para {1}: {2}" -f $Name, $root, $_.Exception.Message) "DEBUG" 2
        }
    }

    return $copied
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

    Write-Log "Depois de copiar a pasta modules ao lado do script, reexecute este mesmo arquivo." "INFO" 1
}

function Test-And-LoadModule {
    param(
        [Parameter(Mandatory)][hashtable]$ModuleDefinition,
        [Parameter(Mandatory)][bool]$InternetAvailable,
        [Parameter(Mandatory)][bool]$OnlineInstallEnabled,
        [Parameter(Mandatory)][string]$OfflineRoot,
        [Parameter(Mandatory)][array]$AllModules
    )

    $name = $ModuleDefinition.Name
    $requiredVersion = [version]$ModuleDefinition.RequiredVersion
    $requiredCommands = $ModuleDefinition.RequiredCommands
    $minimumPSEdition = if ($ModuleDefinition.ContainsKey("MinimumPSEdition")) { $ModuleDefinition.MinimumPSEdition } else { "Any" }

    Write-Log ("Validando módulo {0}" -f $name) "INFO" 1

    $available = Get-LatestAvailableModule -Name $name
    if ($available) {
        Write-Log ("Encontrado localmente: v{0}" -f $available.Version) "SUCCESS" 2
        Write-Log ("Origem: {0}" -f $available.Path) "DEBUG" 2

        if ([version]$available.Version -lt $requiredVersion) {
            Write-Log ("Versão local abaixo do mínimo esperado ({0})" -f $requiredVersion) "WARNING" 2
            $available = $null
        }
    }
    else {
        Write-Log "Módulo não encontrado localmente" "WARNING" 2
    }

    if (-not $available) {
        if ($InternetAvailable -and $OnlineInstallEnabled) {
            Write-Log "Tentando instalação online..." "INFO" 2

            try {
                Install-Module -Name $name -RequiredVersion $requiredVersion -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
                Write-Log ("Tentativa de instalação online concluída para {0} v{1}" -f $name, $requiredVersion) "INFO" 2
            }
            catch {
                Write-Log ("Falha na instalação online de {0}: {1}" -f $name, $_.Exception.Message) "ERROR" 2
            }

            if (-not (Test-ModuleVersion -ModuleName $name -RequiredVersion $requiredVersion)) {
                Write-Log ("O módulo {0} v{1} não ficou disponível após a tentativa online" -f $name, $requiredVersion) "ERROR" 2

                if (Test-Path (Join-Path $OfflineRoot $name)) {
                    Write-Log "Pacote offline detectado. Tentando instalação offline..." "INFO" 2

                    $offlineInstalled = Install-ModuleOfflineFromFolder -Name $name -RequiredVersion $requiredVersion -OfflineRoot $OfflineRoot
                    if (-not $offlineInstalled) {
                        Show-OfflineModuleInstructions -ModuleName $name -OfflineRoot $OfflineRoot -AllModules $AllModules
                        return $false
                    }
                }
                else {
                    Show-OfflineModuleInstructions -ModuleName $name -OfflineRoot $OfflineRoot -AllModules $AllModules
                    return $false
                }
            }
        }
        else {
            Write-Log "Sem internet ou instalação online desabilitada. Tentando instalação offline..." "INFO" 2

            $offlineInstalled = Install-ModuleOfflineFromFolder -Name $name -RequiredVersion $requiredVersion -OfflineRoot $OfflineRoot
            if (-not $offlineInstalled) {
                Show-OfflineModuleInstructions -ModuleName $name -OfflineRoot $OfflineRoot -AllModules $AllModules
                return $false
            }
        }
    }

    if (-not (Test-ModuleVersion -ModuleName $name -RequiredVersion $requiredVersion)) {
        Write-Log ("Validação de versão falhou para {0}. Requerido: >= {1}" -f $name, $requiredVersion) "ERROR" 2
        return $false
    }

    $validatedModule = Get-LatestAvailableModule -Name $name
    Write-Log ("Versão validada para {0}: v{1}" -f $name, $validatedModule.Version) "SUCCESS" 2

    if ($minimumPSEdition -eq "DesktopOnly" -and $PSEdition -ne "Desktop") {
        Write-Log ("Importação do módulo {0} será ignorada na sessão atual porque ele requer Windows PowerShell (Desktop)." -f $name) "WARNING" 2
        return $true
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

$ModuleBaseline = @(
    @{ Name = "AsBuiltReport.Core";      RequiredVersion = "1.6.2";     RequiredCommands = @("New-AsBuiltReport", "New-AsBuiltReportConfig") },
    @{ Name = "AsBuiltReport.Veeam.VBR"; RequiredVersion = "0.8.26";    RequiredCommands = @() },
    @{ Name = "PScribo";                 RequiredVersion = "0.11.1";    RequiredCommands = @() },
    @{ Name = "PScriboCharts";           RequiredVersion = "0.9.0";     RequiredCommands = @() },
    @{ Name = "PSGraph";                 RequiredVersion = "2.1.38.27"; RequiredCommands = @() },
    @{ Name = "Diagrammer.Core";         RequiredVersion = "0.2.39";    RequiredCommands = @() },
    @{ Name = "Veeam.Diagrammer";        RequiredVersion = "0.6.34";    RequiredCommands = @(); MinimumPSEdition = "DesktopOnly" }
)

Write-Log "Validação do PowerShell" "INFO" 0
$psVersion = $PSVersionTable.PSVersion.Major
Write-Log ("Versão detectada: {0}" -f $psVersion) "INFO" 1
Update-Summary -Key "PowerShell" -Value "OK"

Write-Log "Validação de conectividade" "INFO" 0
$internetAvailable = Test-InternetConnectivity
$onlineInstallEnabled = $false

if ($internetAvailable) {
    Write-Log "Internet disponível para instalação online de módulos" "INFO" 1
    Update-Summary -Key "Connectivity" -Value "OK"
    $onlineInstallEnabled = Validate-NuGetAndGallery
    if (-not $onlineInstallEnabled) {
        Write-Log "Instalação online de módulos será desabilitada e o script tentará apenas o modo offline." "WARNING" 1
        Update-Summary -Key "NuGetGallery" -Value "WARNING"
    }
}
else {
    Write-Log "Ambiente sem internet detectado" "WARNING" 1
    Write-Log ("Será utilizada a pasta offline, se disponível: {0}" -f $offlineModulesRoot) "INFO" 1
    Update-Summary -Key "Connectivity" -Value "WARNING"
    Update-Summary -Key "NuGetGallery" -Value "SKIPPED"
}

Write-Log "Validação de módulos AsBuilt" "INFO" 0

foreach ($moduleDef in $ModuleBaseline) {
    $ok = Test-And-LoadModule `
        -ModuleDefinition $moduleDef `
        -InternetAvailable $internetAvailable `
        -OnlineInstallEnabled $onlineInstallEnabled `
        -OfflineRoot $offlineModulesRoot `
        -AllModules $ModuleBaseline

    if (-not $ok) {
        Stop-WithFailure -SummaryKey "Modules" -Message ("Validação do módulo {0} falhou. Encerrando execução." -f $moduleDef.Name)
    }
}
Update-Summary -Key "Modules" -Value "OK"

Write-Log "Carregamento do Veeam" "INFO" 0

$veeamDll = "C:\Program Files\Veeam\Backup and Replication\Console\Veeam.Backup.PowerShell.dll"

if (-not (Test-Path $veeamDll)) {
    Stop-WithFailure -SummaryKey "VeeamPowerShell" -Message ("DLL do Veeam não encontrada: {0}" -f $veeamDll)
}

try {
    Import-Module $veeamDll -ErrorAction Stop -DisableNameChecking -WarningAction SilentlyContinue
    Write-Log "DLL carregada com sucesso" "SUCCESS" 1
}
catch {
    Write-Log ("Falha ao carregar DLL do Veeam: {0}" -f $_.Exception.Message) "WARNING" 1

    if ($psVersion -lt 7) {
        if (Confirm-Action "Executar em PowerShell 7?") {
            $pwsh = "C:\Program Files\PowerShell\7\pwsh.exe"

            if (Test-Path $pwsh) {
                Update-Summary -Key "VeeamPowerShell" -Value "WARNING"
                Update-Summary -Key "FinalStatus" -Value "WARNING"
                Update-Summary -Key "FinalMessage" -Value "Relaunch em PowerShell 7 necessário para carregar os cmdlets do Veeam."
                $argList = "-NoExit -File `"$PSCommandPath`" -relaunched 1 -VBRServer `"$VBRServer`""
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
        if (-not (Confirm-Action "Deseja continuar mesmo assim?")) {
            Stop-WithFailure -SummaryKey "VeeamVersion" -Message "Execução cancelada pelo usuário após detecção de Veeam v13+."
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
