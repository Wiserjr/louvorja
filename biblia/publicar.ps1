# Bíblia de Estudo: compila Android e Windows, envia os commits e publica a
# release no GitHub, com o manifesto da atualizacao automatica.
#
# A versao vem do `version:` do pubspec.yaml. Para lancar a 1.0.1, suba a
# versao no pubspec (o numero depois do + TAMBEM) e rode este script; ele cria
# a release se a tag ainda nao existir, ou substitui os arquivos se ja existir.
#
# Pre-requisitos, uma vez:
#     & "C:\Program Files\GitHub CLI\gh.exe" auth login
#     Visual Studio com "Desenvolvimento para desktop com C++" (build Windows)
#
# Depois, dentro da pasta biblia\:
#     powershell -ExecutionPolicy Bypass -File publicar.ps1
#
# Opcoes:
#     -SemCompilar   republica o que ja esta em build\publicar\
#     -SemTestes     pula analyze e testes (nao recomendado)
#     -SoAndroid     nao compila nem publica o Windows
#
# ATUALIZACAO AUTOMATICA (lib/dados/atualizacao.dart):
#   - Este app mora no MESMO repositorio do Louvor JA. A release "latest" e
#     do Louvor JA (os apps dele procuram o manifesto la), entao as releases
#     da Biblia sao criadas com --latest=false, e o manifesto vai para uma
#     release fixa, "biblia-atual", que este script regrava a cada versao.
#   - Os apps instalados consultam
#       releases/download/biblia-atual/atualizacao-br.com.wisejr.bibliaestudo.json
#   - Suba o numero depois do + a cada release: e ele que os apps comparam, e
#     o script recusa publicar se ele nao crescer.
#   - Assine sempre com a MESMA chave (android\key.properties; ver README), ou
#     a atualizacao nao entra por cima da versao instalada.

param(
    [switch]$SemCompilar,
    [switch]$SemTestes,
    [switch]$SoAndroid
)

$ErrorActionPreference = 'Stop'
$gh = 'C:\Program Files\GitHub CLI\gh.exe'
$flutter = Join-Path $env:USERPROFILE 'flutter\bin\flutter.bat'
$apk = 'build\app\outputs\flutter-apk'
$windows = 'build\windows\x64\runner\Release'
$saida = 'build\publicar'
$repo = 'Wiserjr/louvorja'
$id = 'br.com.wisejr.bibliaestudo'
$canal = 'biblia-atual'
$prefixo = 'biblia'
$abis = @('arm64-v8a', 'armeabi-v7a', 'x86_64')

if (-not (Test-Path $gh)) { throw "gh nao encontrado em $gh" }
if (-not (Test-Path 'pubspec.yaml')) { throw 'Rode dentro da pasta biblia (pubspec.yaml nao encontrado).' }

# --- versao ---
$linha = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(.+)$' | Select-Object -First 1
if (-not $linha) { throw 'Nao achei a linha version: no pubspec.yaml' }
$partes = $linha.Matches[0].Groups[1].Value.Trim().Split('+')
$versao = $partes[0]
if ($partes.Count -lt 2 -or $partes[1] -notmatch '^\d+$') {
    throw 'O version: do pubspec precisa do numero depois do + (ex.: 1.0.1+2).'
}
$codigo = [int]$partes[1]
# Com --split-per-abi o Flutter soma 1000 x arquitetura a este numero; os apps
# comparam so a base, que por isso tem de ficar abaixo de 1000.
if ($codigo -ge 1000) { throw "O numero depois do + passou de 999 ($codigo)." }
$tag = "biblia-v$versao"
Write-Output "Versao do pubspec: $versao (versionCode $codigo)  ->  tag $tag"

& $gh auth status
if ($LASTEXITCODE -ne 0) { throw 'Autentique primeiro: gh auth login' }

# --- versao publicada ---
# Publicar com o mesmo numero de uma versao anterior deixa todo mundo sem
# atualizacao, em silencio. Republicar a MESMA versao e permitido.
$publicado = $null
try {
    $publicado = Invoke-RestMethod "https://github.com/$repo/releases/download/$canal/atualizacao-$id.json"
} catch {
    # Primeira publicacao, ou sem rede.
}
if ($publicado -and $publicado.versionName -ne $versao -and $codigo -le [int]$publicado.versionCode) {
    throw "A versao publicada ($($publicado.versionName)) ja tem versionCode $($publicado.versionCode). Suba o numero depois do + no pubspec."
}

# --- qualidade ---
if (-not $SemTestes) {
    Write-Output ''
    Write-Output 'Analisando...'
    & $flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'flutter analyze falhou. Corrija antes de publicar.' }
    Write-Output 'Rodando os testes...'
    & $flutter test
    if ($LASTEXITCODE -ne 0) { throw 'Os testes falharam. Corrija antes de publicar.' }
    python -m unittest ferramentas\test_referencias_pt.py ferramentas\test_texto_pdf.py
    if ($LASTEXITCODE -ne 0) { throw 'Os testes das ferramentas falharam.' }
}

foreach ($a in @('assets\biblia.db.gz', 'assets\estudo.db.gz')) {
    if (-not (Test-Path $a)) { throw "Falta $a. Veja o README (ferramentas)." }
}

# --- assinatura ---
if (-not (Test-Path 'android\key.properties')) {
    Write-Warning ('Sem android\key.properties: os APKs saem com a chave de debug deste PC. ' +
        'Publicar de outro PC quebra a atualizacao automatica de todo mundo. Ver README, "Chave de assinatura".')
}

# --- compilacao ---
if (-not $SemCompilar) {
    if (Test-Path $saida) { Remove-Item $saida -Recurse -Force }
    New-Item -ItemType Directory -Path $saida | Out-Null

    Write-Output ''
    Write-Output 'Compilando Android...'
    & $flutter build apk --release --split-per-abi
    if ($LASTEXITCODE -ne 0) { throw 'A compilacao Android falhou.' }
    foreach ($abi in $abis) {
        Copy-Item "$apk\app-$abi-release.apk" "$saida\$prefixo-$abi.apk"
    }

    if (-not $SoAndroid) {
        Write-Output ''
        Write-Output 'Compilando Windows...'
        & $flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw 'A compilacao Windows falhou.' }
        # versao.json no zip: o app confere, antes de trocar os arquivos, que
        # o zip baixado e deste app e da versao anunciada.
        $v = [ordered]@{ applicationId = $id; versionCode = $codigo; versionName = $versao }
        [System.IO.File]::WriteAllText((Join-Path (Resolve-Path $windows) 'versao.json'),
            ($v | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))
        $zip = Join-Path (Resolve-Path $saida) "$prefixo-windows.zip"
        if (Test-Path $zip) { Remove-Item $zip }
        Compress-Archive -Path "$windows\*" -DestinationPath $zip
    }
}

# --- manifesto da atualizacao automatica ---
$arquivos = @()
$links = [ordered]@{}
foreach ($abi in $abis) {
    $nome = "$prefixo-$abi.apk"
    if (-not (Test-Path "$saida\$nome")) { throw "APK ausente: $saida\$nome. Rode sem -SemCompilar." }
    $arquivos += "$saida\$nome"
    $links[$abi] = "https://github.com/$repo/releases/download/$tag/$nome"
}
$manifesto = [ordered]@{
    applicationId = $id
    versionCode   = $codigo
    versionName   = $versao
    apks          = $links
}
if (Test-Path "$saida\$prefixo-windows.zip") {
    $arquivos += "$saida\$prefixo-windows.zip"
    $manifesto.windows = "https://github.com/$repo/releases/download/$tag/$prefixo-windows.zip"
} elseif ($publicado -and $publicado.windows) {
    Write-Warning 'Esta versao sai sem Windows: quem usa no PC continua na versao anterior.'
}
$caminhoManifesto = Join-Path (Resolve-Path $saida) "atualizacao-$id.json"
# Sem BOM: o PowerShell 5 poe um, e JSON com BOM e rejeitado por muitos leitores.
[System.IO.File]::WriteAllText($caminhoManifesto, ($manifesto | ConvertTo-Json -Depth 3),
    (New-Object System.Text.UTF8Encoding $false))

# --- commits ---
Write-Output ''
Write-Output 'Enviando os commits...'
git push origin main
if ($LASTEXITCODE -ne 0) { throw 'git push falhou.' }

# --- release da versao ---
# --latest=false: a "latest" do repositorio e do Louvor JA.
$notas = 'NOTAS_DA_VERSAO.md'
& $gh release view $tag --repo $repo --json tagName 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Output "Criando a release $tag..."
    & $gh release create $tag $arquivos $caminhoManifesto --repo $repo --latest=false `
        --title "Biblia de Estudo $versao" --notes-file $notas
} else {
    Write-Output "Release $tag ja existe; substituindo os arquivos..."
    & $gh release upload $tag $arquivos $caminhoManifesto --repo $repo --clobber
    & $gh release edit $tag --repo $repo --notes-file $notas
}
if ($LASTEXITCODE -ne 0) { throw 'Falha ao publicar a release.' }

# --- canal da atualizacao ---
# O manifesto vai por ULTIMO: se algo acima falhar, os apps continuam vendo a
# versao anterior, cujos arquivos existem.
& $gh release view $canal --repo $repo --json tagName 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    & $gh release create $canal $caminhoManifesto --repo $repo --prerelease --latest=false `
        --title 'Biblia de Estudo - canal de atualizacao' `
        --notes 'Manifesto lido pelos apps instalados. Os instaladores estao nas releases biblia-v*.'
} else {
    & $gh release upload $canal $caminhoManifesto --repo $repo --clobber
}
if ($LASTEXITCODE -ne 0) { throw 'Falha ao publicar o manifesto da atualizacao.' }

Write-Output ''
Write-Output 'Pronto:'
& $gh release view $tag --repo $repo --json url -q .url
Write-Output 'Quem ja tem o app instalado recebe esta versao sozinho, ao abrir o app.'
