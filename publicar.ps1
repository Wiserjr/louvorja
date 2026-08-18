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
# Para republicar so os APKs que ja estao em build\, sem recompilar:
#     powershell -ExecutionPolicy Bypass -File publicar.ps1 -SemCompilar

param(
    [switch]$SemCompilar,
    [switch]$SemTestes
)

$ErrorActionPreference = 'Stop'
$gh = 'C:\Program Files\GitHub CLI\gh.exe'
$flutter = Join-Path $env:USERPROFILE 'flutter\bin\flutter.bat'
$apk = 'build\app\outputs\flutter-apk'

if (-not (Test-Path $gh)) { throw "gh nao encontrado em $gh" }
if (-not (Test-Path 'pubspec.yaml')) { throw 'Rode na raiz do projeto (pubspec.yaml nao encontrado).' }

# --- versao ---
# "version: 1.0.3+4" -> tag v1.0.3. O que vem depois do + e o versionCode do
# Android e nao entra na tag.
$linha = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(.+)$' | Select-Object -First 1
if (-not $linha) { throw 'Nao achei a linha version: no pubspec.yaml' }
$versao = $linha.Matches[0].Groups[1].Value.Trim().Split('+')[0]
$tag = "v$versao"
Write-Output "Versao do pubspec: $versao  ->  tag $tag"

& $gh auth status
if ($LASTEXITCODE -ne 0) { throw 'Autentique primeiro: gh auth login' }

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

# --- compilacao ---
# Os tres APKs por arquitetura. O app-release.apk generico fica de fora: ele e
# apenas o x86_64 da ultima compilacao de teste, nao serve para celular.
$arquivos = @(
    "$apk\app-arm64-v8a-release.apk",
    "$apk\app-armeabi-v7a-release.apk",
    "$apk\app-x86_64-release.apk"
)

if (-not $SemCompilar) {
    Write-Output ''
    Write-Output 'Compilando os APKs...'
    & $flutter build apk --release --split-per-abi
    if ($LASTEXITCODE -ne 0) { throw 'A compilacao falhou.' }
}

foreach ($a in $arquivos) {
    if (-not (Test-Path $a)) {
        throw "APK ausente: $a. Rode sem -SemCompilar, ou: flutter build apk --release --split-per-abi"
    }
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
