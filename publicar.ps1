# Compila os APKs, envia os commits e publica a release no GitHub.
#
# A tag vem do `version:` do pubspec.yaml - nao ha numero fixo aqui. Para
# lancar a 1.0.4, suba a versao no pubspec e rode este script; ele cria a
# release se a tag ainda nao existir, ou substitui os APKs se ja existir.
#
# Pre-requisito: autenticar uma vez, no seu terminal:
#     & "C:\Program Files\GitHub CLI\gh.exe" auth login
#
# Depois, na raiz do projeto:
#     powershell -ExecutionPolicy Bypass -File publicar.ps1
#
# Para republicar so os APKs que ja estao em build\publicar\, sem recompilar:
#     powershell -ExecutionPolicy Bypass -File publicar.ps1 -SemCompilar
#
# ATUALIZACAO AUTOMATICA: cada release leva, alem dos APKs, um manifesto por
# app (atualizacao-<applicationId>.json). Os apps instalados consultam o da
# ultima release ao abrir e se atualizam sozinhos (lib/dados/atualizacao.dart).
# Por isso:
#   - suba o numero depois do + no pubspec a cada release: e ele que os apps
#     comparam, e o script recusa publicar se ele nao crescer;
#   - assine sempre com a MESMA chave (android\key.properties; ver README),
#     ou a atualizacao nao entra por cima da versao instalada.

param(
    [switch]$SemCompilar,
    [switch]$SemTestes
)

$ErrorActionPreference = 'Stop'
$gh = 'C:\Program Files\GitHub CLI\gh.exe'
$flutter = Join-Path $env:USERPROFILE 'flutter\bin\flutter.bat'
$apk = 'build\app\outputs\flutter-apk'
$saida = 'build\publicar'
$repo = 'Wiserjr/louvorja'

# Os dois apps que o mesmo codigo gera (productFlavors no build.gradle.kts): o
# Louvor JA completo e o Hinarios, so com os dois hinarios. O prefixo nomeia os
# APKs na release: os dois convivem nela, e nomes iguais se sobrescreveriam.
$apps = @(
    @{ Id = 'br.com.wisejr.louvorja';          Prefixo = 'louvorja'; Flavor = 'louvorja' },
    @{ Id = 'br.com.wisejr.louvorja.hinarios'; Prefixo = 'hinarios'; Flavor = 'hinario' }
)
$abis = @('arm64-v8a', 'armeabi-v7a', 'x86_64')

if (-not (Test-Path $gh)) { throw "gh nao encontrado em $gh" }
if (-not (Test-Path 'pubspec.yaml')) { throw 'Rode na raiz do projeto (pubspec.yaml nao encontrado).' }

# --- versao ---
# "version: 1.0.3+4" -> tag v1.0.3. O que vem depois do + e o versionCode do
# Android e nao entra na tag.
$linha = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(.+)$' | Select-Object -First 1
if (-not $linha) { throw 'Nao achei a linha version: no pubspec.yaml' }
$partes = $linha.Matches[0].Groups[1].Value.Trim().Split('+')
$versao = $partes[0]
if ($partes.Count -lt 2 -or $partes[1] -notmatch '^\d+$') {
    throw 'O version: do pubspec precisa do numero depois do + (ex.: 1.0.10+11).'
}
$codigo = [int]$partes[1]
# Com --split-per-abi o Flutter soma 1000 x arquitetura a este numero; os apps
# comparam so a base, que por isso tem de ficar abaixo de 1000.
if ($codigo -ge 1000) { throw "O numero depois do + passou de 999 ($codigo)." }
$tag = "v$versao"
Write-Output "Versao do pubspec: $versao (versionCode $codigo)  ->  tag $tag"

& $gh auth status
if ($LASTEXITCODE -ne 0) { throw 'Autentique primeiro: gh auth login' }

# --- versao publicada ---
# Os apps so se atualizam se o versionCode crescer. Publicar com o mesmo numero
# de uma versao anterior e o erro que ja travou as atualizacoes da 1.0.0 a
# 1.0.3 - o build passa e ninguem recebe nada. Republicar a MESMA tag e
# permitido (e o caso do -SemCompilar).
$publicado = $null
try {
    $publicado = Invoke-RestMethod "https://github.com/$repo/releases/latest/download/atualizacao-$($apps[0].Id).json"
} catch {
    # Sem manifesto publicado ainda (primeira release com atualizacao
    # automatica) ou sem rede: nada para comparar.
}
if ($publicado) {
    $tagPublicada = & $gh release view --repo $repo --json tagName -q .tagName
    if ($tagPublicada -ne $tag -and $codigo -le [int]$publicado.versionCode) {
        throw "A ultima release ($tagPublicada) ja tem versionCode $($publicado.versionCode). Suba o numero depois do + no pubspec."
    }
}

# --- qualidade ---
# Isto publica para quem vai instalar no celular, entao analise e testes sao
# porteiro, nao formalidade.
if (-not $SemTestes) {
    Write-Output ''
    Write-Output 'Analisando...'
    & $flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'flutter analyze falhou. Corrija antes de publicar.' }

    Write-Output 'Rodando os testes...'
    & $flutter test
    if ($LASTEXITCODE -ne 0) { throw 'Os testes falharam. Corrija antes de publicar.' }
}

# Fora do -SemTestes de proposito. Isto nao mede qualidade de codigo: confere se
# o catalogo que vai dentro do APK esta completo. A atualizacao do programa base
# apaga as edicoes da Biblia Livre do banco do desktop, e nada nesse caminho
# reclama - o build passa e a release sai sem elas. Custa um segundo.
Write-Output ''
Write-Output 'Conferindo o catalogo...'
python ferramentas\conferir_catalogo.py
if ($LASTEXITCODE -ne 0) { throw 'Catalogo reprovado. Veja acima o que falta.' }

# --- assinatura ---
# A atualizacao automatica so entra por cima se o APK novo tiver a MESMA chave do
# instalado. Sem key.properties o APK sai com a chave de debug deste PC: vale
# enquanto se publicar sempre daqui.
if (-not (Test-Path 'android\key.properties')) {
    Write-Warning ('Sem android\key.properties: os APKs saem com a chave de debug deste PC. ' +
        'Publicar de outro PC quebra a atualizacao automatica de todo mundo. Ver README, "Chave de assinatura".')
}

# --- compilacao ---
# Os dois apps, cada um nas tres arquiteturas. O app-release.apk generico fica
# de fora: ele e apenas o x86_64 da ultima compilacao de teste. Cada build
# sobrescreve build\app\outputs, entao os APKs sao copiados para build\publicar
# ja com o nome final antes do proximo.
if (-not $SemCompilar) {
    if (Test-Path $saida) { Remove-Item $saida -Recurse -Force }
    New-Item -ItemType Directory -Path $saida | Out-Null
    foreach ($app in $apps) {
        Write-Output ''
        Write-Output "Compilando $($app.Prefixo)..."
        & $flutter build apk --release --split-per-abi --flavor "$($app.Flavor)"
        if ($LASTEXITCODE -ne 0) { throw "A compilacao de $($app.Prefixo) falhou." }
        foreach ($abi in $abis) {
            Copy-Item "$apk\app-$abi-$($app.Flavor)-release.apk" "$saida\$($app.Prefixo)-$abi.apk"
        }
    }
}

# --- manifestos da atualizacao automatica ---
# Um por app, com o applicationId no nome: os dois convivem no aparelho e um nao
# pode receber o APK do outro. Os links apontam para ESTA tag; o app so aceita
# links de releases deste repositorio (ver interpretarManifesto).
$arquivos = @()
foreach ($app in $apps) {
    $links = [ordered]@{}
    foreach ($abi in $abis) {
        $nome = "$($app.Prefixo)-$abi.apk"
        if (-not (Test-Path "$saida\$nome")) {
            throw "APK ausente: $saida\$nome. Rode sem -SemCompilar."
        }
        $arquivos += "$saida\$nome"
        $links[$abi] = "https://github.com/$repo/releases/download/$tag/$nome"
    }
    $manifesto = [ordered]@{
        applicationId = $app.Id
        versionCode   = $codigo
        versionName   = $versao
        apks          = $links
    }
    $caminho = Join-Path (Resolve-Path $saida) "atualizacao-$($app.Id).json"
    # Sem BOM: o Set-Content -Encoding UTF8 do PowerShell 5 poe um, e JSON com
    # BOM e rejeitado por muitos leitores.
    [System.IO.File]::WriteAllText($caminho, ($manifesto | ConvertTo-Json -Depth 3),
        (New-Object System.Text.UTF8Encoding $false))
    $arquivos += $caminho
}

# --- commits ---
Write-Output ''
Write-Output 'Enviando os commits...'
git push origin main
if ($LASTEXITCODE -ne 0) { throw 'git push falhou.' }

# --- release ---
$jaExiste = & $gh release view $tag --json tagName
if ($LASTEXITCODE -ne 0) {
    Write-Output "Criando a release $tag..."
    & $gh release create $tag $arquivos --title "LouvorJA para Android $versao" --notes-file '.github\RELEASE_NOTES.md'
} else {
    Write-Output "Release $tag ja existe; substituindo os APKs e as notas..."
    & $gh release upload $tag $arquivos --clobber
    & $gh release edit $tag --notes-file '.github\RELEASE_NOTES.md'
}
if ($LASTEXITCODE -ne 0) { throw 'Falha ao publicar a release.' }

Write-Output ''
Write-Output 'Pronto. Links:'
& $gh repo view --json url -q .url
& $gh release view $tag --json url -q .url
Write-Output ''
Write-Output 'O repositorio e publico: o link da release baixa direto, sem login.'
Write-Output 'Na duvida sobre qual APK indicar, use o arm64-v8a.'
Write-Output 'Quem ja tem o app instalado recebe esta versao sozinho, ao abrir o app.'
