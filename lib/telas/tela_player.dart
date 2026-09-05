import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:saf_stream/saf_stream.dart';

import '../dados/compartilhar.dart';
import '../dados/download.dart';
import '../dados/midia.dart';

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../dados/modelos.dart';
import '../dados/repositorio.dart';
import '../player/sincronia.dart';

class TelaPlayer extends StatefulWidget {
  const TelaPlayer({
    super.key,
    required this.fila,
    required this.indice,
    required this.nomeAlbum,
  });

  /// Abre o player numa música só, sem faixa seguinte.
  TelaPlayer.avulsa({
    Key? key,
    required Musica musica,
    required String nomeAlbum,
  }) : this(key: key, fila: [musica], indice: 0, nomeAlbum: nomeAlbum);

  /// As músicas que o player percorre, na ordem em que aparecem na tela de
  /// origem. Sem isto não há "próxima" — e sem próxima não há repetir nem
  /// aleatório, que são os modos de percorrê-la.
  final List<Musica> fila;

  /// Onde começar dentro de [fila].
  final int indice;

  /// Só o nome: a busca global abre o player sem ter o objeto do álbum em mãos.
  final String nomeAlbum;

  @override
  State<TelaPlayer> createState() => _TelaPlayerState();
}

class _TelaPlayerState extends State<TelaPlayer> {
  final _repo = const Repositorio();
  final _player = AudioPlayer();

  Sincronizador? _sinc;
  String? _erro;
  bool _carregando = true;

  /// Faixa instrumental em vez da cantada. O catálogo guarda tempos próprios
  /// para ela em `ms_pb`, então a letra continua sincronizada.
  bool _playback = false;
  List<Slide> _slides = const [];

  /// Caminho do fundo atual, resolvido sob demanda e memorizado: são 1.003
  /// imagens e a mesma se repete em vários slides seguidos.
  final Map<String, String?> _fundos = {};
  final Map<String, Uint8List?> _bytes = {};

  /// Último fundo que chegou a ser exibido.
  ///
  /// Serve de ponte enquanto o próximo carrega. Sem ele, a troca de slide para
  /// uma imagem ainda não lida pinta o fundo liso por um instante — e se a
  /// imagem não estiver na pasta, o app vai buscá-la na API e o liso fica.
  /// Numa projeção durante o culto isso aparece como se o slide travasse.
  Uint8List? _ultimoFundo;

  /// Ordem de reprodução: posições de `widget.fila`, não as músicas.
  ///
  /// No aleatório a lista é embaralhada em vez de sortear a cada faixa. Sorteio
  /// puro repete música antes de tocar todas, que é justamente a queixa comum
  /// contra o modo aleatório dos outros aplicativos.
  late List<int> _ordem;
  late int _pos;

  ModoRepeticao _repeticao = ModoRepeticao.nenhum;
  bool _aleatorio = false;
  bool _temAudio = false;

  Musica get _musica => widget.fila[_ordem[_pos]];
  bool get _temFila => widget.fila.length > 1;

  @override
  void initState() {
    super.initState();
    _ordem = List.generate(widget.fila.length, (i) => i);
    _pos = widget.indice.clamp(0, widget.fila.length - 1);
    _player.playerStateStream.listen(_aoMudarEstado);
    _preparar();
  }

  /// Avança sozinho quando a faixa termina, conforme o modo escolhido.
  void _aoMudarEstado(PlayerState estado) {
    if (estado.processingState != ProcessingState.completed) return;
    switch (_repeticao) {
      case ModoRepeticao.uma:
        _player.seek(Duration.zero);
        _player.play();
      case ModoRepeticao.todas:
        _irPara(_pos + 1);
      case ModoRepeticao.nenhum:
        // Sem repetição a fila acaba quando acaba: parar no fim é o esperado,
        // e voltar ao início surpreenderia quem deixou tocando.
        if (_pos + 1 < _ordem.length) _irPara(_pos + 1);
    }
  }

  Future<void> _irPara(int novaPos, {bool tocar = true}) async {
    if (_ordem.isEmpty) return;
    final pos = novaPos % _ordem.length;
    await _player.stop();
    setState(() {
      _pos = pos < 0 ? pos + _ordem.length : pos;
      _carregando = true;
      _erro = null;
      _playback = false;
      // Os caches de fundo são por música: a próxima tem as suas imagens.
      _fundos.clear();
      _bytes.clear();
    });
    await _preparar(tocarAoFim: tocar);
  }

  /// Volta ao início da faixa se ela já andou — como em qualquer player.
  void _anterior() {
    if (_player.position > const Duration(seconds: 3)) {
      _player.seek(Duration.zero);
      return;
    }
    _irPara(_pos - 1);
  }

  void _alternarAleatorio() {
    setState(() {
      _aleatorio = !_aleatorio;
      final atual = _ordem[_pos];
      _ordem = _aleatorio
          ? ordemAleatoria(widget.fila.length, atual)
          : List.generate(widget.fila.length, (i) => i);
      _pos = _ordem.indexOf(atual);
    });
  }

  Future<void> _preparar({bool tocarAoFim = false}) async {
    try {
      _slides = await _repo.slidesDe(_musica.id);
      _sinc = Sincronizador(_slides, usarTemposPlayback: _playback);

      // Sem await: o áudio não precisa esperar as imagens, e cada fundo que
      // chega já dispara o setState de _bytesDoFundo.
      unawaited(_precarregarFundos());

      final caminho = _playback
          ? (_musica.audioPlayback ?? _musica.audio)
          : _musica.audio;

      // Conferido aqui, não recebido pronto: cada faixa da fila tem o seu
      // arquivo, e a tela de origem só sabia da primeira.
      final uri = caminho == null ? null : await Midia.instancia.uriDe(caminho);
      _temAudio = uri != null;
      if (uri != null) {
        // O ExoPlayer lê URIs content:// nativamente — é o que torna o
        // acesso via SAF viável sem copiar os arquivos para dentro do app.
        await _player.setAudioSource(AudioSource.uri(Uri.parse(uri)));
        if (tocarAoFim) _player.play();
      }
    } catch (e) {
      _erro = '$e';
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _alternarPlayback() async {
    setState(() {
      _playback = !_playback;
      _carregando = true;
      _erro = null;
    });
    await _player.stop();
    await _preparar();
  }

  /// Resolve o fundo de um slide, memorizando o resultado.
  Future<String?> _fundoDe(String? rel) async {
    if (rel == null) return null;
    if (_fundos.containsKey(rel)) return _fundos[rel];
    final uri = await Midia.instancia.uriDe(rel);
    _fundos[rel] = uri;
    return uri;
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Compartilhar',
            icon: const Icon(Icons.share_outlined),
            onSelected: (opcao) {
              if (opcao == 'titulo') {
                Compartilhar.instancia.texto(
                  Compartilhar.textoDaMusica(
                    _musica,
                    album: widget.nomeAlbum.isEmpty ? null : widget.nomeAlbum,
                  ),
                );
              } else {
                Compartilhar.instancia.texto(
                  Compartilhar.textoDaLetra(
                    _musica,
                    _slides,
                    album: widget.nomeAlbum.isEmpty ? null : widget.nomeAlbum,
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'titulo',
                child: Text('Compartilhar o título'),
              ),
              // Só oferece a letra quando ela existe: um item que produz texto
              // vazio é pior do que item nenhum.
              if (_slides.any((s) => s.texto.trim().isNotEmpty))
                const PopupMenuItem(
                  value: 'letra',
                  child: Text('Compartilhar a letra'),
                ),
            ],
          ),
          if (_musica.audioPlayback != null)
            IconButton(
              tooltip: _playback ? 'Ouvindo o playback' : 'Ouvindo a cantada',
              onPressed: _carregando ? null : _alternarPlayback,
              icon: Icon(_playback ? Icons.mic_off : Icons.mic),
            ),
        ],
        title: Text(_musica.nome),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(18),
          child: Text(
            widget.nomeAlbum,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(child: _letra()),
                if (_erro != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Erro: $_erro',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_temAudio) _controles(),
              ],
            ),
    );
  }

  Widget _letra() {
    final sinc = _sinc;
    if (sinc == null || sinc.vazio) {
      return const Center(child: Text('Esta música não tem letra cadastrada.'));
    }

    return StreamBuilder<Duration>(
      stream: _player.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;

        Slide? atual;
        try {
          atual = sinc.slideEm(pos);
        } on UnimplementedError {
          return _pendente(context);
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            _fundo(atual?.imagem ?? _musica.imagem),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: atual == null || atual.texto.trim().isEmpty
                  // Antes do primeiro verso, e nos slides de texto vazio que o
                  // acervo usa para limpar a projeção, a tela fica só com o fundo.
                  ? const SizedBox.expand(key: ValueKey('vazio'))
                  : _versoProjetado(context, atual),
            ),
          ],
        );
      },
    );
  }

  /// Fundo do slide, no estilo da projeção do programa original.
  ///
  /// A imagem pode vir da pasta escolhida (`content://`) ou do download
  /// (`file://`). O `content://` não é legível por `Image.file`, então os bytes
  /// são lidos pelo SAF — e memorizados, porque a mesma imagem costuma valer
  /// para vários slides seguidos.
  Widget _fundo(String? rel) {
    if (rel == null) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      );
    }
    return FutureBuilder<Uint8List?>(
      future: _bytesDoFundo(rel),
      builder: (context, snap) {
        // Enquanto o próximo fundo não chega, segura o anterior em vez de
        // piscar o fundo liso.
        final bytes = snap.data ?? _ultimoFundo;
        if (bytes == null) {
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          );
        }
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        );
      },
    );
  }

  Future<Uint8List?> _bytesDoFundo(String rel) async {
    if (_bytes.containsKey(rel)) return _bytes[rel];
    var uri = await _fundoDe(rel);

    // Não está na pasta copiada? Busca no servidor. A imagem é pequena perto do
    // MP3 e fica em cache para os próximos slides.
    if (uri == null) {
      final f = await Download.instancia.baixarArquivo(rel);
      uri = f?.uri.toString();
      if (uri != null) _fundos[rel] = uri;
    }

    Uint8List? dados;
    try {
      if (uri == null) {
        dados = null;
      } else if (uri.startsWith('content://')) {
        dados = await SafStream().readFileBytes(uri);
      } else {
        dados = await File(Uri.parse(uri).toFilePath()).readAsBytes();
      }
    } catch (_) {
      dados = null;
    }
    _bytes[rel] = dados;
    if (dados != null) _ultimoFundo = dados;
    if (mounted) setState(() {});
    return dados;
  }

  /// Carrega os fundos da música toda antes que os slides comecem a trocar.
  ///
  /// São poucas imagens distintas por música — quase sempre uma ou duas — e
  /// resolvê-las de uma vez evita duas coisas: a espera no meio da reprodução,
  /// quando um slide entra e sua imagem ainda não foi lida, e a rajada de
  /// requisições à API que as buscas sob demanda geram numa música inteira.
  Future<void> _precarregarFundos() async {
    final rels = <String>{
      if (_musica.imagem != null) _musica.imagem!,
      for (final s in _slides)
        if (s.imagem != null) s.imagem!,
    };
    for (final rel in rels) {
      if (!mounted) return;
      await _bytesDoFundo(rel);
    }
  }

  /// O verso na tela: maiúsculas sobre faixa escura, como na projeção.
  Widget _versoProjetado(BuildContext context, Slide slide) {
    return Center(
      key: ValueKey(slide.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                child: Text(
                  slide.texto.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFFFFC107),
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
            ),
            if ((slide.textoAux ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Text(
                    slide.textoAux!.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Mostrado enquanto `Sincronizador.indiceEm` não estiver implementado.
  Widget _pendente(BuildContext context) => Center(
    child: Card(
      margin: const EdgeInsets.all(24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.construction, size: 40),
            const SizedBox(height: 12),
            Text(
              'Sincronização pendente',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Implemente Sincronizador.indiceEm em\n'
              'lib/player/sincronia.dart para a letra acompanhar o áudio.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _controles() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (context, snap) {
                final pos = snap.data ?? Duration.zero;
                final total = _player.duration ?? Duration.zero;
                final max = total.inMilliseconds.toDouble();
                return Column(
                  children: [
                    Slider(
                      value: pos.inMilliseconds
                          .clamp(0, total.inMilliseconds)
                          .toDouble(),
                      max: max <= 0 ? 1 : max,
                      onChanged: max <= 0
                          ? null
                          : (v) =>
                                _player.seek(Duration(milliseconds: v.toInt())),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [Text(_mmss(pos)), Text(_mmss(total))],
                    ),
                  ],
                );
              },
            ),
            StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (context, snap) {
                final tocando = snap.data?.playing ?? false;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_temFila)
                      IconButton(
                        iconSize: 32,
                        tooltip: 'Anterior',
                        onPressed: _anterior,
                        icon: const Icon(Icons.skip_previous),
                      ),
                    IconButton(
                      iconSize: 32,
                      tooltip: 'Voltar 10 segundos',
                      onPressed: () => _player.seek(
                        _player.position - const Duration(seconds: 10),
                      ),
                      icon: const Icon(Icons.replay_10),
                    ),
                    IconButton.filled(
                      iconSize: 44,
                      onPressed: () =>
                          tocando ? _player.pause() : _player.play(),
                      icon: Icon(tocando ? Icons.pause : Icons.play_arrow),
                    ),
                    IconButton(
                      iconSize: 32,
                      tooltip: 'Avançar 10 segundos',
                      onPressed: () => _player.seek(
                        _player.position + const Duration(seconds: 10),
                      ),
                      icon: const Icon(Icons.forward_10),
                    ),
                    if (_temFila)
                      IconButton(
                        iconSize: 32,
                        tooltip: 'Próxima',
                        onPressed: () => _irPara(_pos + 1),
                        icon: const Icon(Icons.skip_next),
                      ),
                  ],
                );
              },
            ),
            if (_temFila) _modos(),
          ],
        ),
      ),
    );
  }

  /// Aleatório, repetição e a posição na fila.
  ///
  /// Ficam numa linha própria, abaixo do transporte: são estados que ficam
  /// ligados, não ações momentâneas, e o realce colorido mostra isso sem
  /// precisar de rótulo.
  Widget _modos() {
    final cor = Theme.of(context).colorScheme;
    final (icone, dica) = switch (_repeticao) {
      ModoRepeticao.nenhum => (Icons.repeat, 'Repetir: desligado'),
      ModoRepeticao.todas => (Icons.repeat_on_outlined, 'Repetir: todas'),
      ModoRepeticao.uma => (Icons.repeat_one_on_outlined, 'Repetir: esta'),
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: _aleatorio ? 'Aleatório: ligado' : 'Aleatório: desligado',
          onPressed: _alternarAleatorio,
          isSelected: _aleatorio,
          color: _aleatorio ? cor.primary : null,
          icon: Icon(_aleatorio ? Icons.shuffle_on_outlined : Icons.shuffle),
        ),
        Text(
          '${_pos + 1} de ${widget.fila.length}',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        IconButton(
          tooltip: dica,
          // Percorre desligado → todas → esta, como na maioria dos players.
          onPressed: () => setState(() {
            _repeticao = ModoRepeticao
                .values[(_repeticao.index + 1) % ModoRepeticao.values.length];
          }),
          isSelected: _repeticao != ModoRepeticao.nenhum,
          color: _repeticao != ModoRepeticao.nenhum ? cor.primary : null,
          icon: Icon(icone),
        ),
      ],
    );
  }

  static String _mmss(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// Ordem embaralhada de [total] posições, começando por [atual].
///
/// Embaralhar a lista em vez de sortear a cada faixa é o que garante que toda
/// música toque uma vez antes de qualquer repetição — sorteio independente
/// repete cedo, que é a queixa comum contra o aleatório dos outros players.
///
/// [atual] fica na frente porque ela já está tocando quando o usuário liga o
/// modo: reembaralhar sem isso trocaria a música no meio.
List<int> ordemAleatoria(int total, int atual) {
  final resto = [
    for (var i = 0; i < total; i++)
      if (i != atual) i,
  ]..shuffle();
  return [atual, ...resto];
}

/// Como a fila se comporta quando a faixa termina.
enum ModoRepeticao {
  /// Toca até o fim da fila e para.
  nenhum,

  /// Volta ao começo da fila depois da última.
  todas,

  /// Repete a faixa atual indefinidamente.
  uma,
}
