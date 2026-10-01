# Bíblia de Estudo — com Ellen G. White e os pioneiros

App para **Android e Windows** que junta, em cada versículo:

- o texto em **12 traduções** (ARA, NAA, ARC, ACF, NVI, NVT, NTLH, KJA, ACRF,
  ARIB e as duas edições da Bíblia Livre), com as palavras de Jesus em
  vermelho e comparação lado a lado;
- os **trechos de Ellen G. White** que citam o versículo — 95 livros —, e os
  capítulos que narram a passagem ("Este capítulo é baseado em Mateus 4:1-11");
- os **pioneiros adventistas** (11 livros), entre eles *Daniel e Apocalipse*
  de Urias Smith, ligado **versículo a versículo**;
- **citações do Antigo Testamento no Novo** (e a recíproca), **passagens
  paralelas** (sinóticos; Samuel/Reis/Crônicas) e **referências cruzadas**
  ordenadas por relevância;
- **introdução a cada livro**: autor, data, local, tema, versículo-chave,
  esboço, mensagem, Cristo no livro e onde Ellen G. White trata dele;
- **notas de estudo** por versículo (opcionais; ver *Notas*, abaixo);
- marcações com cores, anotações, busca por referência ou por palavras;
- **atualização automática** no Android e no Windows.

No celular, tocar num versículo abre o painel de estudo por baixo; no PC (ou
tablet deitado), o painel fica fixo à direita, como as notas de uma Bíblia de
estudo aberta.

## Números

| | |
|---|---|
| Ligações versículo → parágrafo de Ellen G. White e pioneiros | 43.281 |
| Parágrafos indexados | 31.877 em 106 livros |
| Capítulos "baseados em" (narrativa da passagem) | 451 |
| Seções de comentário versículo a versículo (Urias Smith) | 273 |
| Referências cruzadas (OpenBible.info, ≥ 3 votos) | 213.579 |
| Citações AT ↔ NT detectadas | 368 (+ 284 alusões) |
| Passagens paralelas | 799 |

## Como os livros de Ellen G. White entram sem serem redistribuídos

Os e-books do [Centro de Pesquisas Ellen G. White](https://centrowhite.org.br/downloads/ebooks/)
e da [Adventist Pioneer Library](https://centrowhite.org.br/downloads/ebooks-apl/)
são gratuitos, mas a licença deles é **de uso pessoal e proíbe
redistribuir**. Por isso o app **não leva o texto de nenhum livro**:

1. No PC, `ferramentas/indexar_obras.py` baixa os PDFs, lê cada um com o
   PDFium e acha toda citação bíblica ("Mateus 4:2-4", "1 João 3:2",
   "Apocalipse 3:7, 8"). Para cada parágrafo que cita, guarda **só a posição**:
   página do PDF e intervalo de caracteres.
2. O app leva esse índice (4 MB). Quando a pessoa quer ler um trecho, o app
   baixa o PDF **do próprio site do Centro White**, para o aparelho dela —
   o mesmo download que faria pelo navegador — e recorta o parágrafo ali.
3. O leitor de PDF do app (pdfrx) usa o **mesmo PDFium** do indexador; o
   teste `test/indice_test.dart` confere que os dois recortam exatamente o
   mesmo parágrafo.

Se o Centro White trocar um PDF por outra edição, o app percebe (cada livro
tem tamanho e SHA-256 registrados) e passa a achar o parágrafo pela própria
citação nas páginas vizinhas. Para voltar à posição exata, rode o indexador
de novo e publique uma versão.

> Antes de divulgar amplamente, vale pedir ao Centro White uma confirmação
> de que esse uso (índice + download pelo próprio usuário) está de acordo com
> eles. Se autorizarem a redistribuição, dá para embutir os textos e o app
> funciona sem baixar nada.

## Estrutura

```
biblia/
  lib/dados/      bancos, consultas, PDFs, atualização
  lib/telas/      leitor, painel de estudo, biblioteca, busca, ajustes
  android/        app Android (Kotlin: instalador da atualização)
  windows/        app Windows
  assets/         biblia.db.gz (texto) e estudo.db.gz (estudo)
  ferramentas/    scripts Python que geram os dois bancos
  test/           testes (Dart); ferramentas/test_*.py (Python)
```

Fica dentro do repositório do Louvor JA porque reaproveita dele as traduções
(`../assets/louvorja_pt.db.gz`) e o mecanismo de atualização. É um projeto
Flutter independente: para movê-lo a um repositório próprio, copie a pasta e
troque `repositorio` em `lib/dados/atualizacao.dart` e `$repo` no
`publicar.ps1`.

## Ferramentas (gerar os bancos)

```bash
pip install pypdfium2           # e anthropic, para as notas
cd biblia
python ferramentas/construir_biblia.py   # texto, a partir do catálogo do Louvor JA
python ferramentas/indexar_obras.py      # baixa os 106 PDFs (~155 MB) e indexa
python ferramentas/construir_estudo.py   # junta tudo em assets/estudo.db.gz
```

Os PDFs e o índice intermediário ficam em `ferramentas/cache/` (fora do git).

Para acrescentar um livro: inclua-o em `ferramentas/obras.py` (arquivo, sigla,
prioridade) e rode os dois últimos comandos.

As introduções estão em `ferramentas/introducoes.json` — texto escrito para
este app, fácil de revisar e corrigir.

### Notas de estudo (opcional)

`ferramentas/gerar_notas.py` escreve notas curtas por versículo com a API do
Claude, no estilo das Bíblias de estudo: contexto histórico, sentido das
palavras no original, ligação com outras passagens e com os trechos de Ellen
G. White indexados para o capítulo (citados pela sigla e página, sem
inventar). Um pedido por capítulo, pela Batches API (metade do preço).

```bash
export ANTHROPIC_API_KEY=...
python ferramentas/gerar_notas.py --simular --livros 43   # vê o pedido e os tokens
python ferramentas/gerar_notas.py --livros 40-43          # evangelhos primeiro
python ferramentas/construir_estudo.py
```

O app avisa, junto de cada nota, que ela é gerada por IA. **Revise antes de
publicar**, a começar pelos livros que mais serão lidos.

## Testes

```bash
flutter test
python -m unittest ferramentas/test_referencias_pt.py ferramentas/test_texto_pdf.py
```

O teste de paridade PDFium (Python) × pdfrx (app) roda quando os PDFs estão
em `ferramentas/cache/pdf` e `PDFIUM_PATH` aponta para um `libpdfium`, por
exemplo o do pypdfium2:

```bash
PDFIUM_PATH=$(python -c "import pypdfium2_raw,os;print(os.path.join(os.path.dirname(pypdfium2_raw.__file__),'libpdfium.so'))") flutter test
```

## Atualização automática

Mesma regra dos outros apps: o app consulta um manifesto ao abrir e, havendo
versão nova, baixa e instala com a confirmação da pessoa. Também em
*Ajustes → Procurar atualização*.

- **Android**: APK por arquitetura, entregue ao `PackageInstaller`
  (`android/.../Atualizador.kt`, igual ao do Louvor JA).
- **Windows**: o app baixa o zip da release, confere (`versao.json` dentro
  dele), e um script espera o app fechar, copia os arquivos por cima e abre a
  versão nova. Os dados (livros baixados, marcações) ficam em `AppData`, fora
  da pasta do programa. Distribua o zip para ser extraído numa pasta do
  usuário (ex.: `%LOCALAPPDATA%\Biblia de Estudo`), não em *Arquivos de
  Programas*, onde o app não tem permissão de gravar.

Como o repositório é o do Louvor JA, cuja release *latest* os apps dele
consultam, este app publica em releases `biblia-vX.Y.Z` (com
`--latest=false`) e o manifesto numa release fixa, `biblia-atual`:

```
https://github.com/Wiserjr/louvorja/releases/download/biblia-atual/atualizacao-br.com.wisejr.bibliaestudo.json
```

Publicar (no PC com Windows, dentro de `biblia\`):

```powershell
powershell -ExecutionPolicy Bypass -File publicar.ps1
```

O script exige o número depois do `+` no `pubspec.yaml` maior que o publicado.

### Chave de assinatura

A atualização só entra por cima se o APK novo tiver **a mesma chave** do
instalado. Crie a chave **antes da primeira distribuição** e guarde cópia fora
do PC:

```powershell
keytool -genkey -v -keystore $env:USERPROFILE\biblia-estudo.jks -keyalg RSA -keysize 2048 -validity 10000 -alias biblia
```

e `android\key.properties` (fora do git):

```
storeFile=C:\\Users\\<voce>\\biblia-estudo.jks
storePassword=...
keyAlias=biblia
keyPassword=...
```

Sem ela, o release sai assinado com a chave de debug do PC que compilou.
