# Publica o projeto no GitHub e cria a release com os APKs.
#
# Pre-requisito: autenticar uma vez, no seu terminal:
#     & "C:\Program Files\GitHub CLI\gh.exe" auth login
#
# Depois, rode este script na raiz do projeto:
#     powershell -ExecutionPolicy Bypass -File publicar.ps1

$ErrorActionPreference = 'Stop'
$gh = 'C:\Program Files\GitHub CLI\gh.exe'
$apk = 'build\app\outputs\flutter-apk'

if (-not (Test-Path $gh)) { throw "gh nao encontrado em $gh" }

& $gh auth status
if ($LASTEXITCODE -ne 0) { throw 'Autentique primeiro: gh auth login' }

# --- repositorio ---
$existe = & $gh repo view louvorja --json name 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Output 'Criando o repositorio privado...'
  & $gh repo create louvorja `
      --private `
      --source=. `
      --remote=origin `
      --push `
      --description 'App Android offline com o acervo do LouvorJA: albuns, hinarios, letra sincronizada, Biblia e coletaneas on-line'
} else {
  Write-Output 'Repositorio ja existe; enviando os commits...'
  git push -u origin main
}

# --- release com os APKs ---
# Os tres APKs por arquitetura. O app-release.apk generico fica de fora: ele e
# apenas o x86_64 da ultima compilacao de teste, nao serve para celular.
$arquivos = @(
  "$apk\app-arm64-v8a-release.apk",
  "$apk\app-armeabi-v7a-release.apk",
  "$apk\app-x86_64-release.apk"
)
foreach ($a in $arquivos) {
  if (-not (Test-Path $a)) { throw "APK ausente: $a. Rode: flutter build apk --release --split-per-abi" }
}

$existeRelease = & $gh release view v1.0.0 --json tagName 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Output 'Criando a release v1.0.0...'
  & $gh release create v1.0.0 $arquivos `
      --title 'LouvorJA para Android 1.0.0' `
      --notes-file .github\RELEASE_NOTES.md
} else {
  Write-Output 'Release ja existe; substituindo os APKs...'
  & $gh release upload v1.0.0 $arquivos --clobber
}

Write-Output ''
Write-Output 'Pronto. Links:'
& $gh repo view --json url -q .url
& $gh release view v1.0.0 --json url -q .url
Write-Output ''
Write-Output 'Repositorio privado: para alguem baixar o APK pelo link, adicione'
Write-Output 'a pessoa como colaboradora:'
Write-Output '    gh repo add-collaborator louvorja USUARIO'
