param(
    [string]$Mode,
    [string]$OutputPath,
    [string]$ModulesPath
)

$ErrorActionPreference = "Stop"

$repo = "https://raw.githubusercontent.com/julianscunha/Veeam.VBR.ASBuilt/main"
$currentPath = Get-Location
$scriptPath = Join-Path $currentPath "vbr_asbuilt.ps1"

Write-Host "===== Veeam VBR AsBuilt Bootstrap =====" -ForegroundColor Cyan
Write-Host "Diretório de execução: $currentPath" -ForegroundColor Yellow

try {
    Write-Host "Baixando script principal..." -ForegroundColor Cyan
    Invoke-WebRequest "$repo/vbr_asbuilt.ps1" -OutFile $scriptPath -UseBasicParsing

    if (-not (Test-Path $scriptPath)) {
        throw "Falha ao baixar o script principal."
    }

    Write-Host "Script baixado com sucesso." -ForegroundColor Green
}
catch {
    Write-Host "Erro ao baixar script: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$modulesPathDefault = Join-Path $currentPath "modules"
$reportPathDefault  = Join-Path $currentPath "report"

if (-not (Test-Path $modulesPathDefault)) {
    New-Item -ItemType Directory -Path $modulesPathDefault | Out-Null
}

if (-not (Test-Path $reportPathDefault)) {
    New-Item -ItemType Directory -Path $reportPathDefault | Out-Null
}

$argList = "-ExecutionPolicy Bypass -File `"$scriptPath`""

if ($Mode)        { $argList += " -Mode $Mode" }
if ($OutputPath)  { $argList += " -OutputPath `"$OutputPath`"" }
if ($ModulesPath) { $argList += " -ModulesPath `"$ModulesPath`"" }

Write-Host "Executando script principal..." -ForegroundColor Cyan

powershell $argList
