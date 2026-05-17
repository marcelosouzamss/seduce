# Gera o App Bundle (.aab) do Seduce Mobile para upload na Google Play Console.
# O projeto Flutter está em .\mobile (pubspec.yaml, android\, etc.).
#
# Incrementa version no mobile\pubspec.yaml antes do build (+build sempre; patch também,
# exceto com -BumpBuildOnly).
#
# Uso (na raiz do repositório c:\seduce):
#   .\gerar-app-bundle.ps1
#   .\gerar-app-bundle.ps1 -ApiBaseUrl "https://api.seudominio.com"
#
# Prioridade da URL da API (compile-time, --dart-define API_BASE_URL):
#   1) parâmetro -ApiBaseUrl
#   2) variável de ambiente SEDUCE_API_BASE_URL
#   3) variável de ambiente API_BASE_URL
#   4) montagem https?://$env:SEDUCE_EC2_HOST:$env:SEDUCE_API_PORT (TLS se SEDUCE_API_USE_TLS=1|true)
#
# Opcional: -SkipVersionBump, -BumpBuildOnly
#
# Assinatura Play Store: copie mobile\android\key.properties.example para key.properties,
# preencha e coloque o .jks referenciado em storeFile (rejeitam bundle assinado só com debug).

param(
    [string] $ApiBaseUrl = "",
    [switch] $SkipVersionBump,
    [switch] $BumpBuildOnly
)

$ErrorActionPreference = "Stop"

$repoRoot = $PSScriptRoot
$mobileDir = Join-Path $repoRoot "mobile"
$pubspecPath = Join-Path $mobileDir "pubspec.yaml"

if (-not (Test-Path -LiteralPath $mobileDir)) {
    Write-Host "ERRO: pasta mobile nao encontrada em $mobileDir" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $pubspecPath)) {
    Write-Host "ERRO: pubspec.yaml nao encontrado em $pubspecPath" -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    $ApiBaseUrl = [Environment]::GetEnvironmentVariable("SEDUCE_API_BASE_URL", "Process")
}
if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    $ApiBaseUrl = [Environment]::GetEnvironmentVariable("API_BASE_URL", "Process")
}
if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    $ec2HostPart = [Environment]::GetEnvironmentVariable("SEDUCE_EC2_HOST", "Process")
    if (-not [string]::IsNullOrWhiteSpace($ec2HostPart)) {
        $ec2HostPart = $ec2HostPart.Trim()
        $portPart = [Environment]::GetEnvironmentVariable("SEDUCE_API_PORT", "Process")
        if ([string]::IsNullOrWhiteSpace($portPart)) {
            $portPart = "3000"
        } else {
            $portPart = $portPart.Trim()
        }
        $tls = $env:SEDUCE_API_USE_TLS
        $scheme = $(if ($tls -eq "1" -or $tls -eq "true") { "https" } else { "http" })
        $ApiBaseUrl = "${scheme}://${ec2HostPart}:${portPart}"
    }
}

if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    Write-Host "AVISO: defina a URL da API com -ApiBaseUrl ou SEDUCE_API_BASE_URL / API_BASE_URL." -ForegroundColor Yellow
    Write-Host "        Usando placeholder (altere antes de publicar).`n" -ForegroundColor Yellow
    $ApiBaseUrl = "https://SEU_BACKEND_AQUI"
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host "ERRO: flutter nao encontrado no PATH." -ForegroundColor Red
    exit 1
}

# --- version: major.minor.patch+build (versionCode na Play deve subir a cada envio)
if (-not $SkipVersionBump) {
    $content = Get-Content -LiteralPath $pubspecPath -Raw
    if ($content -match 'version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)') {
        $major = [int]$Matches[1]
        $minor = [int]$Matches[2]
        $patch = [int]$Matches[3]
        $build = [int]$Matches[4]

        $build++
        if (-not $BumpBuildOnly) {
            $patch++
        }

        $newVersion = "version: $major.$minor.$patch+$build"
        $content = $content -replace 'version:\s*\d+\.\d+\.\d+\+\d+', $newVersion
        Set-Content -LiteralPath $pubspecPath -Value $content -NoNewline
        Write-Host "Versao atualizada em mobile\pubspec.yaml -> $major.$minor.$patch+$build" -ForegroundColor Green
    } else {
        Write-Host "Aviso: nao foi possivel ler o campo version em pubspec.yaml." -ForegroundColor Yellow
    }
} else {
    Write-Host "SkipVersionBump: pubspec.yaml inalterado." -ForegroundColor Cyan
}

$keyProps = Join-Path $mobileDir "android\key.properties"
if (-not (Test-Path -LiteralPath $keyProps)) {
    Write-Host "AVISO: mobile\android\key.properties nao existe. Sem upload keystore o AAB pode ficar so com assinatura DEBUG e a Play Console rejeita." -ForegroundColor Yellow
    Write-Host "        Veja mobile\android\key.properties.example`n" -ForegroundColor Yellow
}

Push-Location $mobileDir
try {
    Write-Host "`nLimpando build (flutter clean)..." -ForegroundColor Cyan
    & flutter clean

    if (Test-Path -LiteralPath "build") {
        Write-Host "Removendo pasta build..." -ForegroundColor Cyan
        Remove-Item -LiteralPath "build" -Recurse -Force
    }

    Write-Host "`nBaixando dependencias (flutter pub get)..." -ForegroundColor Cyan
    & flutter pub get

    Write-Host "`nRelease — API_BASE_URL=$ApiBaseUrl`n" -ForegroundColor Yellow

    $buildArgs = @(
        "build", "appbundle", "--release",
        "--dart-define=API_BASE_URL=$ApiBaseUrl"
    )

    Write-Host "Gerando App Bundle..." -ForegroundColor Cyan
    & flutter @buildArgs
}
finally {
    Pop-Location
}

$aabPath = Join-Path $mobileDir "build\app\outputs\bundle\release\app-release.aab"
if (Test-Path -LiteralPath $aabPath) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "AAB GERADO (Google Play)" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Arquivo: $((Resolve-Path -LiteralPath $aabPath).Path)" -ForegroundColor Yellow
    Write-Host "`nPlay Console > seu app > Versoes > producao ou teste interno > criar nova versao > enviar o .aab`n" -ForegroundColor White
} else {
    Write-Host "`nErro: app-release.aab nao encontrado. Confira as mensagens do flutter acima.`n" -ForegroundColor Red
    exit 1
}
