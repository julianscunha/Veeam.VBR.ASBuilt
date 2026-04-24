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

# ---------- FUNÇÃO INTERNET ----------
function Test-InternetConnection {
    try {
        $req = [System.Net.WebRequest]::Create("https://api.github.com")
        $req.Timeout = 3000
        $res = $req.GetResponse()
        $res.Close()
        return $true
    }
    catch {
        return $false
    }
}

# ---------- FUNÇÃO VERSÃO LOCAL ----------
function Get-LocalScriptVersion {
    param($Path)

    if (-not (Test-Path $Path)) { return $null }

    try {
        $content = Get-Content $Path -ErrorAction Stop
        foreach ($line in $content) {
            if ($line -match '\$ScriptVersion\s*=\s*"(.+)"') {
                return $matches[1]
            }
        }
    }
    catch {}

    return "unknown"
}

# ---------- HEADER ----------
Write-Host ""
Write-Host "===== Veeam VBR AsBuilt Bootstrap =====" -ForegroundColor Cyan
Write-Host "Diretório: $currentPath" -ForegroundColor DarkGray

$hasInternet = Test-InternetConnection

# ---------- ONLINE ----------
if ($hasInternet) {

    try {
        if ($Version -eq "latest") {
            $release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -TimeoutSec 5
            $latestVersion = $release.tag_name
        }
        else {
            $latestVersion = $Version
        }

        $baseUrl = "https://raw.githubusercontent.com/$repo/$latestVersion"
        $downloadUrl = "$baseUrl/vbr_asbuilt.ps1"

        $localVersion = Get-LocalScriptVersion -Path $scriptPath

        if ($localVersion) {

            if ($localVersion -ne $latestVersion) {

                Write-Host ""
                Write-Host "Nova versão disponível: $latestVersion" -ForegroundColor Yellow
                Write-Host "Versão local: $localVersion" -ForegroundColor Yellow
                Write-Host ""

                $choice = Read-Host "Deseja atualizar? (Y/N)"

                if ($choice -match "^[Yy]") {

                    Write-Host "Baixando nova versão..." -ForegroundColor Cyan
                    Invoke-WebRequest $downloadUrl -OutFile $scriptPath -UseBasicParsing
                }
                else {
                    Write-Host "Mantendo versão atual..." -ForegroundColor DarkGray
                }
            }
        }
        else {
            Write-Host "Baixando script (primeira execução)..." -ForegroundColor Cyan
            Invoke-WebRequest $downloadUrl -OutFile $scriptPath -UseBasicParsing
        }
    }
    catch {
        Write-Host "Falha ao verificar/baixar versão. Executando versão local." -ForegroundColor Yellow
    }
}

# ---------- OFFLINE ----------
else {
    Write-Host "Modo offline detectado. Usando script local." -ForegroundColor DarkGray
}

# ---------- VALIDA EXISTÊNCIA ----------
if (-not (Test-Path $scriptPath)) {
    Write-Host "Script não encontrado e não foi possível baixar." -ForegroundColor Red
    exit 1
}

# ---------- ESTRUTURA ----------
$modulesPathDefault = Join-Path $currentPath "modules"
$reportPathDefault  = Join-Path $currentPath "report"

if (-not (Test-Path $modulesPathDefault)) {
    New-Item -ItemType Directory -Path $modulesPathDefault | Out-Null
}

if (-not (Test-Path $reportPathDefault)) {
    New-Item -ItemType Directory -Path $reportPathDefault | Out-Null
}

# ---------- EXECUÇÃO ----------
$argList = "-ExecutionPolicy Bypass -File `"$scriptPath`""

if ($Mode)        { $argList += " -Mode $Mode" }
if ($OutputPath)  { $argList += " -OutputPath `"$OutputPath`"" }
if ($ModulesPath) { $argList += " -ModulesPath `"$ModulesPath`"" }

Write-Host ""
Write-Host "Executando AsBuilt..." -ForegroundColor Cyan

& $scriptPath @(
    if ($Mode)        { "-Mode"; $Mode }
    if ($OutputPath)  { "-OutputPath"; $OutputPath }
    if ($ModulesPath) { "-ModulesPath"; $ModulesPath }
)
