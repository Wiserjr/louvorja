# Louvor JA — app Android

App offline com o acervo do LouvorJA desktop: álbuns, músicas com letra
sincronizada e a Bíblia em 7 traduções.

Não é uma conversão do `LouvorJA.exe` — aquele é um binário Delphi/VCL Win32 e
não tem como virar APK. O que se reaproveita aqui são os **dados**, que já
estavam numa camada desacoplada do executável.

## O que vem de onde

| Origem | Destino |
|---|---|
| `config/database.db` (91 MB) | `assets/louvorja_pt.db.gz` (19,7 MB) |
| `config/capas/*.bmp` (3,8 MB) | `assets/capas/*.webp` (293 KB) |
| `config/musicas/**` (14 GB) | pasta copiada para o celular, ou download |
| `config/imagens/**` (0,41 GB) | idem |

O catálogo tem 75 álbuns em 9 categorias, 1.889 músicas (incluindo os 601 hinos
do Hinário Adventista e os 613 do de 1996), 59.520 linhas de letra com tempo,
311.045 versículos em 10 traduções e as coletâneas on-line: 5 canais, 16
playlists e 1.150 vídeos.

### Sobre os caminhos de mídia

O catálogo guarda o caminho no formato da API (`musics/pt/Álbum/Faixa.mp3`), que
desde a versão 26.9 do programa é idêntico ao `files.dir` do banco local. A
instalação no Windows, porém, manteve os nomes de pasta antigos — a tradução
`musics/pt→musicas`, `images→imagens`, `covers→capas` vive em
`ferramentas/caminhos.py` e existe só do lado do PC. No celular, caminho do
catálogo, caminho na pasta copiada e caminho de download são a mesma string.

## Ferramentas (pasta `ferramentas/`)

Rodam no computador onde o LouvorJA está instalado.

Regerar o catálogo a partir do banco original:

```bash
python ferramentas/build_db.py
```

Ver os álbuns disponíveis e o tamanho de cada um:

```bash
python ferramentas/empacotar.py --listar
```

Montar a pasta para copiar ao celular (aceita `1,4,7-12` ou `todos`):

```bash
python ferramentas/empacotar.py --albuns 4,21,663 --destino "D:\LouvorJA"
```

Simular antes, só para ver o tamanho:

```bash
python ferramentas/empacotar.py --albuns todos --simular
```

Depois copie a pasta para o celular e aponte para ela em **Ajustes → Pasta das
músicas**. Álbuns adicionados depois são reconhecidos sem atualizar o app.

## Busca

O campo no topo da aba Álbuns varre o acervo inteiro: devolve **álbuns e
músicas** na mesma tela, cada faixa acompanhada do álbum de origem — "Santo,
Santo, Santo!" sozinho não diria que é do Hinário. Um termo numérico também casa
com o número da faixa, que nos hinários é o número do hino.

## Coletâneas on-line

Os vídeos do YouTube que o programa lista numa aba própria. A navegação inteira
— canais, playlists, vídeos — funciona **sem rede**, porque as miniaturas vêm
embutidas no catálogo: o banco de origem já as guardava em base64, e aqui elas
viram BLOB (4,4 MB de texto em ~3,3 MB de bytes). Só a reprodução exige conexão,
e acontece dentro do app pelo player oficial embutido do YouTube.

Detalhe da origem: o rótulo das miniaturas diz `image/png` mas os bytes são
JPEG. Guardar os bytes crus e deixar o decodificador identificar evita depender
desse rótulo.

## Baixar em lote

**Ajustes → Baixar músicas** permite escolher um álbum, uma categoria inteira ou
todo o acervo. O tamanho é estimado antes de começar e conta **apenas o que
falta** — quem já copiou metade à mão não deve ver 8 GB anunciados.

A fila vive fora das telas (`FilaDownload`), então sair da tela não interrompe um
lote de centenas de arquivos. O download é sequencial de propósito: em paralelo,
doze barras andariam devagar ao mesmo tempo e o conjunto pareceria travado, além
de sobrecarregar quem hospeda o acervo.

## Atualização automática pela API

O app compara sua versão de acervo com a publicada e traz o que houver de novo:

    GET /json_db/config          versão publicada (version_number)
    GET /json_db/pt_categories   índice: categorias -> álbuns
    GET /json_db/album_{id}      faixas do álbum
    GET /json_db/music_{id}      caminhos de mídia e letra completa

**A sincronização nunca apaga.** O índice publicado traz apenas as cinco
categorias de coletânea; os dois hinários, a Doxologia e as Infantis existem só
no catálogo extraído do desktop. Espelhar o remoto destruiria a maior parte do
acervo — por isso tudo é upsert.

Faixas novas entram primeiro incompletas (o índice do álbum não traz mídia nem
letra) e são completadas por `music_{id}` num segundo passo. Um toque longo em
"Versão do acervo" refaz a sincronização mesmo com o catálogo em dia.

## Arquitetura

- **Dois bancos, de propósito.** `louvorja_pt.db` é o catálogo, somente leitura,
  substituível por inteiro quando o acervo mudar. `usuario.db` guarda favoritos e
  o índice de mídia, e sobrevive à troca do catálogo.
- **Caminhos relativos.** O catálogo nunca guarda caminho absoluto, então o mesmo
  banco serve para qualquer aparelho, com a mídia onde couber.
- **SAF em vez de permissão de armazenamento.** O usuário escolhe a pasta pelo
  seletor do sistema; o app recebe URIs `content://` e o ExoPlayer os lê direto.
- **Tempos em milissegundos.** A conversão de `'00:01:23'` acontece na geração do
  banco, não durante a reprodução.
- **Capas sempre quadradas.** A arte de origem é quadrada (137×137, e 88×88 nas
  mais antigas). Exibi-la numa célula mais alta com `BoxFit.cover` cortava o topo
  e a base. A célula também é pequena de propósito: perto do tamanho nativo, a
  capa fica nítida em vez de ampliada. Um álbum — Músicas Infantis — não tem
  imagem cadastrada na origem, e ganha uma peça sólida na cor do próprio álbum.
- **Altura fixa para o título na grade.** Sem ela, um título de duas linhas
  empurra o subtítulo e as células da mesma fileira deixam de se alinhar.
- **`exibe_slide = 1` sempre.** As demais linhas são marcadores de tela em branco
  herdados da projeção do desktop, com `ms = 0`; incluí-las faria o player saltar
  para o instante zero no meio da música.
- **Futures memorizados, não resultados.** `Banco.catalogo` guarda o `Future` da
  abertura. Com `_catalogo ??= await _abrirCatalogo()` o await suspende antes da
  atribuição e dois chamadores simultâneos executam a abertura inteira em
  paralelo — foi assim que a limpeza de catálogos antigos passou a falhar.

## Sincronização da letra

`Sincronizador.indiceEm` (`lib/player/sincronia.dart`) reproduz o comportamento
da projeção do desktop:

- durante a introdução instrumental a tela fica limpa;
- o verso permanece até o próximo entrar;
- o último permanece até a música acabar.

Não há tempo arbitrado para "apagar a tela": quando o acervo quer a projeção
limpa, ele traz um slide de texto vazio com horário próprio — são 2.567 deles, e
o algoritmo os devolve como qualquer outro slide.

Verificado contra as 1.886 músicas do acervo: nenhuma lista fora de ordem,
nenhum tempo duplicado (que tornaria um slide invisível), nenhuma música com
verso entrando em 0 ms e nenhuma regressão de índice ao varrer o tempo.
Sete testes em `test/sincronia_test.dart`.

## Download pela API oficial

Além da pasta copiada à mão, o app baixa da API oficial. O endereço antigo
(`arquivos.louvorja.com.br`, gravado no banco de 2024) foi desativado; o atual é:

    GET https://api.louvorja.com.br/json_db/config       versão do acervo
    GET https://api.louvorja.com.br/json_db/music_{id}   música + letra + url_music
    GET https://api.louvorja.com.br/json_db/album_{id}   álbum + faixas
    GET https://api.louvorja.com.br/file{url_music}      o MP3

Os **ids de música são estáveis** desde 2024, então o catálogo local casa com a
API. Já o caminho do arquivo mudou (`musicas/…` virou `/musics/pt/…`, com
diferenças de maiúsculas nos acentos), por isso o app pergunta o `url_music` à
API em vez de derivá-lo do catálogo. O arquivo é gravado localmente no caminho
do catálogo, a mesma convenção da pasta copiada — a resolução de mídia não
precisa saber de onde veio.

O servidor ignora o cabeçalho `Range`: pedir um byte devolve o arquivo inteiro.
Por isso o teste de conexão usa `json_db/config`, de 115 bytes.

## Verificado no emulador

Android 36.1, x86_64:

- grade por categoria, com o ano como subtítulo;
- Hinário Adventista com busca por número — "43" leva a *Vem, Santo Espírito, Agora*;
- busca global: "santo" devolve 38 músicas, cada uma com seu álbum e duração;
- coletâneas on-line: playlists com miniaturas e reprodução do vídeo no app;
- download em lote: "Doxologia" estimou 48 faixas e 181 MB antes de iniciar;
- Bíblia nas 10 traduções;
- sincronização real com a API: *versão 184 → 184, 67 álbuns conferidos*;
- download de uma faixa e reprodução com letra sincronizada sobre a imagem de
  fundo, em maiúsculas — aos 31s o verso cujo tempo no catálogo é 31s.

## Pendente

- Licenças do Android SDK não aceitas (`flutter doctor --android-licenses`).
- O release é assinado com a chave de debug; publicar exige chave própria.
- O catálogo embutido é de agosto de 2024 (a API está na versão 184, de julho de
  2026). Atualizá-lo exige regerar o banco a partir de uma instalação recente do
  programa, ou passar a consumir `json_db` direto.

## Licenciamento

Os MP3, as capas e as traduções bíblicas são de terceiros, e o catálogo deriva do
acervo de louvorja.com.br. Uso pessoal ou na igreja local é uma coisa; distribuir
um APK com esse conteúdo é outra, e aí vale conversar com o autor do LouvorJA.
