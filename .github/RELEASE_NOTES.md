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
  destacado e velocidade ajustável. Funciona nas dez traduções. Precisa da voz
  em português instalada no aparelho (Configurações → Idiomas → Conversão de
  texto em voz).
- **Letra maior**: botões A− e A+ no topo do leitor.

## Compartilhar

- **Versículo como imagem**: cartão quadrado sobre uma foto escolhida pelo tema
  do texto — um toque troca a imagem.
- **Como texto**: versículo, passagem, título da música ou a letra completa.

## O que vem dentro

- 75 álbuns em 9 categorias, com o ano no subtítulo
- Hinário Adventista (601 hinos) e o de 1996 (613), com busca por número
- 59.520 linhas de letra com tempo, sincronizadas com o áudio
- Bíblia completa em 10 traduções (311.045 versículos)
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
  acervo deriva de louvorja.com.br.
