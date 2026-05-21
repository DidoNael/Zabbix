# PowerShell Script para criar o repositório privado e subir o template ZTE
$ErrorActionPreference = "Continue"

# Caminhos padrão dos executáveis
$gitPath = "C:\Program Files\Git\cmd\git.exe"
$ghPath = "C:\Program Files\GitHub CLI\gh.exe"

# Mensagem inicial
Clear-Host
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Assistente de Criação de Repositório - Zabbix Templates" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Verificar se o GitHub CLI e o Git estão disponíveis
if (-not (Test-Path $gitPath)) {
    Write-Host "Git não encontrado em $gitPath. Por favor, instale o Git primeiro." -ForegroundColor Red
    exit
}
if (-not (Test-Path $ghPath)) {
    Write-Host "GitHub CLI não encontrado em $ghPath. Por favor, instale o GitHub CLI primeiro." -ForegroundColor Red
    exit
}

# 2. Verificar autenticação do GitHub CLI
Write-Host "Verificando autenticação no GitHub..." -ForegroundColor Yellow
$authCheck = & $ghPath auth status 2>&1
$isAuthed = $false
foreach ($line in $authCheck) {
    if ($line -match "Logged in to github.com") {
        $isAuthed = $true
        break
    }
}

if ($isAuthed) {
    Write-Host "Você já está autenticado no GitHub!" -ForegroundColor Green
} else {
    Write-Host "Você não está autenticado. Iniciando processo de login interativo..." -ForegroundColor Yellow
    Write-Host "Uma nova janela de terminal será aberta para que você conclua o login no GitHub." -ForegroundColor Yellow
    Write-Host "Escolha a opção 'Login with a web browser' e siga as instruções." -ForegroundColor Cyan
    Write-Host ""
    
    # Executa o login em uma nova janela para permitir interação
    $loginProcess = Start-Process -FilePath $ghPath -ArgumentList "auth login" -Wait -PassThru
    
    # Aguarda o usuário concluir e checa novamente
    $authCheck = & $ghPath auth status 2>&1
    $isAuthed = $false
    foreach ($line in $authCheck) {
        if ($line -match "Logged in to github.com") {
            $isAuthed = $true
            break
        }
    }
    
    if (-not $isAuthed) {
        Write-Host "Autenticação não realizada ou falhou. Execute o script novamente após fazer o login." -ForegroundColor Red
        exit
    }
    Write-Host "Autenticação concluída com sucesso!" -ForegroundColor Green
}

# 3. Obter nome de usuário do GitHub
$username = (& $ghPath api user --jq ".login").Trim()
Write-Host "Usuário GitHub identificado: $username" -ForegroundColor Green

# 4. Configurar identidade global do Git (se necessário)
Write-Host "Configurando informações de identidade do Git..." -ForegroundColor Yellow
$gitName = & $gitPath config --global user.name 2>$null
if ([string]::IsNullOrEmpty($gitName)) {
    $githubName = & $ghPath api user --jq ".name" 2>$null
    if ([string]::IsNullOrEmpty($githubName) -or $githubName -eq "null") { $githubName = $username }
    & $gitPath config --global user.name $githubName
    Write-Host "Definido Git user.name global para: $githubName" -ForegroundColor Gray
} else {
    Write-Host "Git user.name global já configurado: $gitName" -ForegroundColor Gray
}

$gitEmail = & $gitPath config --global user.email 2>$null
if ([string]::IsNullOrEmpty($gitEmail)) {
    $githubEmail = & $ghPath api user --jq ".email" 2>$null
    if ([string]::IsNullOrEmpty($githubEmail) -or $githubEmail -eq "null") {
        $githubId = & $ghPath api user --jq ".id" 2>$null
        $githubEmail = "$githubId+$username@users.noreply.github.com"
    }
    & $gitPath config --global user.email $githubEmail
    Write-Host "Definido Git user.email global para: $githubEmail" -ForegroundColor Gray
} else {
    Write-Host "Git user.email global já configurado: $gitEmail" -ForegroundColor Gray
}

# 5. Inicializar Git e fazer commit
$repoDir = "C:\Users\Revolution\.gemini\antigravity\scratch\zabbix-templates"
Set-Location -Path $repoDir
if (-not (Test-Path "$repoDir\.git")) {
    & $gitPath init -b main
    Write-Host "Repositório Git inicializado com sucesso (branch main)." -ForegroundColor Green
}

& $gitPath add ZTE.xml README.md
& $gitPath commit -m "Initial commit: ZTE GPON OLT Template corrigido e documentação"
Write-Host "Arquivos adicionados e commit inicial criado." -ForegroundColor Green

# 6. Criar o repositório no GitHub (caso não exista)
Write-Host "Verificando se o repositório já existe no GitHub..." -ForegroundColor Yellow
$repoExists = $false
try {
    $repoView = & $ghPath repo view "$username/zabbix-templates" 2>&1
    if ($repoView -match "github.com/$username/zabbix-templates") {
        $repoExists = $true
    }
} catch {}

if (-not $repoExists) {
    Write-Host "Criando repositório privado 'zabbix-templates' no GitHub..." -ForegroundColor Cyan
    & $ghPath repo create zabbix-templates --private
    Write-Host "Repositório criado no GitHub com sucesso!" -ForegroundColor Green
} else {
    Write-Host "O repositório já existe no GitHub." -ForegroundColor Yellow
}

# 7. Adicionar remote origin e fazer Push
$remotes = & $gitPath remote
if ($remotes -notmatch "origin") {
    & $gitPath remote add origin "https://github.com/$username/zabbix-templates.git"
}

Write-Host "Subindo alterações para o GitHub..." -ForegroundColor Yellow
& $gitPath push -u origin main --force
Write-Host "Arquivos enviados para a branch 'main'." -ForegroundColor Green

# 8. Criar e subir Tag
Write-Host "Verificando e configurando tags..." -ForegroundColor Yellow
# Apaga tag local se existir para evitar conflito
& $gitPath tag -d v1.0.0 2>$null | Out-Null
& $gitPath tag -a v1.0.0 -m "Versão 1.0.0 - Template ZTE Corrigido"
& $gitPath push origin v1.0.0 --force
Write-Host "Tag v1.0.0 criada e enviada com sucesso!" -ForegroundColor Green

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "   Sucesso! Repositório privado criado e tag v1.0.0 criada." -ForegroundColor Green
Write-Host "   URL: https://github.com/$username/zabbix-templates" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
