# Gera o App Bundle (.aab) do Condo App para upload na Google Play Store.
# Incrementa version no pubspec antes do build (patch e +build por padrão; use -BumpBuildOnly só +build).
#
# Uso:
#   .\gerar-app-bundle.ps1
#   .\gerar-app-bundle.ps1 -ApiBaseUrl "https://api.meucondominio.com.br"
#
# Prioridade da URL da API (API_BASE_URL no app):
#   - parâmetro -ApiBaseUrl
#   - $env:CONDO_API_BASE_URL
#   - $env:CONDO_API_PUBLIC_URL
#   - montagem http(s)://$env:CONDO_EC2_HOST:$env:CONDO_API_PORT após carregar ec2-backend-config.ps1 (se existir)
#
# Opcional: CONDO_LOGIN_CONDO_ID; -SkipVersionBump, -BumpBuildOnly

param(
    [string] $ApiBaseUrl = "",
    [string] $LoginCondoId = "",
    [switch] $SkipVersionBump,
    # Incrementa apenas o número após "+" (versionCode Play). Mantém major.minor.patch.
    [switch] $BumpBuildOnly
)

Set-Location $PSScriptRoot

$configPs1 = Join-Path $PSScriptRoot "ec2-backend-config.ps1"
if (Test-Path -LiteralPath $configPs1) {
    Write-Host "Carregando ec2-backend-config.ps1..." -ForegroundColor DarkGray
    . $configPs1
}

# --- Backend (Flutter lê API_BASE_URL em lib/syndic_metric_pages.dart) ---
if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    $ApiBaseUrl = $env:CONDO_API_BASE_URL
}
if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    $pubUrl = [Environment]::GetEnvironmentVariable("CONDO_API_PUBLIC_URL", "Process")
    if (-not [string]::IsNullOrWhiteSpace($pubUrl)) {
        $ApiBaseUrl = $pubUrl.Trim()
    }
}
if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    $ec2HostPart = [Environment]::GetEnvironmentVariable("CONDO_EC2_HOST", "Process")
    if (-not [string]::IsNullOrWhiteSpace($ec2HostPart)) {
        $ec2HostPart = $ec2HostPart.Trim()
    }
    if (-not [string]::IsNullOrWhiteSpace($ec2HostPart)) {
        $portPart = [Environment]::GetEnvironmentVariable("CONDO_API_PORT", "Process")
        if ([string]::IsNullOrWhiteSpace($portPart)) {
            $portPart = "5050"
        } else {
            $portPart = $portPart.Trim()
        }
        $scheme = $(if (
                $env:CONDO_API_USE_TLS -eq "1" -or
                ($env:CONDO_API_USE_TLS -eq "true")) { "https" } else { "http" })
        $ApiBaseUrl = "${scheme}://${ec2HostPart}:${portPart}"
    }
}
if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    $ApiBaseUrl = "https://SEU_BACKEND_AQUI"
    Write-Host "AVISO: defina ec2-backend-config.ps1 (veja ec2-backend-config.example.ps1), ou CONDO_API_BASE_URL / -ApiBaseUrl." -ForegroundColor Yellow
}
if ([string]::IsNullOrWhiteSpace($LoginCondoId)) {
    $LoginCondoId = $env:CONDO_LOGIN_CONDO_ID
}
if ([string]::IsNullOrWhiteSpace($LoginCondoId)) {
    $LoginCondoId = "1"
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host "ERRO: flutter nao encontrado no PATH." -ForegroundColor Red
    exit 1
}

# --- Incremento de versão (pubspec: versionName+versionCode → ex.: 1.0.0+1)
# Na Play Console o versionCode (+N) obrigatoriamente aumenta a cada artefato.
$pubspecPath = Join-Path $PSScriptRoot "pubspec.yaml"
if (-not (Test-Path $pubspecPath)) {
    Write-Host "ERRO: pubspec.yaml nao encontrado em $pubspecPath" -ForegroundColor Red
    exit 1
}

if (-not $SkipVersionBump) {
    $content = Get-Content $pubspecPath -Raw
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
        Write-Host "Versao atualizada para $major.$minor.$patch+$build" -ForegroundColor Green
    } else {
        Write-Host "Aviso: nao foi possivel ler o campo version no pubspec.yaml." -ForegroundColor Yellow
    }
} else {
    Write-Host "SkipVersionBump: pubspec.yaml inalterado." -ForegroundColor Cyan
}

Write-Host "`nLimpando build anterior (flutter clean)..." -ForegroundColor Cyan
flutter clean

Write-Host "`nRemovendo pasta build para garantir build limpo..." -ForegroundColor Cyan
if (Test-Path "build") { Remove-Item -LiteralPath "build" -Recurse -Force }

Write-Host "`nBaixando dependencias..." -ForegroundColor Cyan
flutter pub get

$keyProps = Join-Path $PSScriptRoot "android\key.properties"
if (-not (Test-Path -LiteralPath $keyProps)) {
    Write-Host "AVISO: android\key.properties nao existe. O AAB ficara assinado com DEBUG e a Play Store rejeita." -ForegroundColor Yellow
    Write-Host "        Copie android\key.properties.example para android\key.properties, crie um .jks (keytool) e preencha. `n" -ForegroundColor Yellow
}

Write-Host "`nModo release" -ForegroundColor Yellow
Write-Host "  API_BASE_URL=$ApiBaseUrl" -ForegroundColor Gray
Write-Host "  LOGIN_CONDO_ID=$LoginCondoId (tela de login publica)`n" -ForegroundColor Gray

$buildArgs = @(
    "build", "appbundle", "--release",
    "--dart-define=API_BASE_URL=$ApiBaseUrl",
    "--dart-define=LOGIN_CONDO_ID=$LoginCondoId"
)
Write-Host "Gerando App Bundle..." -ForegroundColor Cyan
& flutter @buildArgs

$aabPath = Join-Path $PSScriptRoot "build\app\outputs\bundle\release\app-release.aab"
if (Test-Path $aabPath) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "ARQUIVO GERADO COM SUCESSO!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Caminho: $((Resolve-Path $aabPath).Path)" -ForegroundColor Yellow
    Write-Host "`nPlay Console:" -ForegroundColor White
    Write-Host "  Release > Producao (ou teste interno) > Nova versao" -ForegroundColor White
    Write-Host "  Envie o .aab gerado.`n" -ForegroundColor White
} else {
    Write-Host "`nErro: AAB nao encontrado. Confira mensagens acima.`n" -ForegroundColor Red
    exit 1
}
