App Android offline com o acervo do LouvorJA — álbuns, hinários, letra
sincronizada, Bíblia e as coletâneas on-line.

## Instalação

Baixe o APK da arquitetura do seu aparelho e abra o arquivo no celular. Será
preciso permitir a instalação de "fontes desconhecidas" para este app.

| Arquivo | Para |
|---|---|
| `app-arm64-v8a-release.apk` | praticamente todo celular atual |
| `app-armeabi-v7a-release.apk` | aparelhos antigos, 32 bits |
| `app-x86_64-release.apk` | emuladores |

Na dúvida, use o **arm64-v8a**.

## Para quem tem dificuldade de ler

- **Ouvir a Bíblia**: o capítulo é lido em voz alta, com o versículo atual
  destacado e velocidade ajustável. Funciona nas doze traduções. Precisa da voz
  em português instalada no aparelho (Configurações → Idiomas → Conversão de
  texto em voz).
- **Letra maior**: botões A− e A+ no topo do leitor.

## Se você já tem o app instalado, leia isto

**As versões 1.0.0 a 1.0.3 não conseguiam se atualizar entre si.** Por um
descuido nosso, todas foram publicadas com o mesmo número interno de versão
(`versionCode`), e o Android se recusa a instalar por cima um APK cujo número
interno não é maior que o já instalado. Na prática: quem instalou a 1.0.0
continuou nela, mesmo baixando as seguintes — a instalação falhava, ou o
sistema a ignorava em silêncio.

A partir da **1.0.4** isso está corrigido, e as próximas atualizações vão
instalar normalmente. Só que esta ainda precisa de um empurrão:

> Se aparecer erro ao instalar por cima, **desinstale o app antigo** e instale
> este APK. Suas configurações se perdem (pasta das músicas, voz da leitura),
> mas as músicas já baixadas ficam no aparelho.

Para saber qual versão está instalada: *Configurações do Android → Apps →
Louvor JA*, e role até o fim. O app ainda não mostra isso na própria tela —
o "Versão do acervo" que aparece em *Ajustes* é outra coisa: é a versão do
catálogo de músicas, não a do aplicativo.

## Novidades desde a 1.0.0

Se você ficou preso numa versão antiga, é isto que chega de uma vez:

- **Versículo do dia** no topo da aba Bíblia. Um toque abre o capítulo no
  leitor; o ícone leva ao cartão de imagem. Funciona sem internet, em qualquer
  das doze traduções.
- **Bíblia Livre (BLIVRE)** em duas edições: `BLIVRE`, do texto crítico Nestle
  1904, e `BLIVRE-TR`, do Textus Receptus. É a única tradução do app com
  licença livre — Creative Commons Atribuição 3.0 Brasil.
- **Ouvir a Bíblia** com escolha de motor e voz, e **Bíblia em áudio** pela
  Bible Brain quando há chave configurada.
- **Download de músicas pelo app**, por álbum, categoria ou acervo inteiro.

## Compartilhar

- **Versículo como imagem**: cartão quadrado sobre uma foto escolhida pelo tema
  do texto — um toque troca a imagem.
- **Como texto**: versículo, passagem, título da música ou a letra completa.

## O que vem dentro

- 75 álbuns em 9 categorias, com o ano no subtítulo
- Hinário Adventista (601 hinos) e o de 1996 (613), com busca por número
- 59.520 linhas de letra com tempo, sincronizadas com o áudio
- Bíblia completa em 12 traduções (373.249 versículos)
- Coletâneas on-line: 5 canais, 16 playlists, 1.150 vídeos
- Busca no texto bíblico e busca global por álbuns e músicas

O catálogo inteiro cabe no APK. O áudio, não: são quase 14 GB.

## Como colocar as músicas

Duas formas, combináveis:

1. **Copiar a pasta** — no computador, `python ferramentas/empacotar.py --listar`
   mostra os álbuns; escolha os que quiser, gere a pasta e copie para o celular.
   Depois aponte o app para ela em *Ajustes → Pasta das músicas*.
2. **Baixar pelo app** — *Ajustes → Baixar músicas* permite baixar um álbum, uma
   categoria inteira ou todo o acervo, com estimativa de tamanho antes.

## Observações

- O app se mantém em dia com a API oficial: em *Ajustes → Versão do acervo* ele
  compara com o servidor e traz o que houver de novo.
- Esta versão é assinada com chave de depuração, adequada para instalação
  direta, não para publicação em loja.
- Músicas, capas e traduções bíblicas são de seus respectivos detentores; o
  acervo deriva de louvorja.com.br. A exceção é a **Bíblia Livre**, sob
  Creative Commons Atribuição 3.0 Brasil — crédito em *Ajustes → Créditos*.
