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
    @{ Id = 'br.com.wisejr.louvorja'; Prefixo = 'louvorja'; Flavor = 'louvorja'
       Fonte = 'pubspec'; TagPrefixo = 'v'
       Titulo = 'LouvorJA para Android'; Notas = '.github\RELEASE_NOTES.md' },
    @{ Id = 'br.com.wisejr.louvorja.hinarios'; Prefixo = 'hinarios'; Flavor = 'hinario'
       Fonte = 'versoes'; TagPrefixo = 'hinarios-v'
       Titulo = 'Hinarios'; Notas = '.github\RELEASE_NOTES_HINARIOS.md' }
)

# A tag fixa que guarda os manifestos da atualizacao automatica, fora do ciclo
# de versao dos apps. Ver o comentario em lib/dados/atualizacao.dart: com
# `releases/latest` os dois apps ficavam presos ao mesmo ciclo, porque so uma
# release pode ser a mais recente.
$tagManifestos = 'atualizacao'
$abis = @('arm64-v8a', 'armeabi-v7a', 'x86_64')

if (-not (Test-Path $gh)) { throw "gh nao encontrado em $gh" }
if (-not (Test-Path 'pubspec.yaml')) { throw 'Rode na raiz do projeto (pubspec.yaml nao encontrado).' }

# --- versao de cada app ---
# Cada app anda no seu ritmo. O Louvor JA usa o `version:` do pubspec.yaml; o
# Hinarios, que muda poucas vezes por ano, usa o versoes.json - assim publicar
# um nao obriga a republicar o outro.
if (-not (Test-Path 'versoes.json')) { throw 'versoes.json nao encontrado.' }
foreach ($app in $apps) {
    if (-not (Test-Path $app.Notas)) { throw "Notas ausentes: $($app.Notas)" }
}
$versoes = Get-Content 'versoes.json' -Raw | ConvertFrom-Json

foreach ($app in $apps) {
    if ($app.Fonte -eq 'pubspec') {
        $linha = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(.+)$' | Select-Object -First 1
        if (-not $linha) { throw 'Nao achei a linha version: no pubspec.yaml' }
        $partes = $linha.Matches[0].Groups[1].Value.Trim().Split('+')
        if ($partes.Count -lt 2 -or $partes[1] -notmatch '^\d+$') {
            throw 'O version: do pubspec precisa do numero depois do + (ex.: 1.0.10+11).'
        }
        $app.Versao = $partes[0]
        $app.Codigo = [int]$partes[1]
    } else {
        $v = $versoes.($app.Prefixo)
        if (-not $v) { throw "versoes.json nao tem a entrada '$($app.Prefixo)'." }
        $app.Versao = [string]$v.versao
        $app.Codigo = [int]$v.codigo
    }
    # Com --split-per-abi o Flutter soma 1000 x arquitetura a este numero; os
    # apps comparam so a base, que por isso tem de ficar abaixo de 1000.
    if ($app.Codigo -ge 1000) { throw "O versionCode de $($app.Prefixo) passou de 999 ($($app.Codigo))." }
    $app.Tag = "$($app.TagPrefixo)$($app.Versao)"
    Write-Output ("{0,-9} {1} (versionCode {2})  ->  tag {3}" -f $app.Prefixo, $app.Versao, $app.Codigo, $app.Tag)
}

& $gh auth status
if ($LASTEXITCODE -ne 0) { throw 'Autentique primeiro: gh auth login' }

# --- versao publicada ---
# Os apps so se atualizam se o versionCode crescer. Publicar com o mesmo numero
# de uma versao anterior e o erro que ja travou as atualizacoes da 1.0.0 a
# 1.0.3 - o build passa e ninguem recebe nada. Republicar a MESMA tag e
# permitido (e o caso do -SemCompilar).
foreach ($app in $apps) {
    $pub = $null
    try {
        $pub = Invoke-RestMethod "https://github.com/$repo/releases/download/$tagManifestos/atualizacao-$($app.Id).json"
    } catch {
        # Sem manifesto publicado ainda, ou sem rede: nada para comparar.
    }
    if ($pub -and $app.Codigo -lt [int]$pub.versionCode) {
        throw "$($app.Prefixo) publicado tem versionCode $($pub.versionCode) e aqui esta $($app.Codigo). O numero nunca pode diminuir."
    }
    # Igual significa 'nada mudou neste app': republicar e inofensivo, mas nao
    # ha release nova a criar. E o caso normal do Hinarios.
    $app.Mudou = (-not $pub) -or ($app.Codigo -gt [int]$pub.versionCode)
    if (-not $app.Mudou) {
        Write-Output "$($app.Prefixo): sem versao nova (versionCode $($app.Codigo) ja publicado) - nao sai release."
    }
}
if (-not ($apps | Where-Object { $_.Mudou })) {
    Write-Output ''
    Write-Output 'Nenhum app tem versao nova. Suba o numero de quem voce quer publicar.'
    return
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
    foreach ($app in $apps | Where-Object { $_.Mudou }) {
        Write-Output ''
        Write-Output "Compilando $($app.Prefixo) $($app.Versao)..."
        # --build-name/--build-number vencem o pubspec: e assim que o Hinarios
        # recebe a versao do versoes.json sem um pubspec proprio.
        & $flutter build apk --release --split-per-abi --flavor "$($app.Flavor)" `
            --build-name "$($app.Versao)" --build-number "$($app.Codigo)"
        if ($LASTEXITCODE -ne 0) { throw "A compilacao de $($app.Prefixo) falhou." }
        foreach ($abi in $abis) {
            Copy-Item "$apk\app-$abi-$($app.Flavor)-release.apk" "$saida\$($app.Prefixo)-$abi.apk"
        }
    }
}

# --- conferencia dos APKs ---
# O -SemCompilar reaproveita build\publicar\, e essa pasta sobrevive entre
# versoes. Na v1.0.11 ela guardava a compilacao da 1.0.10: a release saiu com o
# manifesto anunciando 12 e os binarios em 11, e todo mundo que tentou se
# atualizar recebeu "O arquivo baixado nao corresponde a esta atualizacao".
# Conferir o que esta na pasta custa um segundo e nao depende de lembrar.
$aapt = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Android\Sdk\build-tools\*\aapt2.exe') -ErrorAction SilentlyContinue |
    Sort-Object FullName | Select-Object -Last 1
if (-not $aapt) {
    if ($SemCompilar) {
        throw ('Sem aapt2 para conferir os APKs de build\publicar\, e -SemCompilar reaproveita o que estiver la. ' +
               'Rode sem -SemCompilar para compilar do zero.')
    }
} else {
    Write-Output ''
    Write-Output 'Conferindo os APKs...'
    foreach ($app in $apps | Where-Object { $_.Mudou }) {
        foreach ($abi in $abis) {
            $arq = "$saida\$($app.Prefixo)-$abi.apk"
            if (-not (Test-Path $arq)) { throw "APK ausente: $arq. Rode sem -SemCompilar." }
            $info = & $aapt.FullName dump badging $arq | Select-Object -First 1
            if ($info -notmatch "versionCode='(\d+)'") { throw "Nao consegui ler o versionCode de $arq." }
            $base = [int]$Matches[1] % 1000
            if ($base -ne $app.Codigo) {
                throw ("$arq tem versionCode base $base, mas $($app.Prefixo) esta sendo publicado como $($app.Codigo). " +
                       'Rode sem -SemCompilar: a pasta tem binarios de outra versao.')
            }
        }
        Write-Output "  $($app.Prefixo): os tres APKs estao na versao $($app.Codigo)."
    }
}

# --- commits ---
Write-Output ''
Write-Output 'Enviando os commits...'
git push origin main
if ($LASTEXITCODE -ne 0) { throw 'git push falhou.' }

# --- release de cada app que mudou ---
# Uma release por app, com tag propria. Os APKs de cada um vao na sua, e o
# manifesto aponta para la.
foreach ($app in $apps | Where-Object { $_.Mudou }) {
    $arquivos = @()
    $links = [ordered]@{}
    foreach ($abi in $abis) {
        $nome = "$($app.Prefixo)-$abi.apk"
        if (-not (Test-Path "$saida\$nome")) {
            throw "APK ausente: $saida\$nome. Rode sem -SemCompilar."
        }
        $arquivos += "$saida\$nome"
        $links[$abi] = "https://github.com/$repo/releases/download/$($app.Tag)/$nome"
    }
    $manifesto = [ordered]@{
        applicationId = $app.Id
        versionCode   = $app.Codigo
        versionName   = $app.Versao
        apks          = $links
    }
    $caminho = Join-Path (Resolve-Path $saida) "atualizacao-$($app.Id).json"
    # Sem BOM: o Set-Content -Encoding UTF8 do PowerShell 5 poe um, e JSON com
    # BOM e rejeitado por muitos leitores.
    [System.IO.File]::WriteAllText($caminho, ($manifesto | ConvertTo-Json -Depth 3),
        (New-Object System.Text.UTF8Encoding $false))
    $app.Manifesto = $caminho

    # O manifesto vai TAMBEM na release de versao, nao so na tag fixa: os apps
    # ate a 1.0.11 leem `releases/latest`, e so passam a ler a tag fixa depois
    # de instalarem esta. Enquanto houver gente na versao antiga, os dois
    # lugares precisam estar certos.
    $arquivos += $caminho
    Write-Output ''
    Write-Output "Publicando $($app.Prefixo) $($app.Versao)..."
    # O selo Latest pertence ao Louvor JA, sempre. Os apps ate a 1.0.11 leem
    # `releases/latest/download/atualizacao-{pacote}.json`: se o Hinarios ficar
    # como Latest - e fica, por ser publicado depois -, o Louvor JA instalado
    # procura o seu manifesto numa release que so tem o do outro app, recebe
    # 404 e nunca mais se atualiza.
    $ehPrincipal = ($app.Fonte -eq 'pubspec')
    $jaExiste = & $gh release view $app.Tag --json tagName
    if ($LASTEXITCODE -ne 0) {
        & $gh release create $app.Tag $arquivos --title "$($app.Titulo) $($app.Versao)" `
            --notes-file $app.Notas "--latest=$($ehPrincipal.ToString().ToLower())"
    } else {
        & $gh release upload $app.Tag $arquivos --clobber
        & $gh release edit $app.Tag --notes-file $app.Notas `
            "--latest=$($ehPrincipal.ToString().ToLower())"
    }
    if ($LASTEXITCODE -ne 0) { throw "Falha ao publicar $($app.Prefixo)." }
}

# --- manifestos na tag fixa ---
# E daqui que os apps a partir da 1.0.12 leem. A tag nunca muda, entao cada
# manifesto se move quando o seu app se move - que e o ponto de separar os
# ciclos. Nao e marcada como Latest: o selo pertence ao Louvor JA.
$manifestos = @($apps | Where-Object { $_.Mudou } | ForEach-Object { $_.Manifesto })
Write-Output ''
Write-Output 'Atualizando os manifestos na tag fixa...'
$temTag = & $gh release view $tagManifestos --json tagName
if ($LASTEXITCODE -ne 0) {
    & $gh release create $tagManifestos $manifestos --title 'Atualizacao automatica' --latest=false `
        --notes 'Manifestos que os apps consultam ao abrir para saber se ha versao nova. Nao ha nada para baixar aqui a mao - os APKs estao nas releases de versao.'
} else {
    & $gh release upload $tagManifestos $manifestos --clobber
}
if ($LASTEXITCODE -ne 0) { throw 'Falha ao atualizar os manifestos.' }

Write-Output ''
Write-Output 'Pronto. Links:'
& $gh repo view --json url -q .url
foreach ($app in $apps | Where-Object { $_.Mudou }) {
    & $gh release view $app.Tag --json url -q .url
}
Write-Output ''
Write-Output 'O repositorio e publico: o link da release baixa direto, sem login.'
Write-Output 'Na duvida sobre qual APK indicar, use o arm64-v8a.'
Write-Output 'Quem ja tem o app instalado recebe esta versao sozinho, ao abrir o app.'
