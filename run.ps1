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

# ---------------- INTERNET ----------------
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

# ---------------- NORMALIZA VERSÃO ----------------
function Normalize-Version {
    param($v)
    if (-not $v) { return $null }
    return ($v -replace '^v','').Trim()
}

# ---------------- VERSÃO LOCAL ----------------
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

    return $null
}

# ---------------- HEADER ----------------
Write-Host ""
Write-Host "===== Veeam VBR AsBuilt =====" -ForegroundColor Cyan

$hasInternet = Test-InternetConnection

# ---------------- ONLINE ----------------
if ($hasInternet) {

    try {
        if ($Version -eq "latest") {
            $release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -TimeoutSec 5
            $latestVersionRaw = $release.tag_name
        }
        else {
            $latestVersionRaw = $Version
        }

        $latestVersion = Normalize-Version $latestVersionRaw
        $baseUrl = "https://raw.githubusercontent.com/$repo/$latestVersionRaw"
        $downloadUrl = "$baseUrl/vbr_asbuilt.ps1"

        $localVersionRaw = Get-LocalScriptVersion -Path $scriptPath
        $localVersion = Normalize-Version $localVersionRaw

        $downloadNeeded = $false

        if ($localVersion) {

            if ($localVersion -ne $latestVersion) {

                Write-Host ""
                Write-Host "Nova versão disponível: $latestVersionRaw" -ForegroundColor Yellow
                Write-Host "Versão local: $localVersionRaw" -ForegroundColor Yellow

                $choice = Read-Host "Atualizar? (Y/N)"

                if ($choice -match "^[Yy]") {
                    $downloadNeeded = $true
                }
            }
        }
        else {
            $downloadNeeded = $true
        }

        if ($downloadNeeded) {

            Write-Host "Baixando script..." -ForegroundColor Cyan

            $tempFile = Join-Path $currentPath "vbr_asbuilt.tmp.ps1"

            Invoke-WebRequest $downloadUrl -OutFile $tempFile -UseBasicParsing

            if (-not (Test-Path $tempFile)) {
                throw "Download falhou"
            }

            Move-Item $tempFile $scriptPath -Force

            # 🔥 Desbloqueia o arquivo baixado (evita bloqueio do Windows)
            Unblock-File -Path $scriptPath -ErrorAction SilentlyContinue
        }

    }
    catch {
        Write-Host "Falha ao verificar versão. Usando versão local." -ForegroundColor DarkGray
    }
}

# ---------------- OFFLINE ----------------
# silencioso (como você pediu)

# ---------------- VALIDA SCRIPT ----------------
if (-not (Test-Path $scriptPath)) {
    Write-Host "Script não encontrado." -ForegroundColor Red
    exit 1
}

# ---------------- ESTRUTURA ----------------
$modulesPathDefault = Join-Path $currentPath "modules"
$reportPathDefault  = Join-Path $currentPath "report"

if (-not (Test-Path $modulesPathDefault)) {
    New-Item -ItemType Directory -Path $modulesPathDefault | Out-Null
}

if (-not (Test-Path $reportPathDefault)) {
    New-Item -ItemType Directory -Path $reportPathDefault | Out-Null
}

# ---------------- EXECUÇÃO ----------------
Write-Host ""
Write-Host "Executando AsBuilt..." -ForegroundColor Cyan

$arguments = @()

if ($Mode)        { $arguments += "-Mode";        $arguments += $Mode }
if ($OutputPath)  { $arguments += "-OutputPath";  $arguments += $OutputPath }
if ($ModulesPath) { $arguments += "-ModulesPath"; $arguments += $ModulesPath }

try {
    & $scriptPath @arguments
}
catch {
    Write-Host "Erro ao executar AsBuilt: $($_.Exception.Message)" -ForegroundColor Red
}
