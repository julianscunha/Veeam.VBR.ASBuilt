param(
    [ValidateSet("Normal","DownloadOnly")]
    [string]$Mode = "Normal",

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

# ---------------- DEFAULT PATHS ----------------
if (-not $OutputPath)  { $OutputPath  = Join-Path $currentPath "report" }
if (-not $ModulesPath) { $ModulesPath = Join-Path $currentPath "modules" }

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
    Write-Host "Modo offline ou falha no download. Usando versão local..." -ForegroundColor Yellow
}

# ---------------- VALIDA EXISTÊNCIA ----------------
if (-not (Test-Path $scriptPath)) {
    Write-Host "Script não encontrado localmente e download falhou." -ForegroundColor Red
    Read-Host "Pressione ENTER para sair"
    exit 1
}

# ---------------- GARANTE PASTAS ----------------
if (-not (Test-Path $ModulesPath)) {
    New-Item -ItemType Directory -Path $ModulesPath | Out-Null
}

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath | Out-Null
}

# ---------------- EXECUÇÃO ----------------
Write-Host ""
Write-Host "Executando AsBuilt..." -ForegroundColor Cyan

try {
    $psArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$scriptPath`"",
        "-Mode", "`"$Mode`"",
        "-OutputPath", "`"$OutputPath`"",
        "-ModulesPath", "`"$ModulesPath`""
    )

    # 🔍 debug leve (pode comentar se quiser)
    Write-Host "Args:" -ForegroundColor DarkGray
    Write-Host ($psArgs -join " ") -ForegroundColor DarkGray

    Start-Process powershell -ArgumentList $psArgs -Wait -NoNewWindow

    # ---------------- CONTROLE DE FLUXO ----------------
    if ($Mode -eq "DownloadOnly") {
        Write-Host ""
        Write-Host "Download concluído. Encerrando." -ForegroundColor Green
        return
    }

    Write-Host ""
    Write-Host "Execução finalizada." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "Erro ao executar AsBuilt:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host "Pressione ENTER para sair"
}
