param(
    [string]$Mode,
    [string]$OutputPath,
    [string]$ModulesPath,
    [string]$Version = "latest"
)

$ErrorActionPreference = "Stop"

$repo = "julianscunha/Veeam.VBR.ASBuilt"
$currentPath = Get-Location
$scriptPath = Join-Path $currentPath "vbr_asbuilt.ps1"

Write-Host ""
Write-Host "===== Veeam VBR AsBuilt =====" -ForegroundColor Cyan

# ---------------- DOWNLOAD / UPDATE ----------------
try {
    if ($Version -eq "latest") {
        $release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -TimeoutSec 5
        $versionTag = $release.tag_name
    } else {
        $versionTag = $Version
    }

    $downloadUrl = "https://raw.githubusercontent.com/$repo/$versionTag/vbr_asbuilt.ps1"

    Write-Host "Verificando/baixando script..." -ForegroundColor DarkGray

    $tempFile = Join-Path $currentPath "vbr_asbuilt.tmp.ps1"

    Invoke-WebRequest $downloadUrl -OutFile $tempFile -UseBasicParsing -ErrorAction Stop

    if (Test-Path $tempFile) {
        Move-Item $tempFile $scriptPath -Force
        Write-Host "Script pronto ($versionTag)" -ForegroundColor Green
    }
}
catch {
    Write-Host "Sem internet ou falha no download. Usando versão local..." -ForegroundColor Yellow
}

# ---------------- VALIDA EXISTÊNCIA ----------------
if (-not (Test-Path $scriptPath)) {
    Write-Host "Script não encontrado localmente e download falhou." -ForegroundColor Red
    Read-Host "Pressione ENTER para sair"
    exit 1
}

# ---------------- GARANTE PASTAS ----------------
$modulesPathDefault = Join-Path $currentPath "modules"
$reportPathDefault  = Join-Path $currentPath "report"

if (-not (Test-Path $modulesPathDefault)) {
    New-Item -ItemType Directory -Path $modulesPathDefault | Out-Null
}

if (-not (Test-Path $reportPathDefault)) {
    New-Item -ItemType Directory -Path $reportPathDefault | Out-Null
}

# ---------------- EXECUÇÃO SEGURA ----------------
Write-Host ""
Write-Host "Executando AsBuilt..." -ForegroundColor Cyan

try {
    # 🔥 cria scriptblock (corrige problema de parâmetros)
    $scriptContent = Get-Content $scriptPath -Raw
    $scriptBlock = [ScriptBlock]::Create($scriptContent)

    # 🔥 parâmetros reais (binding correto)
$invokeParams = @{}

# defaults seguros
if (-not $OutputPath)  { $OutputPath  = Join-Path $currentPath "report" }
if (-not $ModulesPath) { $ModulesPath = Join-Path $currentPath "modules" }

$invokeParams["OutputPath"]  = $OutputPath
$invokeParams["ModulesPath"] = $ModulesPath

if ($Mode) { $invokeParams["Mode"] = $Mode }

    & $scriptBlock @invokeParams
}
catch {
    Write-Host ""
    Write-Host "Erro ao executar AsBuilt:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host "Pressione ENTER para sair"
}
