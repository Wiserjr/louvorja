import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:saf_stream/saf_stream.dart';

import '../dados/download.dart';
import '../dados/midia.dart';

import 'dart:io';
import 'dart:typed_data';

import '../dados/modelos.dart';
import '../dados/repositorio.dart';
import '../player/sincronia.dart';

class TelaPlayer extends StatefulWidget {
  const TelaPlayer({
    super.key,
    required this.musica,
    required this.nomeAlbum,
    required this.temAudio,
  });

  final Musica musica;

  /// Só o nome: a busca global abre o player sem ter o objeto do álbum em mãos.
  final String nomeAlbum;
  final bool temAudio;

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

  @override
  void initState() {
    super.initState();
    _preparar();
  }

  Future<void> _preparar() async {
    try {
      _slides = await _repo.slidesDe(widget.musica.id);
      _sinc = Sincronizador(_slides, usarTemposPlayback: _playback);

      final caminho = _playback
          ? (widget.musica.audioPlayback ?? widget.musica.audio)
          : widget.musica.audio;

      if (widget.temAudio && caminho != null) {
        final uri = await Midia.instancia.uriDe(caminho);
        if (uri != null) {
          // O ExoPlayer lê URIs content:// nativamente — é o que torna o
          // acesso via SAF viável sem copiar os arquivos para dentro do app.
          await _player.setAudioSource(AudioSource.uri(Uri.parse(uri)));
        }
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
          if (widget.musica.audioPlayback != null)
            IconButton(
              tooltip: _playback ? 'Ouvindo o playback' : 'Ouvindo a cantada',
              onPressed: _carregando ? null : _alternarPlayback,
              icon: Icon(_playback ? Icons.mic_off : Icons.mic),
            ),
        ],
        title: Text(widget.musica.nome),
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
                if (widget.temAudio) _controles(),
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
            _fundo(atual?.imagem ?? widget.musica.imagem),
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
        final bytes = snap.data;
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
    if (mounted) setState(() {});
    return dados;
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
                    IconButton(
                      iconSize: 36,
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
                      iconSize: 36,
                      onPressed: () => _player.seek(
                        _player.position + const Duration(seconds: 10),
                      ),
                      icon: const Icon(Icons.forward_10),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  static String _mmss(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
