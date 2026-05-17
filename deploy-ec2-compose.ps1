# Deploy genérico: envia docker-compose + .env para uma EC2 e executa pull + up -d --force-recreate.
# Copie esta pasta scripts/portable para outro repositório e ajuste os parâmetros ou variáveis de ambiente.
#
# Mesma VM do EngBot: use outro -RemoteDir e outra API_HOST_PORT (ex.: Condo 5050 no host; ~/engbot usa 5000).
# Ao enviar o .env, o script ajusta DATABASE_URL para ``...@postgres:5432/...`` se o host for localhost ou 127.0.0.1.
#
# Exemplo:
#   .\deploy-ec2-compose.ps1 `
#     -SshKeyPath "C:\caminho\engbot-server.pem" `
#     -Ec2Host "18.191.229.62" `
#     -Ec2User "ec2-user" `
#     -RemoteDir "~/meu-backend" `
#     -ComposeLocalPath ".\docker-compose.prod.yml" `
#     -EnvLocalPath ".\.env"
#
# Chave SSH: use -SshKeyPath, variável EC2_DEPLOY_KEY, ou coloque engbot-server.pem na pasta de execução,
# na pasta do script, ou na raiz do repositório (o script tenta achar sozinho).
#
# Variáveis de ambiente (sobrescrevem os defaults abaixo e os parâmetros vazios):
#   EC2_DEPLOY_KEY, EC2_DEPLOY_HOST, EC2_DEPLOY_USER, EC2_DEPLOY_REMOTE_DIR
#   CONDO_DOCKER_IMAGE — imagem da API (usuario/repositorio:tag); injeta no .env remoto se faltar

param(
    [string] $SshKeyPath = $env:EC2_DEPLOY_KEY,
    [string] $Ec2Host = $env:EC2_DEPLOY_HOST,
    [string] $Ec2User = $(if ($env:EC2_DEPLOY_USER) { $env:EC2_DEPLOY_USER } else { "ec2-user" }),
    [string] $RemoteDir = $env:EC2_DEPLOY_REMOTE_DIR,
    [string] $ComposeLocalPath = "",
    [string] $RemoteComposeFileName = "",
    [string] $EnvLocalPath = "",
    [string] $EnvExampleLocalPath = "",
    [string] $CondoDockerImage = "",
    [switch] $SkipUp
)

$ErrorActionPreference = "Stop"

# Edite ao copiar este .ps1 para outro repositório (só usam se parâmetro e env estiverem vazios).
$DefaultEc2Host = "18.191.229.62"
$DefaultRemoteDir = "~/condo"
# Se o seu .env não tiver CONDO_DOCKER_IMAGE, preencha aqui (usuario/condo:latest) para o deploy injetar a linha.
$DefaultCondoDockerImage = ""

function Merge-CondoDockerImageLine {
    param(
        [string] $Text,
        [string] $Image
    )
    if ([string]::IsNullOrWhiteSpace($Image)) { return $Text }
    if ($null -eq $Text) { $Text = "" }
    if ($Text -match '(?m)^\s*CONDO_DOCKER_IMAGE\s*=\s*\S') {
        return $Text
    }
    $nl = if ($Text.IndexOf("`r`n", [System.StringComparison]::Ordinal) -ge 0) { "`r`n" } else { "`n" }
    $lines = $Text -split '\r?\n' | Where-Object { $_ -notmatch '^\s*CONDO_DOCKER_IMAGE\s*=' }
    $body = $lines -join $nl
    if (-not [string]::IsNullOrWhiteSpace($body) -and -not $body.EndsWith($nl, [System.StringComparison]::Ordinal)) {
        $body += $nl
    }
    elseif ([string]::IsNullOrWhiteSpace($body)) {
        $body = ""
    }
    return $body + "CONDO_DOCKER_IMAGE=$Image" + $nl
}

# Compose de produção: a API corre num contentor — o Postgres é o serviço "postgres" na rede Docker, não localhost.
function Repair-DatabaseUrlForDockerNetwork {
    param(
        [string] $Text,
        [string] $DockerPgHost = "postgres"
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }

    $lines = $Text -split '\r?\n'
    $changed = $false
    $out = foreach ($line in $lines) {
        if ($line -notmatch '^(?<key>\s*DATABASE_URL\s*=\s*)(?<val>\S+)\s*$') {
            $line
            continue
        }
        $keyPart = $Matches['key']
        $uriVal = $Matches['val']
        if ($uriVal -notmatch '^(postgresql|postgres)://') {
            $line
            continue
        }
        # postgresql://user:pass@host[:port][/db][?query]
        if ($uriVal -notmatch '^(?<prefix>(?:postgresql|postgres)://[^@]+@)(?<host>localhost|127\.0\.0\.1)(?<port>:[0-9]+)?(?<rest>/[^?\s]*)?(?<q>\?[^\s]*)?$') {
            $line
            continue
        }
        $portPart = $Matches['port']
        if ([string]::IsNullOrWhiteSpace($portPart)) { $portPart = ':5432' }
        $rest = $Matches['rest']
        if ($null -eq $rest) { $rest = '' }
        $q = $Matches['q']
        if ($null -eq $q) { $q = '' }
        $newVal = $Matches['prefix'] + $DockerPgHost + $portPart + $rest + $q
        $changed = $true
        "${keyPart}${newVal}"
    }
    if ($changed) {
        Write-Host "  DATABASE_URL ajustado para host ``$DockerPgHost`` (rede Docker; substitui localhost/127.0.0.1)." -ForegroundColor DarkYellow
        return ($out -join ([Environment]::NewLine))
    }
    return $Text
}

function Find-DefaultSshKey {
    $keyName = "engbot-server.pem"
    $dirs = [System.Collections.Generic.List[string]]::new()
    $seen = @{}
    function Add-Dir {
        param([string] $d)
        if ([string]::IsNullOrWhiteSpace($d)) { return }
        if ($seen.ContainsKey($d)) { return }
        [void]$seen.Add($d, $true)
        $dirs.Add($d)
    }
    Add-Dir (Get-Location).Path
    if ($PSScriptRoot) {
        Add-Dir $PSScriptRoot
        $p = $PSScriptRoot
        for ($i = 0; $i -lt 4; $i++) {
            $parent = Split-Path -Parent $p
            if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $p) { break }
            Add-Dir $parent
            $p = $parent
        }
    }
    foreach ($d in $dirs) {
        $cand = Join-Path $d $keyName
        if (Test-Path -LiteralPath $cand) { return $cand }
    }
    return $null
}

function Find-DefaultComposeFile {
    $roots = New-Object System.Collections.Generic.List[string]
    if ($PSScriptRoot) { [void]$roots.Add($PSScriptRoot) }
    $cwd = (Get-Location).Path
    if (-not $roots.Contains($cwd)) { [void]$roots.Add($cwd) }
    foreach ($base in $roots) {
        foreach ($name in @("docker-compose.prod.yml", "docker-compose.yml")) {
            $cand = Join-Path $base $name
            if (Test-Path -LiteralPath $cand) { return $cand }
        }
    }
    return $null
}

# Procura ficheiro de ambiente para enviar à EC2 (no servidor o nome passa a ser sempre `.env`).
# Ordem: raiz .env.prod → .env → pasta do script backend\.env (o .env típico do Node neste repo).
function Find-DefaultEnvForDeploy {
    $roots = New-Object System.Collections.Generic.List[string]
    function Add-Root([string] $p) {
        if ([string]::IsNullOrWhiteSpace($p)) { return }
        $n = $p.TrimEnd('\', '/')
        foreach ($existing in $roots) {
            if ([string]::Compare($existing, $n, [System.StringComparison]::OrdinalIgnoreCase) -eq 0) {
                return
            }
        }
        [void]$roots.Add($n)
    }
    Add-Root $PSScriptRoot
    Add-Root (Get-Location).Path

    # Relativos à raiz do repositório (primeiro PSScriptRoot = pasta onde está o .ps1).
    $relativeCandidates = @(
        ".env.prod",
        ".env",
        (Join-Path "backend" ".env")
    )

    foreach ($base in $roots) {
        foreach ($rel in $relativeCandidates) {
            $cand = Join-Path $base $rel
            if (Test-Path -LiteralPath $cand) {
                $note = ""
                if ($rel -eq (Join-Path "backend" ".env")) {
                    $note = "A usar backend/.env: o deploy reescreve DATABASE_URL para host ``postgres`` se estiver localhost/127.0.0.1."
                }
                return @{ Path = $cand; Note = $note }
            }
        }
    }
    return $null
}

function Repair-WindowsSshKeyPermissions {
    param([string] $KeyPath)
    if ($env:OS -ne 'Windows_NT') { return }
    if (-not (Get-Command icacls.exe -ErrorAction SilentlyContinue)) { return }
    Write-Host "Ajustando ACL do .pem para o OpenSSH (somente seu usuário pode ler)..." -ForegroundColor DarkGray
    $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls.exe $KeyPath /inheritance:r /c 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERRO: icacls /inheritance:r falhou. Tente manualmente:" -ForegroundColor Red
        Write-Host "  icacls.exe `"$KeyPath`" /inheritance:r /c" -ForegroundColor Yellow
        exit 1
    }
    & icacls.exe $KeyPath /grant:r "${user}:(R)" /c 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERRO: icacls /grant falhou. Tente manualmente:" -ForegroundColor Red
        Write-Host "  icacls.exe `"$KeyPath`" /grant:r `"${user}:(R)`" /c" -ForegroundColor Yellow
        exit 1
    }
    foreach ($sid in @('S-1-5-32-545', 'S-1-5-11')) {
        & icacls.exe $KeyPath /remove:g $sid /c 2>&1 | Out-Null
    }
}

function Escape-BashSingleQuoted {
    param([string] $Value)
    if ($null -eq $Value) { return "''" }
    return "'" + ($Value -replace "'", "'\''") + "'"
}

# Caminho absoluto no servidor (/home/USUARIO/...). Não usar apenas aspas simples em 'mkdir' com '~/...':
# em bash ~ não expande dentro de aspas simples — o diretório não era criado e o scp falhava.
function Get-RemoteDirForScp {
    param(
        [string] $RemoteDir,
        [string] $Ec2User
    )
    if ([string]::IsNullOrWhiteSpace($RemoteDir)) { return $RemoteDir }
    if ($RemoteDir -ceq '~') {
        return "/home/$Ec2User"
    }
    if ($RemoteDir -cmatch '^~/(.*)$') {
        $rest = $Matches[1].TrimEnd('/')
        if ($rest) { return "/home/$Ec2User/$rest" }
        return "/home/$Ec2User"
    }
    return $RemoteDir
}

function Resolve-AbsolutePath {
    param([string] $PathLike)
    if ([string]::IsNullOrWhiteSpace($PathLike)) { return "" }
    if ([System.IO.Path]::IsPathRooted($PathLike)) { return (Resolve-Path -LiteralPath $PathLike).Path }
    return (Resolve-Path -LiteralPath (Join-Path (Get-Location) $PathLike)).Path
}

if ([string]::IsNullOrWhiteSpace($SshKeyPath)) {
    $found = Find-DefaultSshKey
    if ($found) {
        $SshKeyPath = $found
        Write-Host "Chave SSH (auto): $SshKeyPath" -ForegroundColor DarkGray
    }
}

if ([string]::IsNullOrWhiteSpace($SshKeyPath)) {
    Write-Host "ERRO: chave .pem não encontrada." -ForegroundColor Red
    Write-Host "  Opção 1: copie engbot-server.pem para a pasta onde você roda o script (ou para a raiz do outro projeto)." -ForegroundColor Yellow
    Write-Host "  Opção 2: -SshKeyPath `"C:\caminho\completo\engbot-server.pem`"" -ForegroundColor Yellow
    Write-Host "  Opção 3: `$env:EC2_DEPLOY_KEY = `"C:\caminho\completo\engbot-server.pem`"" -ForegroundColor Yellow
    exit 1
}
if ([string]::IsNullOrWhiteSpace($Ec2Host) -and -not [string]::IsNullOrWhiteSpace($DefaultEc2Host)) {
    $Ec2Host = $DefaultEc2Host
    Write-Host "EC2 host (default do script): $Ec2Host" -ForegroundColor DarkGray
}
if ([string]::IsNullOrWhiteSpace($Ec2Host)) {
    Write-Host "ERRO: informe -Ec2Host, ou EC2_DEPLOY_HOST, ou preencha `$DefaultEc2Host neste .ps1." -ForegroundColor Red
    Write-Host "  Ex.: -Ec2Host `"18.191.229.62`"" -ForegroundColor Yellow
    exit 1
}
if ([string]::IsNullOrWhiteSpace($RemoteDir) -and -not [string]::IsNullOrWhiteSpace($DefaultRemoteDir)) {
    $RemoteDir = $DefaultRemoteDir
    Write-Host "Diretório remoto (default do script): $RemoteDir" -ForegroundColor DarkGray
}
if ([string]::IsNullOrWhiteSpace($RemoteDir)) {
    Write-Host "ERRO: informe -RemoteDir, EC2_DEPLOY_REMOTE_DIR, ou defina `$DefaultRemoteDir neste .ps1 (ex.: ~/condo)." -ForegroundColor Red
    exit 1
}
if ([string]::IsNullOrWhiteSpace($ComposeLocalPath)) {
    $foundCompose = Find-DefaultComposeFile
    if ($foundCompose) {
        $ComposeLocalPath = $foundCompose
        Write-Host "Compose (auto): $ComposeLocalPath" -ForegroundColor DarkGray
    }
}
if ([string]::IsNullOrWhiteSpace($ComposeLocalPath)) {
    Write-Host "ERRO: informe -ComposeLocalPath ou coloque docker-compose.prod.yml / docker-compose.yml na pasta atual." -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($EnvLocalPath) -and [string]::IsNullOrWhiteSpace($EnvExampleLocalPath)) {
    $envFound = Find-DefaultEnvForDeploy
    if ($envFound) {
        $EnvLocalPath = $envFound.Path
        Write-Host ".env (auto): $EnvLocalPath" -ForegroundColor DarkGray
        if ($envFound.Note) {
            Write-Host "  $($envFound.Note)" -ForegroundColor Yellow
        }
    }
}

if ([string]::IsNullOrWhiteSpace($EnvLocalPath) -and [string]::IsNullOrWhiteSpace($EnvExampleLocalPath)) {
    $exPath = if ($PSScriptRoot) { Join-Path $PSScriptRoot ".env.prod.example" } else { "" }
    if ($exPath -and (Test-Path -LiteralPath $exPath)) {
        $EnvExampleLocalPath = $exPath
        Write-Host "Só encontrado .env.prod.example (modelo). Enviando como .env.example no servidor." -ForegroundColor Yellow
        Write-Host "  Na EC2: cp .env.example .env e edite, OU crie .env.prod na raiz do PC e rode o script de novo." -ForegroundColor Yellow
    }
}

$keyPath = Resolve-AbsolutePath $SshKeyPath
if (-not (Test-Path -LiteralPath $keyPath)) {
    Write-Host "ERRO: chave SSH não encontrada: $keyPath" -ForegroundColor Red
    exit 1
}

Repair-WindowsSshKeyPermissions -KeyPath $keyPath

$composeFile = Resolve-AbsolutePath $ComposeLocalPath
if (-not (Test-Path -LiteralPath $composeFile)) {
    Write-Host "ERRO: compose não encontrado: $composeFile" -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($RemoteComposeFileName)) {
    $RemoteComposeFileName = Split-Path -Leaf $composeFile
}

$effectiveCondoDockerImage = ""
if (-not [string]::IsNullOrWhiteSpace($CondoDockerImage)) {
    $effectiveCondoDockerImage = $CondoDockerImage.Trim()
}
if ([string]::IsNullOrWhiteSpace($effectiveCondoDockerImage)) {
    $rawDocker = [Environment]::GetEnvironmentVariable("CONDO_DOCKER_IMAGE", "Process")
    if (-not [string]::IsNullOrWhiteSpace($rawDocker)) {
        $effectiveCondoDockerImage = $rawDocker.Trim()
    }
}
if ([string]::IsNullOrWhiteSpace($effectiveCondoDockerImage) -and -not [string]::IsNullOrWhiteSpace($DefaultCondoDockerImage)) {
    $effectiveCondoDockerImage = $DefaultCondoDockerImage.Trim()
}

$remoteComposeQ = Escape-BashSingleQuoted $RemoteComposeFileName
$remoteDirAbs = Get-RemoteDirForScp -RemoteDir $RemoteDir -Ec2User $Ec2User
$remoteDirAbsQ = Escape-BashSingleQuoted $remoteDirAbs

Write-Host "Deploy EC2 (compose genérico)" -ForegroundColor Cyan
Write-Host "${Ec2User}@${Ec2Host} -> $RemoteDir | compose remoto: $RemoteComposeFileName" -ForegroundColor Gray
if ($remoteDirAbs -cne $RemoteDir) {
    Write-Host "(caminho efetivo no servidor: $remoteDirAbs)" -ForegroundColor DarkGray
}
Write-Host ""

Write-Host "Garantindo diretório remoto..." -ForegroundColor Yellow
ssh -i $keyPath -o StrictHostKeyChecking=no "${Ec2User}@${Ec2Host}" "mkdir -p $remoteDirAbsQ"

Write-Host "Enviando $RemoteComposeFileName..." -ForegroundColor Yellow
scp -i $keyPath -o StrictHostKeyChecking=no $composeFile "${Ec2User}@${Ec2Host}:${remoteDirAbs}/${RemoteComposeFileName}"

$envSent = $false
if (-not [string]::IsNullOrWhiteSpace($EnvLocalPath)) {
    $envFile = Resolve-AbsolutePath $EnvLocalPath
    if (Test-Path -LiteralPath $envFile) {
        Write-Host "Enviando .env..." -ForegroundColor Yellow
        $rawEnv = [System.IO.File]::ReadAllText($envFile)
        $mergedEnv = Merge-CondoDockerImageLine -Text $rawEnv -Image $effectiveCondoDockerImage
        $mergedEnv = Repair-DatabaseUrlForDockerNetwork -Text $mergedEnv
        if ($mergedEnv -notmatch '(?m)^\s*CONDO_DOCKER_IMAGE\s*=\s*\S') {
            Write-Host "ERRO: o .env precisa de CONDO_DOCKER_IMAGE (ex.: seu_usuario/condo:latest)." -ForegroundColor Red
            Write-Host "  Opcoes: acrescente a linha ao ficheiro, ou -CondoDockerImage 'user/condo:latest', ou" -ForegroundColor Yellow
            Write-Host "  `$env:CONDO_DOCKER_IMAGE, ou preencha `$DefaultCondoDockerImage no deploy-ec2-compose.ps1" -ForegroundColor Yellow
            exit 1
        }
        if (-not [string]::IsNullOrWhiteSpace($effectiveCondoDockerImage)) {
            if ($rawEnv -match '(?m)^\s*CONDO_DOCKER_IMAGE\s*=\s*\S') {
                Write-Host "  CONDO_DOCKER_IMAGE ja presente no ficheiro." -ForegroundColor DarkGray
            } else {
                Write-Host "  CONDO_DOCKER_IMAGE acrescentado pelo deploy: $effectiveCondoDockerImage" -ForegroundColor DarkGray
            }
        }
        $tmpEnv = Join-Path $env:TEMP ("condo-deploy-env-{0}.env" -f [guid]::NewGuid().ToString("N"))
        try {
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($tmpEnv, $mergedEnv, $utf8NoBom)
            scp -i $keyPath -o StrictHostKeyChecking=no $tmpEnv "${Ec2User}@${Ec2Host}:${remoteDirAbs}/.env"
            $envSent = $true
        } finally {
            if (Test-Path -LiteralPath $tmpEnv) {
                Remove-Item -LiteralPath $tmpEnv -Force -ErrorAction SilentlyContinue
            }
        }
    } else {
        Write-Host "AVISO: -EnvLocalPath não existe: $envFile" -ForegroundColor Yellow
    }
}

if (-not $envSent) {
    $envEx = ""
    if (-not [string]::IsNullOrWhiteSpace($EnvExampleLocalPath)) {
        $envEx = Resolve-AbsolutePath $EnvExampleLocalPath
    }
    if ($envEx -and (Test-Path -LiteralPath $envEx)) {
        Write-Host "Enviando .env.example..." -ForegroundColor Yellow
        scp -i $keyPath -o StrictHostKeyChecking=no $envEx "${Ec2User}@${Ec2Host}:${remoteDirAbs}/.env.example"
        Write-Host "Na EC2: cd $RemoteDir && cp .env.example .env && edite o .env" -ForegroundColor Yellow
    } else {
        Write-Host "AVISO: nenhum .env enviado — o docker compose na EC2 exige `.env` nessa pasta." -ForegroundColor Yellow
        Write-Host "  No PC (raiz do repo): copie o modelo e preencha, depois volte a correr este script:" -ForegroundColor Gray
        Write-Host "    Copy-Item .env.prod.example .env.prod   # depois edite POSTGRES_* e DATABASE_URL como em .env.prod.example" -ForegroundColor Gray
        Write-Host "  Ou coloque `.env` na raiz OU use -EnvLocalPath com o caminho do ficheiro." -ForegroundColor Gray
    }
}

if (-not $SkipUp -and -not $envSent) {
    Write-Host ""
    Write-Host "ERRO: falta `.env` no servidor para `docker compose up`. Envie primeiro um ficheiro (ver avisos acima)." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Arquivos em ${Ec2User}@${Ec2Host}:$remoteDirAbs" -ForegroundColor Green

if ($SkipUp) {
    Write-Host ""
    Write-Host "SkipUp: não executou pull/up no servidor." -ForegroundColor Cyan
    exit 0
}

Write-Host ""
Write-Host "Pull e subindo containers na EC2..." -ForegroundColor Yellow

$remoteCmd = @"
set -e
cd $remoteDirAbsQ
if [ ! -f .env ]; then
  echo 'ERRO: .env não encontrado neste diretório remoto.'
  exit 1
fi
if command -v docker-compose >/dev/null 2>&1; then
  docker-compose -f $remoteComposeQ pull
  docker-compose -f $remoteComposeQ up -d --force-recreate
elif docker compose version >/dev/null 2>&1; then
  docker compose -f $remoteComposeQ pull
  docker compose -f $remoteComposeQ up -d --force-recreate
else
  echo 'ERRO: instale docker-compose ou o plugin docker compose'
  exit 1
fi
echo 'OK: containers atualizados.'
"@
$remoteCmd = ($remoteCmd -replace "`r`n", "`n") -replace "`r", ""
$remoteCmd | ssh -i $keyPath -o StrictHostKeyChecking=no "${Ec2User}@${Ec2Host}" bash -s
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    Write-Host ""
    Write-Host "ERRO: comando remoto falhou (código $exitCode)." -ForegroundColor Red
    exit $exitCode
}

Write-Host ""
Write-Host "Concluído." -ForegroundColor Green
